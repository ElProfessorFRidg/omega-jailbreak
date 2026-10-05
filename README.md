# Omega Toolkit

Keep sideloaded / enterprise-signed apps working on a **jailbroken (rootless)**
iDevice by neutralising the local certificate-revocation state, with a small
**on-device web control panel** (buttons for Apply / Status / Log / Debug).

> Your own device, your own apps. Experimental, use at your own risk. This does
> **not** remove the revocation on Apple's side — it only stops your device from
> acting on it (locally + at the network).

## How revocation blocking actually works (verified)

Two independent layers — you need **both**:

1. **Local memory** — the device caches "this cert is REVOKED" in
   `trustd/private/ocspcache.sqlite3` and the four
   `MobileIdentityData/*.plist` ban-lists. The tweak wipes the cache and
   rewrites the ban-lists as empty, **immutable (`schg`)** plists. Effect: apps
   run **offline**. (It does *not* delete `mis.db` — on rootless the profiles
   live inside it with no `.mobileprovision` backups, so that would wipe them.)
2. **Live online re-check** — once online, `amfid` re-queries
   `ocsp.apple.com` / `ppq.apple.com` live and re-blocks. **No on-device file
   can stop this** (`/etc/hosts` is read-only on rootless), so you must block
   these at the **network / DNS** level:
   `ocsp.apple.com ppq.apple.com crl.apple.com valid.apple.com`
   See [`docs/SELF-HOSTED-DNS.md`](docs/SELF-HOSTED-DNS.md) (self-hosted, like
   NextDNS) and [`pc-tools/Omega-DoH.mobileconfig`](pc-tools/Omega-DoH.mobileconfig).

## Repo layout

```
package/      the tweak .deb source (DEBIAN/ + var/jb/…):
              omega-ondevice  config-driven worker (modules: OCSP cache, ban-lists,
                              valid.sqlite3, service restart) — re-applies at boot
              omega-dns       on-device local DNS block (dnsmasq @ 127.0.0.1) + profile
              omega-runner    root trigger runner the app talks to
              LaunchDaemons   boot + hourly worker, and the WatchPaths trigger
app/          native Theos app: tabbed UI (Dashboard / Modules / DNS / Settings / Log)
repo-assets/  Sileo repo landing page (served by GitHub Pages)
pc-tools/     PC-side helpers (USB, no server needed):
              omega_ssh.py          drive the device over SSH-through-USB (diag/clean/exec)
              omega_pro.py          inspect profiles + OCSP revocation status (restore is inspection-grade)
              offline_hotspot.ps1   Windows "dead" Wi-Fi hotspot (no internet) for offline restores
              Omega-DoH.mobileconfig iOS DoH profile template (point it at your VPS DNS)
docs/         SELF-HOSTED-DNS.md    set up your own filtering DNS on a VPS
build.sh      build the tweak .deb (needs dpkg-deb; CI does it for you)
.github/      CI: builds the .deb(s) and publishes a Sileo repo via GitHub Pages
```

### Native app (tabs)

- **Dashboard** — one-tap Apply, colour-coded protection status, enabled-module summary.
- **Modules** — toggle each technique independently (OCSP cache purge+lock, empty
  ban-lists+lock, `valid.sqlite3` blanking, service restart). Stored in
  `/var/mobile/.omega/config`, read by the root worker on every run and at boot.
- **DNS** — install a **local** resolver (`dnsmasq` on `127.0.0.1:53`) that blocks the
  four Apple revocation domains and forwards the rest to your chosen upstream, then
  install the generated profile so iOS routes through it. No VPS required. (Needs the
  `dnsmasq` package.)
- **Settings** — apply-on-launch, diagnostics. **Log** — the live worker log.

## Install (on device)

Add the GitHub Pages URL of this repo in **Sileo** → Sources, install
**Omega On-Device**, then open the control panel in Safari:

```
http://127.0.0.1:8472
```

The worker also runs at every boot (semi-tethered: after each re-jailbreak the
LaunchDaemon re-applies it).

## Build locally

```sh
./build.sh      # produces build/*.deb  (Linux/macOS with dpkg-deb)
```

## Credits

On-device method after JJTech's backup trick and the jailbreak.party Omega tool;
the ban-list/OCSP neutralisation follows the known community snippet, corrected
(no `mis.db` deletion) and verified over SSH root.
