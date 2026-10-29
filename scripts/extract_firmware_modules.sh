#!/usr/bin/env bash
# Pulls kernel modules and vendor audio config out of an official Xiaomi
# fastboot firmware package (*.tgz), so the missing drivers can be restored
# without a device in hand.
#
# The fastboot package is a tar.gz containing per-partition images, including
# vendor_boot.img. That image carries the vendor ramdisk with every MediaTek
# .ko built for this device, which is exactly the set this port is missing.
#
# Usage:
#   ./scripts/extract_firmware_modules.sh <firmware.tgz> [workdir]
#
# Output (in workdir, default ./.firmware-extract):
#   images/           extracted partition images
#   modules/*.ko      every module found in vendor_boot
#   vendor/           audio config + DSP payloads from the vendor image
#   missing.txt       modules in firmware but absent from this repo
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW="${1:-}"
WORK="${2:-$ROOT/.firmware-extract}"
SHIPPED="$ROOT/vendor-ramdisk-overlay/lib/modules"

[ -n "$FW" ] || { echo "usage: $0 <firmware.tgz> [workdir]" >&2; exit 1; }
[ -f "$FW" ] || { echo "no such file: $FW" >&2; exit 1; }

for c in tar python3 cpio curl; do
    command -v "$c" >/dev/null || { echo "$c required" >&2; exit 1; }
done

# These packages are 7+ GB gzip archives and the images sit behind a large
# super.img, so a single-threaded gunzip dominates the runtime. pigz uses all
# cores when available.
if command -v pigz >/dev/null; then
    DECOMP=(tar -I pigz)
else
    DECOMP=(tar -z)
    echo "note: pigz not found, falling back to single-threaded gzip" >&2
fi

mkdir -p "$WORK/images" "$WORK/modules" "$WORK/vendor"

echo "==> Listing partitions in $FW"
# Xiaomi fastboot packages put the images either at the top level or in an
# images/ subdirectory depending on the release.
LIST="$("${DECOMP[@]}" tf "$FW" 2>/dev/null | grep -E '(^|/)(boot|vendor_boot|dtbo|vendor|super|system)\.img$' || true)"
if [ -z "$LIST" ]; then
    echo "no partition images found; top-level contents:" >&2
    "${DECOMP[@]}" tf "$FW" | head -20 >&2
    exit 1
fi
echo "$LIST" | sed 's/^/    /'

echo "==> Extracting images"
for img in vendor_boot.img dtbo.img; do
    path="$(echo "$LIST" | grep -E "(^|/)$img$" | head -1)"
    [ -n "$path" ] || { echo "    $img not present in package"; continue; }
    "${DECOMP[@]}" xf "$FW" -C "$WORK/images" "$path"
    # flatten
    if [ "$(dirname "$path")" != "." ]; then
        mv "$WORK/images/$path" "$WORK/images/$img"
        rmdir -p "$WORK/images/$(dirname "$path")" 2>/dev/null || true
    fi
    echo "    $img -> $WORK/images/$img ($(stat -c%s "$WORK/images/$img") bytes)"
done

# vendor.img is needed for the audio DSP libraries and amp parameters.
VPATH="$(echo "$LIST" | grep -E '(^|/)vendor\.img$' | head -1 || true)"
if [ -n "$VPATH" ]; then
    echo "==> Extracting vendor.img (audio DSP libraries)"
    "${DECOMP[@]}" xf "$FW" -C "$WORK/images" "$VPATH"
    if [ "$(dirname "$VPATH")" != "." ]; then
        mv "$WORK/images/$VPATH" "$WORK/images/vendor.img"
        rmdir -p "$WORK/images/$(dirname "$VPATH")" 2>/dev/null || true
    fi
fi

echo "==> Unpacking vendor_boot ramdisk"
UNPACK="$WORK/unpack_bootimg.py"
[ -f "$UNPACK" ] || curl -sL \
    "https://raw.githubusercontent.com/LineageOS/android_system_tools_mkbootimg/lineage-20.0/unpack_bootimg.py" \
    -o "$UNPACK"
python3 "$UNPACK" --boot_img "$WORK/images/vendor_boot.img" --out "$WORK/vb" > "$WORK/unpack.log" 2>&1 \
    || { echo "unpack failed:"; cat "$WORK/unpack.log"; exit 1; }
grep -E "header version|ramdisk total size|command line" "$WORK/unpack.log" | sed 's/^/    /'

rm -rf "$WORK/ramdisk"; mkdir -p "$WORK/ramdisk"
for frag in "$WORK"/vb/vendor_ramdisk*; do
    [ -s "$frag" ] || continue
    case "$(file -b "$frag")" in
        *LZ4*)  lz4 -dc "$frag" | (cd "$WORK/ramdisk" && cpio -idm --quiet) ;;
        *gzip*) gzip -dc "$frag" | (cd "$WORK/ramdisk" && cpio -idm --quiet) ;;
        *XZ*)   xz -dc "$frag" | (cd "$WORK/ramdisk" && cpio -idm --quiet) ;;
        *cpio*) (cd "$WORK/ramdisk" && cpio -idm --quiet < "$frag") ;;
    esac
done

if [ -d "$WORK/ramdisk/lib/modules" ]; then
    while IFS= read -r ko; do cp -f "$ko" "$WORK/modules/"; done \
        < <(find "$WORK/ramdisk/lib/modules" -name '*.ko')
fi
COUNT=$(find "$WORK/modules" -name '*.ko' | wc -l)
echo "==> Collected $COUNT module(s) from firmware"
[ "$COUNT" -gt 0 ] || { echo "no modules found - unexpected vendor_boot layout" >&2; exit 1; }

echo "==> Comparing with modules shipped in this repo"
fw_list="$(cd "$WORK/modules" && find . -maxdepth 1 -name '*.ko' -printf '%f\n' | sed 's/\.ko$//' | sort -u)"
repo_list="$(cd "$SHIPPED" && find . -maxdepth 1 -name '*.ko' -printf '%f\n' | sed 's/\.ko$//' | sort -u)"
comm -23 <(echo "$fw_list") <(echo "$repo_list") > "$WORK/missing.txt" || true
printf '    %s module(s) in firmware but missing from repo\n' "$(wc -l < "$WORK/missing.txt")"

echo "==> Checking the modules behind the reported bugs"
for m in flashlight flashlights-mt6789-o7 mtk-pwm \
         snd-soc-mt6789-afe snd-soc-mt6366 mt6789-mt6366 audio_ipi adsp \
         snd-soc-audiodsp-common mtk-scp-audio \
         camera_isp camera_mem imgsensor_isp6s camera_eeprom mtk-composite \
         mainaf subaf sensorhub; do
    if [ -f "$WORK/modules/$m.ko" ]; then
        printf '    \033[32mFOUND\033[0m  %s.ko\n' "$m"
    else
        printf '    \033[31mabsent\033[0m %s.ko\n' "$m"
    fi
done

echo
echo "Next:"
echo "  cp $WORK/modules/*.ko $SHIPPED/"
echo "  ./scripts/sync_modules_load.sh && ./scripts/check_modules.sh"
