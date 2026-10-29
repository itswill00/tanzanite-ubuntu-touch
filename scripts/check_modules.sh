#!/usr/bin/env bash
# Verifies the consistency of the kernel module set shipped in vendor_boot.
#
# Three independent lists describe which modules should exist on the device:
#   1. vendor-ramdisk-overlay/lib/modules/*.ko            <- the files actually shipped
#   2. vendor-ramdisk-overlay/lib/modules/modules.load    <- what Halium loads at boot
#   3. overlay/system/usr/lib/modules-load.d/tanzanite.conf <- what systemd-modules-load asks for
#
# When these disagree, drivers silently do not load and the corresponding hardware
# fails with unrelated-looking symptoms (see docs/MODULE_AUDIT.md).
#
# Usage: ./scripts/check_modules.sh [--strict]
# Exit code: 0 if consistent, 1 if inconsistencies found (with --strict).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODDIR="$ROOT/vendor-ramdisk-overlay/lib/modules"
LOADFILE="$MODDIR/modules.load"
CONFFILE="$ROOT/overlay/system/usr/lib/modules-load.d/tanzanite.conf"
STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

[ -d "$MODDIR" ] || { echo "missing $MODDIR" >&2; exit 1; }

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

list_shipped()  { (cd "$MODDIR" && ls *.ko 2>/dev/null | sed 's/\.ko$//' | sort -u); }
list_loaded()   { grep -vE '^\s*#|^\s*$' "$LOADFILE" 2>/dev/null | sed 's/\.ko$//' | sort -u; }
list_conf()     { grep -vE '^\s*#|^\s*$' "$CONFFILE" 2>/dev/null | sed 's/\.ko$//' | sort -u; }

SHIPPED="$(list_shipped)"
LOADED="$(list_loaded)"
CONF="$(list_conf)"

FAIL=0

bold "== 1. modules.load references a file that is not shipped =="
MISSING_LOAD="$(comm -23 <(echo "$LOADED") <(echo "$SHIPPED"))"
if [ -n "$MISSING_LOAD" ]; then
    red "$(echo "$MISSING_LOAD" | wc -l) module(s) in modules.load have no .ko file:"
    echo "$MISSING_LOAD" | sed 's/^/  - /'
    FAIL=1
else
    green "ok - every module in modules.load is present"
fi

bold "== 2. modules-load.d/tanzanite.conf references a file that is not shipped =="
MISSING_CONF="$(comm -23 <(echo "$CONF") <(echo "$SHIPPED"))"
if [ -n "$MISSING_CONF" ]; then
    red "$(echo "$MISSING_CONF" | wc -l) module(s) in tanzanite.conf have no .ko file:"
    echo "$MISSING_CONF" | sed 's/^/  - /'
    FAIL=1
else
    green "ok - every module in tanzanite.conf is present"
fi

bold "== 3. shipped .ko files that are never loaded =="
NEVER="$(comm -13 <(echo "$LOADED") <(echo "$SHIPPED"))"
if [ -n "$NEVER" ]; then
    printf '\033[33m%s module(s) shipped but absent from modules.load:\033[0m\n' "$(echo "$NEVER" | wc -l)"
    echo "$NEVER" | sed 's/^/  - /'
else
    green "ok - every shipped module is loaded"
fi

bold "== 4. modules-load.d entries not in modules.load =="
CONF_ONLY="$(comm -23 <(echo "$CONF") <(echo "$LOADED"))"
if [ -n "$CONF_ONLY" ]; then
    printf '\033[33m%s entry(ies) only requested by tanzanite.conf:\033[0m\n' "$(echo "$CONF_ONLY" | wc -l)"
    echo "$CONF_ONLY" | sed 's/^/  - /'
fi

bold "== 5. hardware-critical modules =="
# Each group maps to a user-visible feature. A missing entry means that feature
# cannot work regardless of userspace configuration.
check_group() {
    local feature="$1"; shift
    local missing=() found=()
    for m in "$@"; do
        if echo "$LOADED" | grep -qx "$m"; then
            if echo "$SHIPPED" | grep -qx "$m"; then found+=("$m"); else missing+=("$m (in modules.load but no .ko)"); fi
        else
            missing+=("$m (not in modules.load)")
        fi
    done
    if [ ${#missing[@]} -eq 0 ]; then
        green "  $feature: ok (${#found[@]} module(s))"
    else
        red "  $feature: BROKEN"
        printf '    %s\n' "${missing[@]}"
        FAIL=1
    fi
}

check_group "flashlight / torch" \
    flashlight flashlights-mt6789-o7 mtk-pwm
check_group "vibration" \
    regulator-vibrator
check_group "audio DSP (MT6789 AFE + codec)" \
    snd-soc-mt6789-afe snd-soc-mt6366 mt6789-mt6366 audio_ipi adsp \
    snd-soc-audiodsp-common mtk-scp-audio
check_group "audio smartpa / speaker amp" \
    snd-soc-rt5512 snd-soc-sipa snd-soc-aw87xx
check_group "camera ISP pipeline" \
    camera_isp camera_mem imgsensor_isp6s camera_eeprom camera_dip_isp6s \
    camera_rsc_isp60 camera_fdvt_isp51
check_group "camera autofocus" \
    mainaf main2af main3af subaf sub2af mtk-composite
check_group "sensors" \
    sensorhub

echo
if [ "$FAIL" -eq 1 ]; then
    bold "RESULT: inconsistencies found"
    echo "See docs/MODULE_AUDIT.md for the remediation procedure."
    [ "$STRICT" -eq 1 ] && exit 1
else
    green "RESULT: all module lists are consistent"
fi
exit 0
