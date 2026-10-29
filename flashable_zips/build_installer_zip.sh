#!/usr/bin/env bash
# Tanzanite Halium 12 - Flashable Installer ZIP Builder
# Packages the recovery installer zip for Redmi Note 14 4G (tanzanite)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$ROOT_DIR/out"
TARGET_ZIP="$ROOT_DIR/tanzanite-halium.zip"
TMP_STAGE="$(mktemp -d -t tanzanite_zip_stage_XXXXXX)"

trap 'rm -rf "$TMP_STAGE"' EXIT

echo "==> Building Tanzanite Halium Flashable Installer Zip..."

# 1. Verify and compile overlay components if needed
if [ ! -f "$ROOT_DIR/overlay/system/usr/local/lib/libupower_filter_bms.so" ]; then
    echo "[-] libupower_filter_bms.so missing, building..."
    gcc -shared -fPIC -O2 "$ROOT_DIR/overlay/system/usr/local/bin/upower_filter_bms.c" -o "$ROOT_DIR/overlay/system/usr/local/lib/libupower_filter_bms.so" -ldl
fi
chmod 755 "$ROOT_DIR/overlay/system/usr/local/bin/tanzanite-flashlight-bridge" \
          "$ROOT_DIR/overlay/system/usr/local/lib/libupower_filter_bms.so"

# 2. Build device_tanzanite_system.tar.gz
echo "[*] Building device_tanzanite_system.tar.gz from overlay/system..."
mkdir -p "$OUT_DIR"
(cd "$ROOT_DIR/overlay/system" && tar --numeric-owner --owner=0 --group=0 -czf "$OUT_DIR/device_tanzanite_system.tar.gz" .)

# 3. Build device_tanzanite.tar.xz if missing or outdated
if [ ! -f "$OUT_DIR/device_tanzanite.tar.xz" ]; then
    echo "[*] Building device_tanzanite.tar.xz..."
    rm -rf "$ROOT_DIR/workdir/tmp/system"
    "$ROOT_DIR/build/build-tarball-mainline.sh" tanzanite "$OUT_DIR" "$ROOT_DIR/workdir/tmp" usrmerge
fi

# 4. Prepare staging directory
echo "[*] Staging installer contents..."
mkdir -p "$TMP_STAGE/META-INF/com/google/android"
mkdir -p "$TMP_STAGE/tools"
mkdir -p "$TMP_STAGE/vbmeta"
mkdir -p "$TMP_STAGE/partitions"

# Meta files
echo "# dummy" > "$TMP_STAGE/META-INF/com/google/android/updater-script"
cp -f "$SCRIPT_DIR/update-binary.template.sh" "$TMP_STAGE/META-INF/com/google/android/update-binary"
sed -i 's/__VBMETA_MODE__/prebuilt/g' "$TMP_STAGE/META-INF/com/google/android/update-binary"
chmod 755 "$TMP_STAGE/META-INF/com/google/android/update-binary"

# Tools
cp -f "$SCRIPT_DIR/common/tools/"* "$TMP_STAGE/tools/"
chmod 755 "$TMP_STAGE/tools/"*

# Vbmeta
cp -f "$SCRIPT_DIR/v1/vbmeta/"* "$TMP_STAGE/vbmeta/"

# Partitions
cp -f "$OUT_DIR/partitions/boot.img" "$TMP_STAGE/partitions/"
cp -f "$OUT_DIR/partitions/vendor_boot.img" "$TMP_STAGE/partitions/"
cp -f "$OUT_DIR/partitions/dtbo.img" "$TMP_STAGE/partitions/"

# Rootfs & overlays
ROOTFS_FILE="/mnt/dreamybull/ubuntu-touch-hybris-rootfs-arm64.tar.gz"
if [ ! -f "$ROOTFS_FILE" ]; then
    ROOTFS_FILE="$(find /mnt "$ROOT_DIR" -maxdepth 2 -name "ubuntu-touch-hybris-rootfs-arm64.tar.gz" 2>/dev/null | head -n 1 || true)"
fi
[ -f "$ROOTFS_FILE" ] || { echo "[-] Error: rootfs tarball not found!"; exit 1; }

cp -f "$ROOTFS_FILE" "$TMP_STAGE/ubuntu-touch-hybris-rootfs-arm64.tar.gz"
cp -f "$ROOT_DIR/ota/halium_halium_arm64.tar.xz" "$TMP_STAGE/halium_halium_arm64.tar.xz"
cp -f "$OUT_DIR/device_tanzanite.tar.xz" "$TMP_STAGE/device_tanzanite.tar.xz"
cp -f "$OUT_DIR/device_tanzanite_system.tar.gz" "$TMP_STAGE/device_tanzanite_system.tar.gz"

# 5. Create zip
echo "[*] Creating $TARGET_ZIP..."
cd "$TMP_STAGE"
zip -r9 "$TARGET_ZIP" META-INF tools vbmeta partitions ubuntu-touch-hybris-rootfs-arm64.tar.gz halium_halium_arm64.tar.xz device_tanzanite.tar.xz device_tanzanite_system.tar.gz

echo "[+] Installer package ready: $TARGET_ZIP"
ls -lh "$TARGET_ZIP"
