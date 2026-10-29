#!/usr/bin/env bash
# Uploads the built installer zip to gofile and updates every place the
# checksum and download link are recorded, so they cannot go stale.
#
# Usage: ./scripts/publish_artifact.sh [zip-path]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -n "${1:-}" ]; then
    ZIP="$1"
else
    # Default to the newest build in dist/, whatever its version string is.
    ZIP="$(ls -1t "$ROOT"/dist/*.zip 2>/dev/null | head -1 || true)"
fi

[ -s "$ZIP" ] || { echo "no such zip: $ZIP" >&2; exit 1; }

SIZE=$(stat -c%s "$ZIP")
NAME="$(basename "$ZIP")"
SHA=$(sha256sum "$ZIP" | cut -d' ' -f1)
MD5=$(md5sum "$ZIP" | cut -d' ' -f1)
MIB=$(awk -v b="$SIZE" 'BEGIN{printf "%.0f", b/1048576}')

echo "==> $ZIP"
echo "    size: $SIZE bytes (${MIB} MiB)"
echo "    sha256: $SHA"
echo "    md5:    $MD5"

echo "==> Requesting a gofile server"
SRV=$(curl -s https://api.gofile.io/servers \
      | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['servers'][0]['name'])")
echo "    server: $SRV"

echo "==> Uploading (this takes a few minutes for ~1 GB)"
RESP=$(curl -s -F "file=@${ZIP}" "https://${SRV}.gofile.io/contents/uploadfile")
URL=$(echo "$RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)['data']
    print(d['downloadPage'])
except Exception:
    print('')
")

if [ -z "$URL" ]; then
    echo "upload failed; response was:" >&2
    echo "$RESP" >&2
    exit 1
fi

echo "==> Uploaded: $URL"

echo "==> Updating artifacts/README.md"
cat > "$ROOT/artifacts/README.md" <<EOF
# Artifacts

Binaries are **not** stored in git. This directory holds only checksums and pointers.

## Installer zip

| Field | Value |
| --- | --- |
| File | \`${NAME}\` |
| Size | ${SIZE} bytes (${MIB} MiB) |
| SHA-256 | \`${SHA}\` |
| MD5 | \`${MD5}\` |
| Download | ${URL} |

Rebuild it with \`./scripts/build_zip_local.sh\` (see \`docs/BUILD_NOTES.md\`).

## Zip contents

| Path | Size |
| --- | --- |
| \`ubuntu-touch-hybris-rootfs-arm64.tar.gz\` | UT Focal arm64 rootfs |
| \`halium_halium_arm64.tar.xz\` | Halium 12 GSI (contains android-rootfs.img) |
| \`partitions/boot.img\` | Halium boot image, header v4 |
| \`partitions/vendor_boot.img\` | Halium vendor_boot, header v4, carries ramdisk + dtb |
| \`partitions/dtbo.img\` | Device tree overlay |
| \`device_tanzanite.tar.xz\` | Device tarball |
| \`device_tanzanite_system.tar.gz\` | Rootfs overlay (udev, ofono, audio, libhybris) |
| \`vbmeta/*.img\` | Pre-disabled AVB metadata |
| \`tools/*\` | busybox, avbctl, erofs tools, lptools |
| \`META-INF/com/google/android/update-binary\` | Installer logic |

## Images produced alongside (not uploaded)

\`rootfs.img\` (3.7 GB) and \`system.img\` (2.7 GB) exceed per-asset hosting limits and are only
needed for the \`fastboot flash system\` path, which this port does not use. Rebuild with
\`prepare-fake-ota.sh\` + \`system-image-from-ota.sh\`.
EOF
rm -f "$ROOT"/artifacts/*.sha256
echo "$SHA  $NAME" > "$ROOT/artifacts/${NAME}.sha256"

echo "==> Updating README.md download link"
python3 - "$ROOT/README.md" "$URL" "$MIB" "$SHA" "$NAME" <<'PY'
import re, sys
path, url, mib, sha, name = sys.argv[1:6]
s = open(path).read()
s = re.sub(r'- \*\*Download:\*\* <[^>]+>', f'- **Download:** <{url}>', s)
s = re.sub(r'- \*\*File:\*\* `[^`]+` \([^)]*\)',
           f'- **File:** `{name}` ({mib} MiB)', s)
s = re.sub(r'- \*\*SHA-256:\*\* `[0-9a-f]{64}`', f'- **SHA-256:** `{sha}`', s)
open(path, 'w').write(s)
PY

echo "==> Done"
grep -A4 'Download:' "$ROOT/README.md" | head -6
