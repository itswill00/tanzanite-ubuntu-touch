#!/usr/bin/env bash
# Tanzanite HyperOS SDCard Fix - KernelSU / Magisk Module Builder
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$ROOT_DIR/out"
ZIP_NAME="Tanzanite-HyperOS-SDCard-Fix-KSU.zip"
TARGET_ZIP="$OUT_DIR/$ZIP_NAME"

mkdir -p "$OUT_DIR"
rm -f "$TARGET_ZIP"

echo "==> Building $ZIP_NAME..."

# Ensure proper permissions
chmod 755 "$SCRIPT_DIR/post-fs-data.sh"
chmod 755 "$SCRIPT_DIR/service.sh"
chmod 644 "$SCRIPT_DIR/system.prop"
chmod 644 "$SCRIPT_DIR/module.prop"
chmod 644 "$SCRIPT_DIR/customize.sh"
chmod 755 "$SCRIPT_DIR/META-INF/com/google/android/update-binary"

cd "$SCRIPT_DIR"
zip -r9 "$TARGET_ZIP" META-INF module.prop post-fs-data.sh service.sh system.prop customize.sh

echo "==> Build successful: $TARGET_ZIP"
ls -lh "$TARGET_ZIP"
