#!/usr/bin/env bash
# Validates that the device configuration files agree with each other and with
# the hardware nodes they reference.
#
# Every check below corresponds to a bug that actually shipped in this port, so
# this script exists to stop those classes of mistake from recurring:
#
#   - a deviceinfo path pointing at a sysfs node no shipped driver creates
#   - a daemon configured for a backend the rootfs does not use
#   - an audio policy rate that contradicts the PulseAudio card args
#   - an aurisys config naming an amplifier whose libraries are not shipped
#
# Usage: ./scripts/check_device_config.sh [--strict]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVINFO="$ROOT/deviceinfo"
YAML="$ROOT/overlay/system/etc/deviceinfo/devices/tanzanite.yaml"
AUDIO_POLICY="$ROOT/overlay/system/usr/share/halium-overlay/vendor/etc/audio_policy_configuration.xml"
AURISYS="$ROOT/overlay/system/usr/share/halium-overlay/vendor/etc/aurisys_config.xml"
VENDOR_OVERLAY="$ROOT/overlay/system/usr/share/halium-overlay/vendor"
MODDIR="$ROOT/vendor-ramdisk-overlay/lib/modules"
STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
FAIL=0

# shellcheck disable=SC1090
source "$DEVINFO"

bold "== 1. kernel cmdline requirements =="
if [[ " ${deviceinfo_kernel_cmdline} " == *" console=tty0 "* ]]; then
    green "ok - console=tty0 present"
else
    red "console=tty0 missing from deviceinfo_kernel_cmdline"
    red "  UBports requires it; a boot failure without it produces no output at all."
    FAIL=1
fi

bold "== 2. deviceinfo paths must have a driver that creates them =="
# Values live in the deviceinfo YAML, not in the build deviceinfo file.
yaml_get() {
    [ -f "$YAML" ] || return 1
    grep -oE "^[[:space:]]*$1:[[:space:]]*[^[:space:]]+" "$YAML" 2>/dev/null \
        | head -1 | sed 's/.*:[[:space:]]*//'
}
# Each entry: <yaml key> <sysfs path> <module that creates it> <feature>
check_path() {
    local key="$1" path="$2" mod="$3" feature="$4"
    local val
    val="$(yaml_get "$key")"
    [ -n "$val" ] || return 0
    if [ ! -f "$MODDIR/$mod.ko" ]; then
        red "  $key -> $val"
        red "    but $mod.ko is not shipped, so $feature cannot work"
        FAIL=1
    else
        green "  $key -> $val (driver: $mod.ko)"
    fi
}
check_path SingleColorLedSysfsPath "/sys/class/leds/green" "leds-mtk" "the notification LED"
check_path FlashlightSysfsPath     "/run/flashlight_bridge" "flashlight" "the torch"

bold "== 3. flashlight bridge target =="
# The bridge writes to a kernel torch node; make sure the driver behind it ships.
if [ -f "$MODDIR/flashlight.ko" ]; then
    green "  ok - flashlight.ko shipped"
else
    red "  flashlight.ko not shipped: /run/flashlight_bridge will accept writes and"
    red "  silently do nothing, because no /sys/class/flashlight_core node exists."
    FAIL=1
fi

bold "== 4. audio policy vs PulseAudio card args =="
CARD_ARGS="$(grep -oE 'PulseaudioModulesDroid_ExtraCardArgs:[[:space:]]*"[^"]*"' "$YAML" 2>/dev/null | grep -oE 'rate=[0-9]+' | cut -d= -f2 || true)"
if [ -n "$CARD_ARGS" ] && [ -f "$AUDIO_POLICY" ]; then
    if grep -q "samplingRates=\"[^\"]*\b${CARD_ARGS}\b" "$AUDIO_POLICY"; then
        green "  ok - audio policy advertises the ${CARD_ARGS} Hz rate used by the droid card"
    else
        red "  audio policy does not advertise ${CARD_ARGS} Hz but the droid card forces it"
        FAIL=1
    fi
    OTHER=44100
    if [ "$CARD_ARGS" != "$OTHER" ] && grep -q "samplingRates=\"[^\"]*${OTHER}" "$AUDIO_POLICY"; then
        yellow "  note - policy still advertises ${OTHER} Hz; clients may pick it and force"
        yellow "         a CPU resample (the DSP that would handle it is not shipped)"
    fi
else
    yellow "  skipped (no rate= in card args or no audio policy)"
fi

bold "== 5. audio DSP modules =="
MISSING_DSP=()
for m in snd-soc-mt6789-afe snd-soc-mt6366 mt6789-mt6366 audio_ipi adsp \
         snd-soc-audiodsp-common mtk-scp-audio; do
    [ -f "$MODDIR/$m.ko" ] || MISSING_DSP+=("$m")
done
if [ ${#MISSING_DSP[@]} -eq 0 ]; then
    green "  ok - audio DSP chain complete"
else
    red "  ${#MISSING_DSP[@]} audio DSP module(s) not shipped:"
    printf '    %s\n' "${MISSING_DSP[@]}"
    red "  Audio will fall back to a generic PCM route: audible as thin/distorted output."
    FAIL=1
fi

bold "== 6. aurisys amplifier consistency =="
if [ -f "$AURISYS" ]; then
    # Collect amplifier names the config references.
    AMPS="$(grep -oE 'library name="[^"]*"' "$AURISYS" | sed 's/.*name="//;s/"//' | grep -viE 'aurisys_demo' | sort -u || true)"
    if [ -n "$AMPS" ]; then
        for amp in $AMPS; do
            # Strip a leading smartpa_ prefix to match the kernel module name.
            mod="snd-soc-${amp#smartpa_}"
            if [ -f "$MODDIR/$mod.ko" ]; then
                green "  ok - $amp -> $mod.ko shipped"
            else
                red "  $amp referenced by aurisys_config.xml but $mod.ko is not shipped"
                FAIL=1
            fi
        done
    fi
    # The config also points at DSP payloads; make sure they exist in the overlay.
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        rel="${p#/vendor/}"
        if [ ! -e "$VENDOR_OVERLAY/$rel" ]; then
            red "  aurisys_config.xml references $p but it is not in the vendor overlay"
            FAIL=1
        fi
    done < <(grep -oE '(lib_path|lib64_path|param_path)="[^"]*"' "$AURISYS" | cut -d'"' -f2 | sort -u)
else
    yellow "  skipped (no aurisys_config.xml)"
fi

bold "== 7. camera ISP modules =="
MISSING_CAM=()
for m in camera_isp camera_mem imgsensor_isp6s camera_eeprom mtk-composite; do
    [ -f "$MODDIR/$m.ko" ] || MISSING_CAM+=("$m")
done
if [ ${#MISSING_CAM[@]} -eq 0 ]; then
    green "  ok - camera ISP pipeline complete"
else
    red "  ${#MISSING_CAM[@]} camera module(s) not shipped:"
    printf '    %s\n' "${MISSING_CAM[@]}"
    red "  The camera HAL will load and then crash opening a non-existent ISP node."
    FAIL=1
fi

bold "== 8. vibrator backend =="
# hfd-service probes leds/vibrator then timed_output/vibrator, then gives up and
# uses a dummy backend that silently ignores every request.
if [ -f "$MODDIR/regulator-vibrator.ko" ]; then
    green "  ok - regulator-vibrator.ko shipped (provides /sys/class/timed_output/vibrator)"
    if grep -qE 'timed_output' "$ROOT/overlay/system/usr/lib/udev/rules.d/70-tanzanite.rules" 2>/dev/null; then
        green "  ok - udev rule covers timed_output so hfd-service can write it"
    else
        red "  no udev rule for timed_output: hfd-service will fall back to a dummy backend"
        FAIL=1
    fi
else
    red "  regulator-vibrator.ko not shipped: hfd-service has no backend, haptics are a no-op"
    FAIL=1
fi

echo
if [ "$FAIL" -eq 1 ]; then
    bold "RESULT: device configuration has unresolved problems"
    echo "See docs/MODULE_AUDIT.md for the remediation procedure."
    [ "$STRICT" -eq 1 ] && exit 1
else
    green "RESULT: device configuration is consistent"
fi
exit 0
