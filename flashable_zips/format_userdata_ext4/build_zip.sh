#!/usr/bin/env bash
# Script to build Format-Data-Ext4-Tanzanite.zip

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$ROOT_DIR/out"
ZIP_NAME="Format-Data-Ext4-Tanzanite.zip"
TARGET_ZIP="$OUT_DIR/$ZIP_NAME"

mkdir -p "$OUT_DIR"
rm -f "$TARGET_ZIP"

echo "==> Building $ZIP_NAME..."

# Ensure executable permissions
chmod 755 "$SCRIPT_DIR/META-INF/com/google/android/update-binary"
chmod 755 "$SCRIPT_DIR/tools/busybox"

cd "$SCRIPT_DIR"
zip -r9 "$TARGET_ZIP" META-INF tools

echo "==> Build successful: $TARGET_ZIP"
ls -lh "$TARGET_ZIP"
