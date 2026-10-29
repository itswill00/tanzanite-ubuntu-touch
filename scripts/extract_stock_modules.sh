#!/usr/bin/env bash
# Extracts kernel modules from a stock vendor_boot.img and compares them with the
# module set shipped in this repository.
#
# Use this to find out exactly which .ko files are missing from
# vendor-ramdisk-overlay/lib/modules/. Those files come from the device firmware
# and cannot be rebuilt here, so they must be pulled from stock.
#
# Usage:
#   ./scripts/extract_stock_modules.sh vendor_boot.img [outdir]
#
# Requires: python3, cpio, gzip/lz4, and unpack_bootimg.py (auto-fetched).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_BOOT="${1:-}"
OUTDIR="${2:-$ROOT/.stock-modules}"
SHIPPED="$ROOT/vendor-ramdisk-overlay/lib/modules"

[ -n "$VENDOR_BOOT" ] || { echo "usage: $0 <vendor_boot.img> [outdir]" >&2; exit 1; }
[ -f "$VENDOR_BOOT" ] || { echo "no such file: $VENDOR_BOOT" >&2; exit 1; }

command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }
command -v cpio    >/dev/null || { echo "cpio required"    >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUTDIR"

echo "==> Fetching unpack_bootimg.py"
UNPACK="$WORK/unpack_bootimg.py"
if [ ! -f "$UNPACK" ]; then
    curl -sL "https://raw.githubusercontent.com/LineageOS/android_system_tools_mkbootimg/lineage-20.0/unpack_bootimg.py" -o "$UNPACK"
fi

echo "==> Unpacking $VENDOR_BOOT"
python3 "$UNPACK" --boot_img "$VENDOR_BOOT" --out "$WORK/vb" > "$WORK/unpack.log" 2>&1 || {
    echo "failed to unpack; output was:"; cat "$WORK/unpack.log"; exit 1
}
grep -E "vendor boot image header version|vendor ramdisk total size|dtb size" "$WORK/unpack.log" || true

# A vendor_boot.img can contain several ramdisk fragments. Extract every one of
# them and collect the .ko files found in each.
echo "==> Extracting ramdisk fragments"
shopt -s nullglob
FRAGS=("$WORK"/vb/vendor_ramdisk*)
[ ${#FRAGS[@]} -gt 0 ] || { echo "no vendor_ramdisk* produced by unpack_bootimg" >&2; exit 1; }

mkdir -p "$OUTDIR/modules"
for frag in "${FRAGS[@]}"; do
    [ -s "$frag" ] || continue
    name="$(basename "$frag")"
    echo "  - $name ($(stat -c%s "$frag") bytes)"
    dest="$WORK/ex_$name"
    mkdir -p "$dest"
    case "$(file -b "$frag")" in
        *gzip*)      gzip -dc "$frag"      | (cd "$dest" && cpio -idm --quiet) ;;
        *LZ4*)       lz4  -dc "$frag"      | (cd "$dest" && cpio -idm --quiet) ;;
        *XZ*)        xz   -dc "$frag"      | (cd "$dest" && cpio -idm --quiet) ;;
        *cpio*)      (cd "$dest" && cpio -idm --quiet < "$frag") ;;
        *)           echo "    (unknown compression, skipped)" ; continue ;;
    esac
    if [ -d "$dest/lib/modules" ]; then
        while IFS= read -r ko; do
            cp -f "$ko" "$OUTDIR/modules/" 2>/dev/null || true
        done < <(find "$dest/lib/modules" -name '*.ko')
    fi
done

COUNT=$(find "$OUTDIR/modules" -name '*.ko' | wc -l)
echo "==> Extracted $COUNT module(s) into $OUTDIR/modules"
[ "$COUNT" -gt 0 ] || { echo "no .ko files found in vendor_boot ramdisks" >&2; exit 1; }

echo
echo "==> Modules present in stock but MISSING from this repo"
stock_list="$(cd "$OUTDIR/modules" && find . -maxdepth 1 -name '*.ko' -printf '%f\n' | sed 's/\.ko$//' | sort -u)"
repo_list="$(cd "$SHIPPED" && find . -maxdepth 1 -name '*.ko' -printf '%f\n' | sed 's/\.ko$//' | sort -u)"
comm -23 <(echo "$stock_list") <(echo "$repo_list") > "$OUTDIR/missing.txt" || true
if [ -s "$OUTDIR/missing.txt" ]; then
    printf '\033[31m%s module(s) missing:\033[0m\n' "$(wc -l < "$OUTDIR/missing.txt")"
    sed 's/^/  - /' "$OUTDIR/missing.txt"
else
    printf '\033[32mnone - repo already ships every stock module\033[0m\n'
fi

echo
echo "==> Hardware-critical modules still missing from the repo"
for m in flashlight flashlights-mt6789-o7 mtk-pwm \
         snd-soc-mt6789-afe snd-soc-mt6366 mt6789-mt6366 audio_ipi adsp \
         snd-soc-audiodsp-common mtk-scp-audio snd-soc-rt5512 snd-soc-sipa snd-soc-aw87xx \
         camera_isp camera_mem imgsensor_isp6s camera_eeprom camera_dip_isp6s \
         camera_rsc_isp60 camera_fdvt_isp51 mainaf main2af main3af subaf sub2af \
         mtk-composite sensorhub regulator-vibrator; do
    if ! echo "$repo_list" | grep -qx "$m"; then
        if echo "$stock_list" | grep -qx "$m"; then
            printf '  \033[33m%s\033[0m  (in stock, copy it in)\n' "$m"
        else
            printf '  \033[31m%s\033[0m  (not in stock either - different vendor layout?)\n' "$m"
        fi
    fi
done

echo
echo "Next steps:"
echo "  1. cp $OUTDIR/modules/*.ko $SHIPPED/"
echo "  2. ./scripts/sync_modules_load.sh    # rebuild modules.load from what is shipped"
echo "  3. ./scripts/check_modules.sh        # verify"
