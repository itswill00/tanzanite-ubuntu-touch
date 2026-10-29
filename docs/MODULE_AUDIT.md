# Module audit: why audio, torch, haptics and camera are broken

**Summary:** four user-visible bugs (low-quality audio, dead torch, dead vibration, camera crash)
share one root cause — the kernel modules those drivers live in are not shipped in
`vendor-ramdisk-overlay/lib/modules/`, and therefore never load.

This document records how that was determined, what has already been fixed, and exactly what
remains and why it cannot be fixed from this repository alone.

---

## How modules reach the device

Three separate lists describe the module set, and they must agree:

| # | Path | Who reads it | Effect when wrong |
|---|---|---|---|
| 1 | `vendor-ramdisk-overlay/lib/modules/*.ko` | packed into `vendor_boot.img` | driver does not exist on device at all |
| 2 | `vendor-ramdisk-overlay/lib/modules/modules.load` | Halium, at boot, before rootfs | module present but never loaded |
| 3 | `overlay/system/usr/lib/modules-load.d/tanzanite.conf` | `systemd-modules-load`, after rootfs | noise in journal, boot delays |

`deviceinfo` sets `deviceinfo_kernel_disable_modules="true"`, so no module is compiled during the
build. The vendor `.ko` files are MediaTek binaries built against a specific GKI KMI; they ship
only inside the stock `vendor_boot.img` and cannot be rebuilt here.

Run the audit at any time:

```bash
./scripts/check_modules.sh
```

## State before this work

| Check | Result |
|---|---|
| `modules.load` entries | 184 |
| `.ko` files shipped | 207 |
| Modules shipped but never loaded | **23** |
| Entries in `tanzanite.conf` | 174 |
| …of which had a matching `.ko` | **24** (150 dead) |
| udev rules for `leds` / `timed_output` / `backlight` | **none** |

## State after the fixes in this repository

| Check | Result |
|---|---|
| `modules.load` entries | 207, matching 207 `.ko` files exactly |
| Modules shipped but never loaded | 0 |
| `tanzanite.conf` entries | 2 (`zram`, `zsmalloc`), both valid |
| udev rules for `leds` / `timed_output` / `backlight` / torch | added |
| Hardware-critical modules still missing | see below |

Fixed by:

- `f61c30b` — `modules.load` regenerated from the shipped set (23 drivers now load)
- `abff716` — 172 dead entries removed from `modules-load.d`
- `44361f5` — udev permissions for LED, torch, haptics, backlight

**This alone does not restore the four broken features.** It removes the loader errors and the
silent permission failures, but the drivers themselves are still absent. Read on.

---

## Per-feature analysis

### 1. Flashlight / torch

| | |
|---|---|
| Symptom | Torch does nothing; no error shown |
| Expected sysfs | `/sys/class/flashlight_core/flashlight/flashlight_torch` |
| Written by | `tanzanite-flashlight-bridge` (see its `.c` source) |
| Missing modules | `flashlight.ko`, `flashlights-mt6789-o7.ko`, `mtk-pwm.ko` |

The bridge daemon is running and correctly writes `0 0 0 1` / `0 0 0 0` to the sysfs path. The
path never exists because the `flashlight` driver is not loaded, so every write silently fails —
`fopen()` returns NULL and the code returns without logging.

`mtk-pwm.ko` is also missing; the MTK torch driver is driven through a PWM channel, so even with
`flashlight.ko` present the lamp would stay dark without it.

**Status: not fixable here.** All three modules must come from stock `vendor_boot.img`.

### 2. Vibration / haptics

| | |
|---|---|
| Symptom | No haptic feedback anywhere |
| Expected sysfs | `/sys/class/timed_output/vibrator/enable` |
| Missing | nothing — `regulator-vibrator.ko` was shipped and already in `modules.load` |

This one is a *permissions* bug, not a module bug. `regulator-vibrator.ko` was present and loaded,
but `70-tanzanite.rules` had no rule for the `timed_output` class, so `hfd-service` (running as
`phablet`/`system`) could not open the node for writing.

The udev rules added in `44361f5` should fix this. `VibrateDurationExtraMs: 40` in
`tanzanite.yaml` is only a timing tweak and was never the problem.

**Status: likely fixed.** Needs on-device confirmation.

### 3. Audio — low quality

| | |
|---|---|
| Symptom | Sound plays but sounds thin/distorted/low volume |
| Missing modules | `snd-soc-mt6789-afe.ko`, `snd-soc-mt6366.ko`, `mt6789-mt6366.ko`, `audio_ipi.ko`, `adsp.ko`, `snd-soc-audiodsp-common.ko`, `mtk-scp-audio.ko`, `snd-soc-rt5512.ko`, `snd-soc-sipa.ko`, `snd-soc-aw87xx.ko` |

"Low quality" rather than "no sound" is the signature of a partial audio stack. The chain on
MT6789 is:

```
PulseAudio -> audio.primary.mediatek.so (HAL) -> snd-soc-mt6789-afe (AFE) -> mt6366 codec -> speaker amp
                                                    |
                                                    +-> audio_ipi -> adsp (DSP) -> Aurisys processing
```

`audio.primary.mediatek.so` is shipped in the overlay, so the HAL loads and audio plays through the
simplest available path. But with the AFE, codec and DSP modules absent, PulseAudio falls back to a
generic PCM route: no Aurisys DSP, no smartpa initialisation, no proper gain staging. That is
audible as thin, quiet, distorted sound.

Two secondary problems compound it:

**3a. Sample-rate mismatch.** `deviceinfo` sets
`PulseaudioModulesDroid_ExtraCardArgs: "hw_volume=false rate=48000"`, and
`audio_policy_configuration.xml` advertises both 44100 and 48000 Hz. MT6789's AFE runs at 48 kHz
natively; forcing 44.1 kHz input through it requires resampling that the missing DSP would normally
handle.

**3b. Conflicting amplifier configuration.** The tree names *three different* speaker amplifier
chips:

| File | Claims |
|---|---|
| `vendor/etc/aurisys_config.xml` | `smartpa_rt5512` (RT5512) |
| `modules-load.d/tanzanite.conf` (old) | `snd-soc-sipa`, `snd-soc-sipa-tuning`, `snd-soc-aw87xx`, `snd-soc-tfa98xx` |
| `aurisys_config.xml` library paths | `/vendor/lib64/libaudiosmartpartk.so`, `/vendor/etc/audio_param`, `/vendor/etc/smartpa_param/SmartPaVendor1_AudioParam.dat` |

These cannot all be right. Exactly one amp is fitted. Worse, the libraries the config references
(`libaudiosmartpartk.so`, `audio_param/`, `smartpa_param/`) are **not present anywhere in this
repository**, so Aurisys cannot initialise regardless.

**Status: partially diagnosable, not fixable here.** Requires the stock `vendor` partition to
determine the real amp and to supply the DSP libraries.

### 4. Camera — crashes on open

| | |
|---|---|
| Symptom | Camera app crashes immediately; camera cannot be opened |
| Shipped | `vendor/lib64/libmtkcam_metastore.so` |
| Missing modules | `camera_isp.ko`, `camera_mem.ko`, `imgsensor_isp6s.ko`, `camera_eeprom.ko`, `camera_dip_isp6s.ko`, `camera_rsc_isp60.ko`, `camera_fdvt_isp51.ko`, `mainaf.ko`, `main2af.ko`, `main3af.ko`, `subaf.ko`, `sub2af.ko`, `mtk-composite.ko`, `sensorhub.ko` |

The entire ISP pipeline is missing. `libmtkcam_metastore.so` loads and tries to open the camera,
the kernel has no ISP device nodes, and the metadata service dereferences a null device handle —
hence a crash rather than a clean error.

`mtk-composite.ko` is notable: it is the MediaTek camera composite driver that registers the
`/dev/mtk_cam*` nodes. Without it nothing camera-related can be opened at all.

`ro.odm.camera=1` in `prop.halium` only enables the rear wide-angle lens selection in userspace; it
has no effect while the ISP is absent.

**Status: not fixable here.** This is why the upstream port lists camera as "in progress".

---

## Remediation procedure

### Step 1 — extract the stock module set

You need `vendor_boot.img` from firmware **`OS2.0.214.0.VOGEUXM`** (the version this port targets).

```bash
./scripts/extract_stock_modules.sh /path/to/vendor_boot.img ./stock-modules
```

The script unpacks every ramdisk fragment, collects all `.ko` files, diffs them against what this
repository ships, and prints which hardware-critical modules are recoverable from stock.

### Step 2 — copy in what is missing

```bash
cp stock-modules/modules/*.ko vendor-ramdisk-overlay/lib/modules/
```

If `extract_stock_modules.sh` reports a module as *"not in stock either"*, the vendor layout differs
from what this port assumes. In that case check whether the driver is built into the kernel
(`/proc/config.gz` on device: `CONFIG_MTK_CAMERA=y` etc.) or lives on the `vendor` partition instead
of `vendor_boot`.

### Step 3 — regenerate the load lists

```bash
./scripts/sync_modules_load.sh        # rebuild modules.load from the shipped set
./scripts/sync_modules_load_conf.sh   # rebuild modules-load.d
./scripts/check_modules.sh            # verify
```

### Step 4 — rebuild and reflash

```bash
./build.sh -b workdir
./scripts/build_zip_local.sh
```

Only `vendor_boot.img` and the installer zip change, but the zip is what you flash.

### Step 5 — resolve the audio amplifier question

Do not guess. On a device running stock HyperOS, collect:

```bash
# which amp driver is actually bound
ls /sys/bus/i2c/drivers/ | grep -iE 'sipa|aw87|rt5512|tfa'
# which audio modules the stock kernel loaded
cat /proc/modules | grep -iE 'snd-soc|smartpa'
# the real aurisys config and DSP payloads
adb pull /vendor/etc/aurisys_config.xml
adb pull /vendor/etc/audio_param
adb pull /vendor/etc/smartpa_param
adb pull /vendor/lib64/libaudiosmartpartk.so
```

Then reconcile `aurisys_config.xml` in this repo with reality, and ship the DSP libraries in
`overlay/system/usr/share/halium-overlay/vendor/` under the same paths the config expects.

---

## Quick reference: what is missing, and for which feature

| Module | Feature | In stock? |
|---|---|---|
| `flashlight` | torch | expected yes |
| `flashlights-mt6789-o7` | torch | expected yes |
| `mtk-pwm` | torch, backlight | expected yes |
| `snd-soc-mt6789-afe` | audio | expected yes |
| `snd-soc-mt6366` | audio | expected yes |
| `mt6789-mt6366` | audio | expected yes |
| `audio_ipi` | audio DSP | expected yes |
| `adsp` | audio DSP | expected yes |
| `snd-soc-audiodsp-common` | audio DSP | expected yes |
| `mtk-scp-audio` | audio DSP | expected yes |
| `snd-soc-rt5512` / `snd-soc-sipa` / `snd-soc-aw87xx` | speaker amp | **one** of them |
| `camera_isp` | camera | expected yes |
| `camera_mem` | camera | expected yes |
| `imgsensor_isp6s` | camera | expected yes |
| `camera_eeprom` | camera | expected yes |
| `camera_dip_isp6s` | camera | expected yes |
| `camera_rsc_isp60` | camera | expected yes |
| `camera_fdvt_isp51` | camera | expected yes |
| `mainaf`, `main2af`, `main3af`, `subaf`, `sub2af` | autofocus | expected yes |
| `mtk-composite` | camera device nodes | expected yes |
| `sensorhub` | sensors, camera metadata | expected yes |
| `regulator-vibrator` | haptics | **shipped** — was a udev bug |

"expected yes" means the module is normally part of a MT6789 vendor_boot; it has not been verified
against tanzanite firmware in this repository.
