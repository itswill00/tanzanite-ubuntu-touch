#!/usr/bin/env bash
# Copies the device kernel definition (defconfig + device tree) into a kernel
# tree, so the port can build on a plain upstream Android Common Kernel instead
# of a device-specific fork.
#
# Usage: ./scripts/apply_kernel_overlay.sh <kernel-dir>
#        (or run with KERNEL_SRC set in the environment)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KDIR="${1:-${KERNEL_SRC:-}}"

[ -n "$KDIR" ] || { echo "usage: $0 <kernel-dir>" >&2; exit 1; }
[ -d "$KDIR/arch/arm64" ] || { echo "not an arm64 kernel tree: $KDIR" >&2; exit 1; }

OVL="$ROOT/kernel-overlay"
DTSDIR="$KDIR/arch/arm64/boot/dts/mediatek"
CFGDIR="$KDIR/arch/arm64/configs"

[ -d "$DTSDIR" ] || { echo "missing $DTSDIR (is this an ACK 5.10 tree?)" >&2; exit 1; }
[ -d "$CFGDIR" ] || { echo "missing $CFGDIR" >&2; exit 1; }

cp -f "$OVL/configs/tanzanite_defconfig" "$CFGDIR/tanzanite_defconfig"
cp -f "$OVL/dts/tanzanite.dts" "$OVL/dts/tanzanite-overlay.dts" "$DTSDIR/"

MK="$DTSDIR/Makefile"
if ! grep -q 'tanzanite.dtb' "$MK"; then
    {
        echo ''
        echo '# Device: Xiaomi Redmi Note 14 4G (tanzanite), MT6789 (from kernel-overlay/).'
        echo 'dtb-y += tanzanite.dtb'
        echo 'dtb-y += tanzanite-overlay.dtb'
    } >> "$MK"
fi

echo "applied kernel-overlay to $KDIR"
