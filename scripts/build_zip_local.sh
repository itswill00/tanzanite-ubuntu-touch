#!/usr/bin/env bash
# Builds the flashable recovery installer zip for tanzanite from locally built artifacts.
#
# Expects (relative to the repo root unless overridden by env):
#   out/partitions/{boot.img,vendor_boot.img,dtbo.img}   from `./build.sh -b workdir`
#   out/device_tanzanite.tar.xz
#   ota/ubuntu-touch-android9plus-rootfs-arm64.tar.gz    UT Focal rootfs
#   ota/halium_halium_arm64.tar.xz                       Halium 12 GSI
#
# Usage: ./scripts/build_zip_local.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT/flashable_zips"
OUT_DIR="$ROOT/out"
PART_DIR="${PART_DIR:-$OUT_DIR/partitions}"
ROOTFS="${ROOTFS:-$ROOT/ota/ubuntu-touch-android9plus-rootfs-arm64.tar.gz}"
GSI="${GSI:-$ROOT/ota/halium_halium_arm64.tar.xz}"
TARGET="${TARGET:-$ROOT/tanzanite-halium.zip}"

for f in "$PART_DIR/boot.img" "$PART_DIR/vendor_boot.img" "$PART_DIR/dtbo.img" \
         "$OUT_DIR/device_tanzanite.tar.xz" "$ROOTFS" "$GSI"; do
    [ -s "$f" ] || { echo "[-] Missing required input: $f" >&2; exit 1; }
done

STAGE="$(mktemp -d -t tanzanite_zip_XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging installer contents"
mkdir -p "$STAGE/META-INF/com/google/android" "$STAGE/tools" "$STAGE/vbmeta" "$STAGE/partitions"

# update-binary with the vbmeta mode substituted in
echo "# dummy" > "$STAGE/META-INF/com/google/android/updater-script"
sed 's/__VBMETA_MODE__/prebuilt/g' "$SCRIPT_DIR/update-binary.template.sh" \
    > "$STAGE/META-INF/com/google/android/update-binary"
chmod 755 "$STAGE/META-INF/com/google/android/update-binary"

cp -f "$SCRIPT_DIR/common/tools/"* "$STAGE/tools/"
chmod 755 "$STAGE/tools/"*
cp -f "$SCRIPT_DIR/format_userdata_ext4/tools/"* "$STAGE/tools/" 2>/dev/null || true

# Pre-disabled vbmeta images (AVB flags already cleared)
if [ -d "$SCRIPT_DIR/vbmeta" ]; then
    cp -f "$SCRIPT_DIR/vbmeta/"* "$STAGE/vbmeta/"
else
    echo "[-] Missing flashable_zips/vbmeta/ (vbmeta*.img required for prebuilt mode)" >&2
    exit 1
fi

# Halium boot images built from our kernel
cp -f "$PART_DIR/boot.img"        "$STAGE/partitions/"
cp -f "$PART_DIR/vendor_boot.img" "$STAGE/partitions/"
cp -f "$PART_DIR/dtbo.img"        "$STAGE/partitions/"

# Device overlay applied on top of the extracted rootfs
echo "[*] Building device_tanzanite_system.tar.gz"
(cd "$ROOT/overlay/system" && tar --numeric-owner --owner=0 --group=0 -czf "$STAGE/device_tanzanite_system.tar.gz" .)

# Rootfs (Focal, ships libhybris) + Halium 12 GSI (contains android-rootfs.img)
cp -f "$ROOTFS" "$STAGE/ubuntu-touch-hybris-rootfs-arm64.tar.gz"
cp -f "$GSI"    "$STAGE/halium_halium_arm64.tar.xz"
cp -f "$OUT_DIR/device_tanzanite.tar.xz" "$STAGE/device_tanzanite.tar.xz"

echo "[*] Creating zip"
rm -f "$TARGET"
(cd "$STAGE" && zip -r9 -q "$TARGET" \
    META-INF tools vbmeta partitions \
    ubuntu-touch-hybris-rootfs-arm64.tar.gz halium_halium_arm64.tar.xz \
    device_tanzanite.tar.xz device_tanzanite_system.tar.gz)

echo "[+] Done: $TARGET"
ls -lh "$TARGET"
sha256sum "$TARGET"
