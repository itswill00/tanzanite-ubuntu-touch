#!/usr/bin/env bash
# Builds the flashable recovery installer zip for tanzanite from locally built artifacts.
#
# Output naming:
#   tanzanite-ut20.04-halium12-v<version>-<yyyymmdd>-<gitshort>.zip
#     ut20.04      Ubuntu Touch rootfs release
#     halium12     Halium version the vendor blobs are matched to
#     v<version>   port version, from PORT_VERSION below
#     yyyymmdd     build date (UTC)
#     gitshort     short commit of this repository, or "nogit" outside a checkout
#
# A companion .sha256 and .buildinfo are written next to the zip.
#
# Expects (relative to the repo root unless overridden by env):
#   out/partitions/{boot.img,vendor_boot.img,dtbo.img}   from `./build.sh -b workdir`
#   out/device_tanzanite.tar.xz
#   ota/ubuntu-touch-android9plus-rootfs-arm64.tar.gz    UT Focal rootfs
#   ota/halium_halium_arm64.tar.xz                       Halium 12 GSI
#
# Usage: ./scripts/build_zip_local.sh
#   PORT_VERSION=1.1.0 ./scripts/build_zip_local.sh    # override the version
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT/flashable_zips"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
PART_DIR="${PART_DIR:-$OUT_DIR/partitions}"
ROOTFS="${ROOTFS:-$ROOT/ota/ubuntu-touch-android9plus-rootfs-arm64.tar.gz}"
GSI="${GSI:-$ROOT/ota/halium_halium_arm64.tar.xz}"

# --- version metadata --------------------------------------------------------
PORT_VERSION="${PORT_VERSION:-1.1.0}"
UT_RELEASE="ut20.04"
HALIUM_VERSION="halium12"
BUILD_DATE="$(date -u +%Y%m%d)"
BUILD_STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if GIT_SHORT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null)"; then
    GIT_DIRTY=""
    git -C "$ROOT" diff --quiet 2>/dev/null || GIT_DIRTY="-dirty"
else
    GIT_SHORT="nogit"; GIT_DIRTY=""
fi
DEVICE_CODENAME="tanzanite"

ZIP_NAME="${DEVICE_CODENAME}-${UT_RELEASE}-${HALIUM_VERSION}-v${PORT_VERSION}-${BUILD_DATE}-${GIT_SHORT}${GIT_DIRTY}.zip"
TARGET="${TARGET:-$ROOT/dist/$ZIP_NAME}"

for f in "$PART_DIR/boot.img" "$PART_DIR/vendor_boot.img" "$PART_DIR/dtbo.img" \
         "$OUT_DIR/device_tanzanite.tar.xz" "$ROOTFS" "$GSI"; do
    [ -s "$f" ] || { echo "[-] Missing required input: $f" >&2; exit 1; }
done

STAGE="$(mktemp -d -t tanzanite_zip_XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Building $ZIP_NAME"
echo "    port version : $PORT_VERSION"
echo "    UT release   : $UT_RELEASE"
echo "    Halium       : $HALIUM_VERSION"
echo "    commit       : $GIT_SHORT$GIT_DIRTY"
echo "    date         : $BUILD_STAMP"

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

# Manifest inside the zip so a flashed device can identify its own build.
echo "[*] Writing build manifest"
mkdir -p "$STAGE/META-INF/tanzanite"
cat > "$STAGE/META-INF/tanzanite/build.prop" <<MANIFEST
# Build identification for this installer package.
# Read at runtime by the installer and written to /data/ubuntu/etc/tanzanite-build.prop
tanzanite.build.version=${PORT_VERSION}
tanzanite.build.device=${DEVICE_CODENAME}
tanzanite.build.ut_release=${UT_RELEASE}
tanzanite.build.halium=${HALIUM_VERSION}
tanzanite.build.date=${BUILD_STAMP}
tanzanite.build.commit=${GIT_SHORT}${GIT_DIRTY}
tanzanite.build.kernel=5.10.269-EvernightKernel-1.1
tanzanite.build.modules=385
tanzanite.build.installer=${ZIP_NAME}
MANIFEST

echo "[*] Creating zip"
mkdir -p "$(dirname "$TARGET")"
rm -f "$TARGET"
(cd "$STAGE" && zip -r9 -q "$TARGET" \
    META-INF tools vbmeta partitions \
    ubuntu-touch-hybris-rootfs-arm64.tar.gz halium_halium_arm64.tar.xz \
    device_tanzanite.tar.xz device_tanzanite_system.tar.gz)

# Companion files, named after the zip so a directory of builds stays readable.
SHA="$(sha256sum "$TARGET" | cut -d' ' -f1)"
SIZE="$(stat -c%s "$TARGET")"
printf '%s  %s\n' "$SHA" "$(basename "$TARGET")" > "${TARGET}.sha256"
cat > "${TARGET%.zip}.buildinfo" <<INFO
file          $(basename "$TARGET")
size          $SIZE bytes
sha256        $SHA
port_version  $PORT_VERSION
ut_release    $UT_RELEASE
halium        $HALIUM_VERSION
device        $DEVICE_CODENAME
commit        $GIT_SHORT$GIT_DIRTY
built         $BUILD_STAMP
kernel        5.10.269-EvernightKernel-1.1
modules       385
INFO

echo "[+] Done: $TARGET"
ls -lh "$TARGET" "${TARGET}.sha256" "${TARGET%.zip}.buildinfo"
echo "[+] sha256: $SHA"
