#!/usr/bin/env bash
# Build the Omega .deb from package/. Requires dpkg-deb (Linux / CI).
set -euo pipefail
cd "$(dirname "$0")"

OUT=build
rm -rf "$OUT"
mkdir -p "$OUT"

# Normalise line endings + exec bits on the scripts that go in the package.
for f in package/DEBIAN/postinst package/DEBIAN/prerm \
         package/var/jb/usr/local/bin/omega-ondevice; do
  sed -i 's/\r$//' "$f"
  chmod 755 "$f"
done
chmod 755 package/DEBIAN

VER=$(awk -F': ' '/^Version:/{print $2}' package/DEBIAN/control)
dpkg-deb -Zgzip --build package "$OUT/party.jailbreak.omega-ondevice_${VER}_iphoneos-arm64.deb"

echo "Built:"
ls -la "$OUT"
