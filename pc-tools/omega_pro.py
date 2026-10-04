#!/usr/bin/env python3
# ---------------------------------------------------------------------------
#  omega_pro.py  -  improved, PC-driven front-end around Omega.
#
#  Adds, on top of the original one-shot restore:
#    * inspect : read a NON-destructive snapshot of the device state that IS
#                readable from a PC (device info + installed provisioning
#                profiles, with expiry flags) and save it to JSON.
#    * diff    : compare two snapshots (before / after).
#    * plan    : print exactly which system files/domains the restore touches.
#    * backup  : full mobilebackup2 safety backup (reversibility) - heavy.
#    * run     : snapshot -> restore -> wait for reboot -> snapshot -> diff.
#
#  NOTE on limits: on a NON-jailbroken device there is no primitive to *read*
#  protected system files (trustd/valid.sqlite3, MobileIdentityData/*). The
#  backup/restore trick only *writes* them. So before/after is on the
#  observable state (device values + provisioning profiles + the change
#  manifest), not on the raw bytes of those protected databases.
# ---------------------------------------------------------------------------
import sys
import json
import asyncio
import datetime
from pathlib import Path

import hashlib
import warnings

import click
import requests
from cryptography import x509
from cryptography.x509 import ocsp
from cryptography.x509.oid import AuthorityInformationAccessOID, ExtensionOID
from cryptography.hazmat.primitives import hashes, serialization

from sparserestore import backup, perform_restore
from pymobiledevice3.exceptions import NoDeviceConnectedError
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.misagent import MisagentService


def _silence_asyncio_shutdown_noise(unraisable):
    # pymobiledevice3 leaves an SSL connection to be garbage-collected after the
    # asyncio event loop has already closed -> harmless "Event loop is closed".
    exc = unraisable.exc_value
    if isinstance(exc, RuntimeError) and "Event loop is closed" in str(exc):
        return
    sys.__unraisablehook__(unraisable)


sys.unraisablehook = _silence_asyncio_shutdown_noise

SNAP_DIR = Path.cwd() / "omega_snapshots"
DEVICE_KEYS = [
    "DeviceName", "ProductType", "ProductVersion", "BuildVersion",
    "UniqueDeviceID", "ActivationState", "CPUArchitecture", "AirplaneMode",
]

# PC equivalent of the on-device "wipe + empty + chflags schg" method.
# A restore can't delete files or set schg, so:
#   * ban-lists are written as VALID EMPTY <array/> plists (like the snippet) -
#     installd reads them as "nothing is banned". (Writing a directory here was
#     a bug: installd can't parse a directory as a plist and keeps the ban.)
#   * the OCSP cache files are replaced by empty DIRECTORIES so trustd can't
#     open them to persist a revocation verdict.
EMPTY_PLIST = (b'<?xml version="1.0" encoding="UTF-8"?>\n'
               b'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
               b'"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
               b'<plist version="1.0">\n<array>\n</array>\n</plist>\n')

# Ban-lists -> empty plist FILES.
BAN_LISTS = [
    ("DatabaseDomain", "MobileIdentityData/AuthListBannedUpps.plist", "ban-list"),
    ("DatabaseDomain", "MobileIdentityData/AuthListBannedCdHashes.plist", "ban-list"),
    ("DatabaseDomain", "MobileIdentityData/Rejections.plist", "ban-list"),
    ("DatabaseDomain", "MobileIdentityData/Indeterminates.plist", "ban-list"),
]
# OCSP cache -> empty directories (block writes). This is where REVOKED lives.
LOCKED_TARGETS = [
    ("ProtectedDomain", "trustd/private/ocspcache.sqlite3", "ocsp-cache"),
    ("ProtectedDomain", "trustd/private/ocspcache.sqlite3-shm", "ocsp-cache"),
    ("ProtectedDomain", "trustd/private/ocspcache.sqlite3-wal", "ocsp-cache"),
    ("ProtectedDomain", "trustd/private/ocspcache.sqlite3-journal", "ocsp-cache"),
]
# Optional (--valid): trustd's valid DB. Original Omega locked it; the snippet
# leaves it alone because it also backs general certificate trust.
VALID_TARGETS = [
    ("ProtectedDomain", "trustd/valid.sqlite3", "cert-validity"),
    ("ProtectedDomain", "trustd/valid.sqlite3-shm", "cert-validity"),
    ("ProtectedDomain", "trustd/valid.sqlite3-wal", "cert-validity"),
]
# Parent directories that must be present in the backup for the above.
PARENT_DIRS = [
    ("DatabaseDomain", ""), ("DatabaseDomain", "MobileIdentityData"),
    ("ProtectedDomain", ""), ("ProtectedDomain", "trustd"), ("ProtectedDomain", "trustd/private"),
]
CONFIG_DOMAIN = "SysSharedContainerDomain-systemgroup.com.apple.configurationprofiles"
# Written by original Omega so the device skips Setup Assistant after restore.
SKIP_SETUP_FILES = [
    (CONFIG_DOMAIN, "Library/ConfigurationProfiles/CloudConfigurationDetails.plist",
     "files/CloudConfigurationDetails.plist"),
    ("ManagedPreferencesDomain", "mobile/com.apple.purplebuddy.plist",
     "files/com.apple.purplebuddy.plist"),
]


def _dir_targets(include_valid):
    """Entries replaced by an empty directory."""
    return LOCKED_TARGETS + (VALID_TARGETS if include_valid else [])


def _targets(include_valid):
    """All neutralised targets, for display."""
    return BAN_LISTS + _dir_targets(include_valid)


def _build_backup(include_valid):
    files = [backup.Directory(path, domain) for domain, path in PARENT_DIRS]
    # ban-lists -> valid empty plist files
    files += [backup.ConcreteFile(path, domain, contents=EMPTY_PLIST)
              for domain, path, _ in BAN_LISTS]
    # ocsp cache (+ optional valid.sqlite3) -> empty directories
    files += [backup.Directory(path, domain) for domain, path, _ in _dir_targets(include_valid)]
    files += [
        backup.Directory("", CONFIG_DOMAIN),
        backup.Directory("Library", CONFIG_DOMAIN),
        backup.Directory("Library/ConfigurationProfiles", CONFIG_DOMAIN),
        backup.Directory("", "ManagedPreferencesDomain"),
        backup.Directory("mobile", "ManagedPreferencesDomain"),
    ]
    files += [backup.ConcreteFile(path, domain, contents=(Path.cwd() / src).read_bytes())
              for domain, path, src in SKIP_SETUP_FILES]
    return backup.Backup(files=files)


_ISSUERS = {}
_CERT_STATUS = {}


def _cert_status(der):
    """Ask Apple's OCSP responder whether a developer certificate is revoked.

    A profile can be far from its expiry date and still be dead: Apple revokes
    the signing certificate, and iOS learns it through this same OCSP check.
    Returns a dict cached per certificate (many profiles share one cert).
    """
    fp = hashlib.sha1(der).hexdigest()
    if fp in _CERT_STATUS:
        return _CERT_STATUS[fp]
    info = {"status": "UNKNOWN", "revoked_at": None, "cert_expires": None, "cert_cn": None}
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            cert = x509.load_der_x509_certificate(der)
            info["cert_cn"] = cert.subject.rfc4514_string()
        info["cert_expires"] = cert.not_valid_after_utc
        aia = cert.extensions.get_extension_for_oid(ExtensionOID.AUTHORITY_INFORMATION_ACCESS).value
        ocsp_url = next(d.access_location.value for d in aia
                        if d.access_method == AuthorityInformationAccessOID.OCSP)
        ca_url = next(d.access_location.value for d in aia
                      if d.access_method == AuthorityInformationAccessOID.CA_ISSUERS)
        if ca_url not in _ISSUERS:
            raw = requests.get(ca_url, timeout=10).content
            try:
                _ISSUERS[ca_url] = x509.load_der_x509_certificate(raw)
            except ValueError:
                _ISSUERS[ca_url] = x509.load_pem_x509_certificate(raw)
        req = ocsp.OCSPRequestBuilder().add_certificate(cert, _ISSUERS[ca_url], hashes.SHA1()).build()
        r = requests.post(ocsp_url, data=req.public_bytes(serialization.Encoding.DER),
                          headers={"Content-Type": "application/ocsp-request"}, timeout=10)
        resp = ocsp.load_der_ocsp_response(r.content)
        if resp.response_status == ocsp.OCSPResponseStatus.SUCCESSFUL:
            info["status"] = resp.certificate_status.name  # GOOD / REVOKED / UNKNOWN
            info["revoked_at"] = resp.revocation_time_utc
    except Exception as e:
        info["status"] = f"ERR:{type(e).__name__}"
    _CERT_STATUS[fp] = info
    return info


def _json_default(o):
    if isinstance(o, (datetime.datetime, datetime.date)):
        return o.isoformat()
    if isinstance(o, (bytes, bytearray)):
        return f"<{len(o)} bytes>"
    return str(o)


async def _connect(exit_on_missing=True):
    try:
        return await create_using_usbmux()
    except NoDeviceConnectedError:
        if not exit_on_missing:
            raise
        click.secho("No device detected! Connect your device via USB and try again.", fg="red")
        sys.exit(1)


async def _snapshot(label, exit_on_missing=True):
    lockdown = await _connect(exit_on_missing)

    info = {}
    for k in DEVICE_KEYS:
        try:
            info[k] = await lockdown.get_value(key=k)
        except Exception as e:
            info[k] = f"<err: {e}>"

    mis = MisagentService(lockdown=lockdown)
    raw = await mis.copy_all()
    now = datetime.datetime.now(datetime.timezone.utc)

    profiles = []
    expired = revoked = 0
    for p in raw:
        pl = getattr(p, "plist", {}) or {}
        exp = pl.get("ExpirationDate")
        is_expired = None
        if isinstance(exp, datetime.datetime):
            e = exp if exp.tzinfo else exp.replace(tzinfo=datetime.timezone.utc)
            is_expired = e < now

        # Revocation (blacklist) of the signing certificate, via Apple's OCSP.
        certs = [_cert_status(der) for der in pl.get("DeveloperCertificates", [])]
        cert = next((c for c in certs if c["status"] == "REVOKED"), certs[0] if certs else {})
        cert_status = cert.get("status", "NO-CERT")
        cert_exp = cert.get("cert_expires")
        cert_expired = bool(cert_exp and cert_exp < now)

        if cert_status == "REVOKED":
            state = "REVOKED"
            revoked += 1
        elif is_expired or cert_expired:
            state = "EXPIRED"
            expired += 1
        elif cert_status == "GOOD":
            state = "OK"
        else:
            state = cert_status  # UNKNOWN / ERR:... (OCSP unreachable, e.g. DNS-blocked)

        profiles.append({
            "Name": pl.get("Name"),
            "AppIDName": pl.get("AppIDName"),
            "TeamName": pl.get("TeamName"),
            "TeamIdentifier": (pl.get("TeamIdentifier") or [None])[0]
                if isinstance(pl.get("TeamIdentifier"), list) else pl.get("TeamIdentifier"),
            "UUID": pl.get("UUID"),
            "ExpirationDate": exp,
            "expired": is_expired,
            "state": state,
            "cert_status": cert_status,
            "revoked_at": cert.get("revoked_at"),
            "cert_expires": cert_exp,
            "cert_cn": cert.get("cert_cn"),
        })

    order = {"REVOKED": 0, "EXPIRED": 1}
    profiles.sort(key=lambda x: (order.get(x["state"], 2 if x["state"] != "OK" else 3),
                                 (x["Name"] or "").lower()))

    snap = {
        "label": label,
        "captured_at": now,
        "device": info,
        "profile_count": len(profiles),
        "expired_count": expired,
        "revoked_count": revoked,
        "profiles": profiles,
    }
    return snap


def _save(snap):
    SNAP_DIR.mkdir(exist_ok=True)
    ts = snap["captured_at"].strftime("%Y%m%d_%H%M%S")
    path = SNAP_DIR / f"snapshot_{snap['label']}_{ts}.json"
    path.write_text(json.dumps(snap, indent=2, default=_json_default), encoding="utf-8")
    return path


def _print_snapshot(snap):
    d = snap["device"]
    click.secho(f"\nDevice : {d.get('DeviceName')}  ({d.get('ProductType')}, "
                f"iOS {d.get('ProductVersion')} / {d.get('BuildVersion')})", fg="cyan")
    click.secho(f"UDID   : {d.get('UniqueDeviceID')}", fg="cyan")
    air = d.get("AirplaneMode")
    click.secho(f"Airplane mode : {'ON (offline - safe for restore)' if air else 'OFF (device is online!)'}",
                fg="green" if air else "red")
    bad = snap.get("revoked_count", 0) + snap["expired_count"]
    click.secho(f"Profiles installed : {snap['profile_count']}   "
                f"(revoked/blacklisted: {snap.get('revoked_count', 0)}, "
                f"expired: {snap['expired_count']})",
                fg="red" if bad else "green")
    click.echo("  " + "-" * 86)
    click.echo(f"  {'STATE':8} {'Name':28.28} {'Team':22.22} {'Revoked on':10} {'Expires':10}")
    click.echo("  " + "-" * 86)
    colors = {"REVOKED": "red", "EXPIRED": "yellow", "OK": "green"}
    for p in snap["profiles"]:
        state = p.get("state", "EXPIRED" if p["expired"] else "OK")
        exp = p["ExpirationDate"]
        exp = exp.strftime("%Y-%m-%d") if isinstance(exp, datetime.datetime) else str(exp or "-")[:10]
        rev = p.get("revoked_at")
        rev = rev.strftime("%Y-%m-%d") if isinstance(rev, datetime.datetime) else str(rev or "-")[:10]
        click.echo("  " + click.style(f"{state[:8]:8}", fg=colors.get(state, "magenta")) +
                   f" {str(p['Name'] or '-'):28.28} {str(p['TeamName'] or '-'):22.22} {rev:10} {exp:10}")


def _diff(before, after):
    click.secho("\n=== BEFORE / AFTER ===", fg="magenta", bold=True)
    click.echo(f"Profiles : {before['profile_count']} -> {after['profile_count']}"
               f"   (delta {after['profile_count'] - before['profile_count']:+d})")
    click.echo(f"Expired  : {before['expired_count']} -> {after['expired_count']}"
               f"   (delta {after['expired_count'] - before['expired_count']:+d})")
    br, ar = before.get("revoked_count"), after.get("revoked_count")
    if br is not None and ar is not None:
        click.echo(f"Revoked  : {br} -> {ar}   (delta {ar - br:+d})")

    def state(p):
        return p.get("state", "EXPIRED" if p["expired"] else "OK")

    b = {p["UUID"]: p for p in before["profiles"]}
    a = {p["UUID"]: p for p in after["profiles"]}
    removed = [b[u] for u in b if u not in a]
    added = [a[u] for u in a if u not in b]
    changed = [(b[u], a[u]) for u in a if u in b and state(b[u]) != state(a[u])]

    for title, items, color in (("Removed profiles", removed, "red"),
                                ("Added profiles", added, "green")):
        click.secho(f"\n{title}: {len(items)}", fg=color)
        for p in items[:20]:
            click.echo(f"  - [{state(p)}] {p['Name']}  ({p['TeamName']})")
    click.secho(f"\nState changed: {len(changed)}", fg="yellow")
    for old, new in changed[:20]:
        click.echo(f"  - {new['Name']}  ({new['TeamName']}): {state(old)} -> {state(new)}")


# --------------------------------------------------------------------------- CLI
@click.group()
def cli():
    """Improved PC-driven front-end around Omega (inspect / diff / plan / run)."""


@cli.command()
@click.option("--label", default="snapshot", help="Label stored in the snapshot file.")
def inspect(label):
    """Read + save a non-destructive snapshot of the device state."""
    snap = asyncio.run(_snapshot(label))
    path = _save(snap)
    _print_snapshot(snap)
    click.secho(f"\nSaved -> {path}", fg="green")


@cli.command()
@click.argument("before_json", type=click.Path(exists=True))
@click.argument("after_json", type=click.Path(exists=True))
def diff(before_json, after_json):
    """Compare two snapshot JSON files."""
    before = json.loads(Path(before_json).read_text(encoding="utf-8"))
    after = json.loads(Path(after_json).read_text(encoding="utf-8"))
    _diff(before, after)


@cli.command()
@click.option("--valid", "include_valid", is_flag=True, help="Also lock trustd/valid.sqlite3.")
def plan(include_valid):
    """Show exactly which system files the restore will replace."""
    click.secho("EMPTY PLIST (valid <array/> file so installd sees an empty ban-list):", fg="yellow")
    click.echo(f"  {'TYPE':14} {'DOMAIN':16} PATH")
    click.echo("  " + "-" * 78)
    for domain, path, kind in BAN_LISTS:
        click.echo(f"  {kind:14} {domain:16} {path}")
    click.secho("\nEMPTY DIR (daemon can't open it to persist a verdict):", fg="yellow")
    for domain, path, kind in _dir_targets(include_valid):
        click.echo(f"  {kind:14} {domain:16} {path}")
    click.secho("\nWRITTEN (skip Setup Assistant after restore, from original Omega):", fg="yellow")
    for domain, path, _ in SKIP_SETUP_FILES:
        click.echo(f"  {'skip-setup':14} {domain[:16]:16} {path}")
    click.secho("\nNOT DONE from PC (on-device .deb only): delete mis.db, chflags schg.", fg="cyan")


@cli.command()
@click.option("--out", default="omega_safety_backup", help="Backup output directory.")
def backup_device(out):
    """Full mobilebackup2 safety backup (heavy / slow). Reversibility."""
    from pymobiledevice3.services.mobilebackup2 import Mobilebackup2Service

    async def _run():
        lockdown = await _connect()
        Path(out).mkdir(exist_ok=True)
        click.secho(f"Starting full backup to ./{out} (this can take a long time)...", fg="yellow")
        svc = Mobilebackup2Service(lockdown)
        await svc.backup(backup_directory=out)
        click.secho("Backup finished.", fg="green")

    asyncio.run(_run())


HOTSPOT_SCRIPT = Path(__file__).with_name("offline_hotspot.ps1")


def _hotspot(action):
    """Drive offline_hotspot.ps1 (needs Windows PowerShell 5.1 for WinRT)."""
    import subprocess
    out = subprocess.run(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
         "-File", str(HOTSPOT_SCRIPT), "-Action", action],
        capture_output=True, text=True).stdout
    clients = 0
    for line in out.splitlines():
        if line.startswith("Clients"):
            try:
                clients = int(line.split(":")[1].split("/")[0])
            except ValueError:
                pass
    return out.strip(), clients


def _wait_hotspot_client(timeout=180):
    import time
    deadline = time.time() + timeout
    while time.time() < deadline:
        _, clients = _hotspot("status")
        if clients > 0:
            return True
        click.echo(f"  ...waiting for the iPad to join 'Omega-Offline' ({int(deadline - time.time())}s left)")
        time.sleep(5)
    return False


@cli.command()
@click.option("--on", "state", flag_value="start", default=True, help="Start the offline hotspot.")
@click.option("--off", "state", flag_value="stop", help="Stop the offline hotspot.")
@click.option("--status", "state", flag_value="status", help="Show hotspot status.")
def hotspot(state):
    """Offline Wi-Fi hotspot 'Omega-Offline' (no internet behind it)."""
    out, _ = _hotspot(state)
    click.echo(out)


@cli.command()
@click.option("--yes", is_flag=True, help="Skip the confirmation prompt.")
@click.option("--hotspot", "use_hotspot", is_flag=True,
              help="Start the offline 'Omega-Offline' hotspot and require the iPad to be on it "
                   "(instead of Airplane mode).")
@click.option("--allow-online", is_flag=True,
              help="Proceed even if Airplane mode is OFF (not recommended: lets iOS re-check/revoke).")
@click.option("--valid", "include_valid", is_flag=True, help="Also lock trustd/valid.sqlite3.")
def run(yes, use_hotspot, allow_online, include_valid):
    """BEFORE snapshot -> restore (REBOOTS device) -> AFTER snapshot -> diff."""
    click.secho("This performs the real, destructive restore and REBOOTS your device.", fg="red")
    click.secho("The USB link drops during reboot; keep the cable connected.", fg="red")

    # Preflight: the device must not reach Apple during the restore and the
    # early-boot window. Either Airplane mode (preserved across reboot) or the
    # offline hotspot (iPad auto-rejoins it after reboot, no internet behind it).
    offline_ok = False
    if use_hotspot:
        click.secho("\nStarting offline hotspot 'Omega-Offline'...", fg="yellow")
        out, clients = _hotspot("start")
        click.echo(out)
        if clients == 0:
            click.secho("On the iPad: join Wi-Fi 'Omega-Offline' (password: omegaoffline), "
                        "and turn OFF Auto-Join on every other known network.", fg="yellow")
        offline_ok = _wait_hotspot_client()
        if not offline_ok:
            click.secho("The iPad never joined 'Omega-Offline'. Aborted.", fg="red")
            return
        click.secho("iPad is on the offline hotspot.", fg="green")

    before = asyncio.run(_snapshot("before"))
    if not offline_ok and not before["device"].get("AirplaneMode") and not allow_online:
        click.secho(
            "\nAirplane mode is OFF. Enable Airplane mode (and turn Wi-Fi off) on the "
            "iPad FIRST so it reboots offline and cannot re-check/revoke the certificate.\n"
            "Then re-run, or pass --allow-online to override.", fg="red")
        return

    if not yes and input('Type "CONTINUE" to proceed: ').strip() != "CONTINUE":
        click.secho("Aborted.", fg="yellow")
        return

    bpath = _save(before)
    _print_snapshot(before)
    click.secho(f"BEFORE saved -> {bpath}", fg="green")

    asyncio.run(_do_restore(include_valid))

    click.secho("\nWaiting for the device to GO DOWN (confirming the reboot)...", fg="yellow")
    rebooted = asyncio.run(_wait_for_down(timeout=120))
    if not rebooted:
        click.secho("WARNING: the device never dropped off USB - the restore may NOT have "
                    "triggered a reboot, so nothing was applied. Check the iPad screen.", fg="red")
    else:
        click.secho("Device went down (rebooting). Now waiting for it to come back "
                    "(up to 8 min)... Unlock the iPad once it boots.", fg="yellow")

    after = asyncio.run(_wait_and_snapshot("after", timeout=480))
    if after is None:
        click.secho("\nDevice did not come back in time. Once it's up and unlocked, run:\n"
                    "  python omega_pro.py inspect --label after\n"
                    f"  python omega_pro.py diff \"{bpath}\" omega_snapshots\\snapshot_after_*.json",
                    fg="yellow")
        return
    apath = _save(after)
    _print_snapshot(after)
    click.secho(f"AFTER saved -> {apath}", fg="green")
    _diff(before, after)


async def _do_restore(include_valid=False):
    lockdown = await _connect()
    back = _build_backup(include_valid)
    click.secho(f"Restoring backup ({len(_targets(include_valid))} locked targets)...", fg="yellow")
    await perform_restore(back, client=lockdown, reboot=True)
    click.secho("Restore sent; device should reboot.", fg="green")


async def _wait_for_down(timeout=120):
    """Return True once the device stops answering lockdown (i.e. it rebooted).

    Requires a sustained disconnect (3 consecutive misses) so a brief blip
    doesn't count. This guarantees the later snapshot is taken post-reboot.
    """
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    misses = 0
    while loop.time() < deadline:
        try:
            await _connect(exit_on_missing=False)
            misses = 0
        except Exception:
            misses += 1
            if misses >= 3:
                return True
        await asyncio.sleep(3)
    return False


async def _wait_and_snapshot(label, timeout=480):
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while loop.time() < deadline:
        try:
            return await _snapshot(label, exit_on_missing=False)
        except Exception:
            # Device still rebooting / not yet unlocked / not paired again.
            remaining = int(deadline - loop.time())
            click.echo(f"  ...not back yet ({remaining}s left)", err=True)
            await asyncio.sleep(5)
    return None


if __name__ == "__main__":
    cli()
