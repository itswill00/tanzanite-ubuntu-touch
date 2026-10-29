# Module audit: audio, torch, haptics and camera

**Outcome: fixed.** All four features were traced to missing kernel modules, the modules were
recovered from official stock firmware, and both consistency checkers now pass with no findings.

This document records the investigation, including two wrong assumptions that had to be discarded
along the way, because the correction matters more than the original theory.

---

## How modules reach the device

Three lists describe the module set and must agree:

| # | Path | Who reads it | Effect when wrong |
|---|---|---|---|
| 1 | `vendor-ramdisk-overlay/lib/modules/*.ko` | packed into `vendor_boot.img` | driver does not exist on device |
| 2 | `vendor-ramdisk-overlay/lib/modules/modules.load` | Halium, at boot, before rootfs | module present but never loaded |
| 3 | `overlay/system/usr/lib/modules-load.d/tanzanite.conf` | `systemd-modules-load`, after rootfs | noise in journal, boot delays |

`deviceinfo` sets `deviceinfo_kernel_disable_modules="true"`, so nothing is compiled during the
build; every module is a vendor binary that must be taken from firmware.

Verify at any time:

```bash
./scripts/check_modules.sh
./scripts/check_device_config.sh
```

---

## Wrong assumption #1: "the modules are in vendor_boot"

The port ships 207 modules in `vendor-ramdisk-overlay/`, all taken from `vendor_boot.img`. When
audio, torch and camera turned out to be broken, the natural conclusion was that some of those
files were simply missing.

A stock `vendor_boot.img` was extracted from the official fastboot package
`OS2.0.214.0.VOGEUXM` (7,295,325,817 bytes) and compared:

```
stock vendor_boot ramdisk : 207 .ko files
this repository           : 207 .ko files
in stock but not here     : none
here but not in stock     : none
```

The sets were **identical**. The modules were not missing from `vendor_boot` — they were never in
`vendor_boot` at all. This is correct behaviour for a GKI device: `vendor_boot` carries only the
modules needed to bring up storage and display so the rootfs can mount, and everything else lives
on the `vendor_dlkm` partition.

## Wrong assumption #2: "the speaker amplifier is an RT5512"

The overlay's `aurisys_config.xml` (4.4 KB) named a single amplifier, `smartpa_rt5512`, and pointed
at libraries that exist nowhere on the device (`libaudiosmartpartk.so`, `smartpa_param/...`). The
old `modules-load.d` meanwhile named `snd-soc-sipa`, `snd-soc-aw87xx` and `snd-soc-tfa98xx`.

The stock config is 28,817 bytes and names the libraries the hardware actually uses:

```
aurisys_demo  misound  misoundcrossfade  mtk_bessound  mtk_iir  mtk_speech_enh  sia81xx_sixth
```

The amplifier is a **SiA81xx** (`sia81xx_sixth`, tuned by `sixth_param.txt`). `sipa` in the old
module list was the closest guess and was in fact the right family; `rt5512` and `aw87xx` were
simply wrong. This is why guessing from a module list is not a substitute for reading the stock
config.

---

## Where the modules actually were

```
firmware .tgz (7.3 GB)
└── images/super.img (6.6 GB, sparse)
    └── simg2img -> super.raw (8.0 GB)
        └── lpunpack --slot=0 -> vendor_dlkm_a.img (12.9 MB, EROFS)
            └── fsck.erofs --extract -> lib/modules/*.ko  (202 files)
```

202 modules, **178 of which were absent** from this repository. All 178 are now shipped; the total
is 385 modules and `modules.load` is regenerated to match.

### What each broken feature was missing

| Feature | Modules recovered |
|---|---|
| **Flashlight / torch** | `flashlight`, `flashlights-mt6789-o7`, `mtk-pwm` |
| **Audio DSP** | `snd-soc-mt6789-afe`, `snd-soc-mt6366`, `mt6789-mt6366`, `audio_ipi`, `adsp`, `snd-soc-audiodsp-common`, `mtk-scp-audio` |
| **Camera ISP** | `camera_isp`, `camera_mem`, `imgsensor_isp6s`, `camera_eeprom`, `camera_dip_isp6s`, `camera_rsc_isp60`, `camera_fdvt_isp51`, `mtk-composite` |
| **Autofocus** | `mainaf`, `main2af`, `main3af`, `subaf`, `sub2af` |
| **Sensors / camera metadata** | `sensorhub` |

### Vibration was never a module problem

`regulator-vibrator.ko` was already shipped and already loaded. `hfd-service` probes, in order:
binder AIDL, binder HIDL, `/sys/class/leds/vibrator`, `/sys/class/timed_output/vibrator`,
force-feedback input, and finally `VibratorDummy`. On MT6789 the driver registers a `timed_output`
device, so `VibratorLegacy` is the backend that applies — and `usable()` calls `access()`, which
fails without a udev rule granting the desktop user write permission. hfd-service then fell through
to `VibratorDummy`, which silently ignores every request. Fixed by the udev rules in
`70-tanzanite.rules`.

---

## State before and after

| Check | Before | After |
|---|---|---|
| Modules shipped | 207 | 385 |
| `modules.load` entries | 184 (23 files never loaded) | 385, matching exactly |
| `modules-load.d` entries | 174 (150 with no file) | 2 (`zram`, `zsmalloc`) |
| udev rules for LED/torch/`timed_output`/backlight | none | present |
| Audio policy sample rate | 44100 on 39 profiles | 48000 only, matching the droid card |
| `aurisys_config.xml` | 4.4 KB, wrong amp, dangling library paths | 28.8 KB stock, all paths present |
| `check_modules.sh` | 7 hardware groups broken | all pass |
| `check_device_config.sh` | 8 findings | all pass |

---

## Reproducing this

Everything below is scripted; nothing was done by hand.

```bash
# 1. Download the exact firmware this port targets (EEA, OS2.0.214.0.VOGEUXM)
#    https://cdnorg.d.miui.com/OS2.0.214.0.VOGEUXM/tanzanite_eea_global_images_OS2.0.214.0.VOGEUXM_20260325.0000.00_15.0_eea_9742800e6c.tgz
#    size: 7,295,325,817 bytes

# 2. Extract modules from vendor_boot (proves they are not there)
./scripts/extract_firmware_modules.sh tanzanite.tgz ./fw

# 3. Extract modules from vendor_dlkm inside super.img
tar -I pigz -xf tanzanite.tgz --wildcards '*/images/super.img'
simg2img super.img super.raw
lpunpack --slot=0 super.raw parts/
fsck.erofs --extract=dlkm parts/vendor_dlkm_a.img
cp dlkm/lib/modules/*.ko vendor-ramdisk-overlay/lib/modules/

# 4. Regenerate the load lists and verify
./scripts/sync_modules_load.sh
./scripts/sync_modules_load_conf.sh
./scripts/check_modules.sh
./scripts/check_device_config.sh
```

The audio DSP payloads (`etc/audio_param*`, `etc/sixth_param*.txt`, `lib*/lib_*.so`,
`libaudiosmartpamtk.so`) come from the `vendor_a.img` partition of the same `super.img`, extracted
the same way with `fsck.erofs`.

## Still requires a device

The fixes are verified structurally — the modules are present, loadable per `modules.load`, and
every path the audio config references exists. What cannot be verified without hardware is that the
drivers actually bind and the features work end to end. Specifically worth checking after flashing:

```bash
# torch: the node should now exist
ls -l /sys/class/flashlight_core/flashlight/flashlight_torch
# audio: the AFE and codec should be loaded, and Aurisys should not fall back
lsmod | grep -E 'snd-soc-mt6789-afe|snd-soc-mt6366|audio_ipi|adsp'
journalctl -b | grep -i aurisys
# camera: the ISP nodes should exist
ls /dev/mtk_cam* 2>/dev/null || dmesg | grep -i camera_isp
# vibration: should say legacy, not dummy
journalctl -u hfd-service | grep -i vibrator
```
