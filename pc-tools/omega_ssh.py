#!/usr/bin/env python3
# ---------------------------------------------------------------------------
#  omega_ssh.py  -  drive a JAILBROKEN device over SSH-through-USB.
#
#  Needs OpenSSH (pkg: openssh) installed on the device. This script opens a
#  usbmux TCP forward (local 2222 -> device 22) with pymobiledevice3, then
#  connects with paramiko (root/alpine by default) so it can read, edit and
#  test the real revocation files live - and so the exact on-device method can
#  be verified before baking it into the .deb.
#
#  Commands:
#    diag          read-only inspection of the revocation DBs / ban-lists
#    clean         apply the full method live (wipe + empty plist + schg +
#                  delete mis.db + restart daemons), then re-diag
#    exec "<cmd>"  run an arbitrary shell command on the device
# ---------------------------------------------------------------------------
import sys
import time
import shlex
import subprocess

import click

try:
    import paramiko
except ImportError:
    paramiko = None


class Device:
    def __init__(self, local_port, device_port, password, udid=None, user="mobile"):
        self.local_port = local_port
        self.device_port = device_port
        self.password = password
        self.udid = udid
        self.user = user
        self._fwd = None
        self._cli = None

    def __enter__(self):
        if paramiko is None:
            raise SystemExit("paramiko is required: pip install paramiko")
        cmd = [sys.executable, "-m", "pymobiledevice3", "usbmux", "forward",
               str(self.local_port), str(self.device_port), "--host", "127.0.0.1"]
        if self.udid:
            cmd += ["--udid", self.udid]
        self._fwd = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self._cli = paramiko.SSHClient()
        self._cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        last = None
        for _ in range(12):  # the forward needs a moment to bind
            time.sleep(1)
            try:
                self._cli.connect("127.0.0.1", port=self.local_port, username=self.user,
                                  password=self.password, look_for_keys=False,
                                  allow_agent=False, timeout=8, banner_timeout=8)
                return self
            except Exception as e:  # noqa: BLE001
                last = e
        raise SystemExit(f"SSH connect failed (is OpenSSH installed + device unlocked?): {last}")

    def __exit__(self, *exc):
        if self._cli:
            self._cli.close()
        if self._fwd:
            self._fwd.terminate()

    def run(self, script, echo=True):
        """Run a shell script as root. If logged in as non-root, escalate with
        `sudo -S sh -s`, feeding the password then the script on stdin."""
        if self.user == "root":
            stdin, out, err = self._cli.exec_command("sh -s", timeout=120)
            stdin.write(script + "\n")
        else:
            stdin, out, err = self._cli.exec_command("sudo -S sh -s", timeout=120)
            stdin.write(self.password + "\n")   # consumed by sudo -S
            stdin.write(script + "\n")           # consumed by the root sh
        stdin.flush()
        stdin.channel.shutdown_write()
        o = out.read().decode(errors="replace")
        e = err.read().decode(errors="replace")
        # strip sudo's lecture / prompt noise from stderr
        e = "\n".join(l for l in e.splitlines()
                      if l.strip() and "password for" not in l and "usual lecture" not in l
                      and not l.startswith(("    #", "We trust", "For security")))
        if echo:
            if o.strip():
                click.echo(o.rstrip())
            if e.strip():
                click.secho(e.rstrip(), fg="red")
        return o, e


DIAG = r'''
echo "### uname / id"; uname -a; id
echo; echo "### MobileIdentityData"; ls -leO /private/var/db/MobileIdentityData/ 2>&1
for f in AuthListBannedUpps AuthListBannedCdHashes Rejections Indeterminates; do
  p=/private/var/db/MobileIdentityData/$f.plist
  echo; echo "### $f.plist"; ls -leO "$p" 2>&1
  plutil -p "$p" 2>&1 | head -30
done
echo; echo "### trustd/private"; ls -leO /private/var/protected/trustd/private/ 2>&1
echo; echo "### ocspcache tables + row counts"
db=/private/var/protected/trustd/private/ocspcache.sqlite3
sqlite3 "$db" ".tables" 2>&1
for t in responses ocsp; do sqlite3 "$db" "select count(*) from $t;" 2>&1 | sed "s/^/$t rows: /"; done
echo; echo "### ProvisioningProfiles"; ls -leO /private/var/MobileDevice/ProvisioningProfiles/ 2>&1
echo; echo "### valid.sqlite3"; ls -leO /private/var/protected/trustd/valid.sqlite3* 2>&1
'''

# Exact on-device method, run live over SSH. Mirrors the .deb worker.
CLEAN = r'''
set -u
MID=/private/var/db/MobileIdentityData
OCSP=/private/var/protected/trustd/private
PROF=/private/var/MobileDevice/ProvisioningProfiles
EMPTY='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
</array>
</plist>'
chflags -R noschg,nouchg "$MID" "$OCSP" 2>/dev/null
# Only the 4 ban-lists are touched (NOT mis.db: on this device profiles live
# inside mis.db with no .mobileprovision backups, so deleting it wipes them).
for f in AuthListBannedUpps AuthListBannedCdHashes Rejections Indeterminates; do
  rm -rf "$MID/$f.plist"                       # may be a leftover broken directory
  printf '%s\n' "$EMPTY" > "$MID/$f.plist"     # valid empty <array/> plist
  chflags schg "$MID/$f.plist"; echo "locked $f.plist"
done
rm -f "$OCSP"/ocspcache.sqlite3 "$OCSP"/ocspcache.sqlite3-shm "$OCSP"/ocspcache.sqlite3-wal
: > "$OCSP/ocspcache.sqlite3"; chflags schg "$OCSP/ocspcache.sqlite3"; echo "locked empty ocspcache"
for d in trustd installd misagentd amfid; do killall -9 "$d" 2>/dev/null && echo "restarted $d"; done
echo DONE
'''


@click.group()
def cli():
    """Drive a jailbroken device over SSH-through-USB (needs pkg: openssh)."""


def _opts(f):
    f = click.option("--port", default=22, help="Device SSH port (OpenSSH=22, Dropbear/palera1n=44).")(f)
    f = click.option("--local-port", default=2222, help="Local port for the USB forward.")(f)
    f = click.option("--user", default="mobile", help="SSH user (mobile -> escalates via sudo; or root).")(f)
    f = click.option("--password", default="alpine", help="SSH/sudo password.")(f)
    f = click.option("--udid", default=None, help="Target device UDID.")(f)
    return f


@cli.command()
@_opts
def diag(port, local_port, user, password, udid):
    """Read-only inspection of the revocation DBs and ban-lists."""
    with Device(local_port, port, password, udid, user) as d:
        d.run(DIAG)


@cli.command()
@_opts
@click.option("--yes", is_flag=True, help="Skip confirmation.")
def clean(port, local_port, user, password, udid, yes):
    """Apply the full on-device method live, then re-inspect."""
    if not yes and input('Type "CLEAN" to wipe+lock the revocation DBs on the device: ').strip() != "CLEAN":
        click.secho("Aborted.", fg="yellow")
        return
    with Device(local_port, port, password, udid, user) as d:
        click.secho("--- applying ---", fg="yellow")
        d.run(CLEAN)
        click.secho("\n--- re-inspect ---", fg="yellow")
        d.run(DIAG)
    click.secho("\nReboot the device for all daemons to pick up the change.", fg="green")


@cli.command(name="exec")
@_opts
@click.argument("command")
def exec_(port, local_port, user, password, udid, command):
    """Run an arbitrary shell command on the device."""
    with Device(local_port, port, password, udid, user) as d:
        d.run(command)


if __name__ == "__main__":
    cli()
