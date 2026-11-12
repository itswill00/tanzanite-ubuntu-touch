# Ubuntu Touch 24.04 (Noble) for Redmi Note 14 4G (`tanzanite`)

<p align="center">
  <a href="https://github.com/itswill00/tanzanite-ubuntu-touch/releases/latest"><img src="https://img.shields.io/github/v/release/itswill00/tanzanite-ubuntu-touch?style=flat-square&label=release&color=77216F" alt="Latest release"></a>
  <a href="https://github.com/itswill00/tanzanite-ubuntu-touch/actions/workflows/validate.yml"><img src="https://img.shields.io/github/actions/workflow/status/itswill00/tanzanite-ubuntu-touch/validate.yml?branch=main&style=flat-square&label=validate" alt="Validation status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/itswill00/tanzanite-ubuntu-touch?style=flat-square&color=blue" alt="License"></a>
  <img src="https://img.shields.io/badge/Ubuntu%20Touch-24.04-E95420?style=flat-square&logo=ubuntu&logoColor=white" alt="Ubuntu Touch 24.04">
  <img src="https://img.shields.io/badge/Halium-12-4E9A06?style=flat-square" alt="Halium 12">
  <img src="https://img.shields.io/badge/device-Redmi%20Note%2014%204G-FF6900?style=flat-square&logo=xiaomi&logoColor=white" alt="Redmi Note 14 4G">
  <img src="https://img.shields.io/badge/SoC-MT6789-8E44AD?style=flat-square" alt="MT6789">
  <img src="https://img.shields.io/badge/kernel-5.10%20GKI-333333?style=flat-square&logo=linux&logoColor=white" alt="Kernel 5.10 GKI">
</p>

<p align="center">
  <a href="https://github.com/itswill00/tanzanite-ubuntu-touch/commits/main"><img src="https://img.shields.io/github/last-commit/itswill00/tanzanite-ubuntu-touch?style=flat-square&label=last%20commit" alt="Last commit"></a>
  <a href="https://github.com/itswill00/tanzanite-ubuntu-touch/stargazers"><img src="https://img.shields.io/github/stars/itswill00/tanzanite-ubuntu-touch?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/itswill00/tanzanite-ubuntu-touch/issues"><img src="https://img.shields.io/github/issues/itswill00/tanzanite-ubuntu-touch?style=flat-square" alt="Issues"></a>
  <a href="https://github.com/itswill00/tanzanite-ubuntu-touch/releases"><img src="https://img.shields.io/github/downloads/itswill00/tanzanite-ubuntu-touch/total?style=flat-square&label=downloads" alt="Downloads"></a>
</p>

Build recipe + reproducible tooling for **Ubuntu Touch 24.04 (Noble Numbat) / Halium 12** on the
**Xiaomi Redmi Note 14 4G** (`tanzanite`, MediaTek Helio G99 / MT6789).

This repository contains everything needed to build the port **from zero** on a Linux host:
kernel configuration patches, the Halium `deviceinfo`, the rootfs overlay (drivers, audio, graphics,
udev, sensors), the recovery installer, and documentation of every value that had to be extracted
from the stock firmware.

> **Status:** built and assembled successfully. Not yet flashed to hardware by this build.
> Hardware support claims below are inherited from the upstream port; see [Hardware status](#hardware-status).

---

## Table of contents

- [What is in this repository](#what-is-in-this-repository)
- [Architecture of the port](#architecture-of-the-port)
- [Quick start (prebuilt installer)](#quick-start-prebuilt-installer)
- [Building from zero](#building-from-zero)
- [Build outputs](#build-outputs)
- [Hardware status](#hardware-status)
- [Repository layout](#repository-layout)
- [Upstream projects and attribution](#upstream-projects-and-attribution)
- [Known issues and caveats](#known-issues-and-caveats)
- [Self-checks](#self-checks)
- [Versioning](#versioning)
- [Changelog](#changelog)
- [Bootloader and AVB](#bootloader-and-avb)
- [What was fixed in this repository](#what-was-fixed-in-this-repository)
- [License](#license)

---

## What is in this repository

| Piece | What it is |
| --- | --- |
| `deviceinfo` | Halium build configuration: kernel source, defconfig, boot image offsets, header version, Halium version |
| `build.sh` | Thin wrapper around UBports `halium-generic-adaptation-build-tools` |
| `build-patches/` | Patches applied to the upstream build tools so the kernel can be built on a **native aarch64 host** |
| `overlay/` | Rootfs overlay: udev rules, ofono MTK config, sensorfw HIDL, usb-moded, upower BMS filter, systemd units, libhybris bits |
| `ramdisk-overlay/` | Boot ramdisk modifications (Halium init scripts, panic/telnet) |
| `ramdisk-recovery-overlay/` | Recovery ramdisk overlay (recovery fstab, prop.default additions) |
| `vendor-ramdisk-overlay/` | Prebuilt MediaTek vendor kernel modules shipped inside `vendor_boot` |
| `flashable_zips/` | Recovery installer: `update-binary` template, busybox/erofs/lptools/avbctl tooling, vbmeta images |
| `switcher-app/` | Android companion app for one-tap dual-boot switching (Jetpack Compose) |
| `docs/` | Flashing guides (EN/ID) and troubleshooting notes |
| `scripts/` | Helper scripts used for this build (kernel build, image assembly, zip packaging) |
| `artifacts/` | Checksums of the produced installer |

**Not in this repository** (too large for git): the installer zip, `rootfs.img`, `system.img`.
See [Build outputs](#build-outputs).

---

## Architecture of the port

An Ubuntu Touch port is three separate artifacts:

```
boot.img / vendor_boot.img   <- your kernel + Halium initramfs        (built here)
system.img / rootfs.img      <- Ubuntu Touch rootfs (Noble)          (assembled here)
                                 + Halium GSI (android-rootfs.img)   (downloaded, not built)
                                 + device overlay                    (this repo)
```

On Treble-era MediaTek devices the vendor partition holds the hardware drivers, so Halium talks to
them through **libhybris** instead of rebuilding the whole Android system. That is why no LineageOS
tree is needed: only the kernel is compiled, and the generic Halium 12 arm64 GSI provides the
Android side.

Version pairing is fixed by the device's vendor blobs:

| Component | Version | Notes |
| --- | --- | --- |
| Android vendor base | 12 | stock HyperOS `OS2.0.214.0.VOGEUXM` |
| Halium | 12 | `deviceinfo_halium_version="12"` |
| Ubuntu Touch rootfs | 24.04-2.x Noble | channel `24.04-2.x/arm64/android9plus/stable` |
| Kernel | 5.10.272 GKI | Google ACK `android12-5.10-lts`, AppArmor + ThinLTO + CFI |
| Boot image header | v4 | GKI device, `vendor_boot` carries the ramdisk + dtb |

---

## Quick start (prebuilt installer)

If you just want to install, use the prebuilt installer:

- **Download:** [GitHub Releases — v1.1.1](https://github.com/itswill00/tanzanite-ubuntu-touch/releases/tag/v1.1.1)
- **File:** `tanzanite-ut20.04-halium12-v1.1.1-20261030-a8d594e.zip` (927 MiB)
- **SHA-256:** `b4804db36e71b6918f5b4cc457aba45f90c07acba8c557376c28c7b4d1a68374`

> 1.1.1 is a hotfix for the audio crash loop found in the first on-device test of 1.1.0
> (PulseAudio aborting with SIGBUS on speaker playback). See
> [`docs/releases/v1.1.1.md`](docs/releases/v1.1.1.md). Torch and vibration from 1.1.0 are
> unaffected.

Full step-by-step instructions, including the mandatory ext4 reformat and the slot-A dual-boot
layout, are in:

- [`docs/FLASHING_GUIDE_en.md`](docs/FLASHING_GUIDE_en.md) (English)
- [`docs/FLASHING_GUIDE_id.md`](docs/FLASHING_GUIDE_id.md) (Bahasa Indonesia)

**Non-negotiable prerequisites:**

1. Bootloader unlocked, custom recovery (OrangeFox/TWRP) with A/B + terminal support.
2. Firmware **exactly** `OS2.0.214.0.VOGEUXM`. HyperOS 3.x must be downgraded first.
3. `/data` formatted to **unencrypted ext4** — Ubuntu Touch cannot use F2FS or FBE here.

---

## Building from zero

The one-command path is `./scripts/build-all.sh`. By default it does **not** compile the kernel: it
downloads a prebuilt kernel object (a release asset) and injects it via `UBPORTS_PREBUILT_KERNEL_OBJ`.
If the tree has no vendor `.ko` (they are gitignored), it also fetches the published module set, so a
clean checkout builds a functional `vendor_boot`.
Set `BUILD_KERNEL=1` to compile the kernel from the Android Common Kernel source as well, or
`KERNEL_OBJ_DIR=/path/to/out` to reuse a local kernel tree.

The manual steps below build everything from scratch, including the kernel.

### 1. Host requirements

Kernel compilation needs ~20 GB of disk and 8 GB RAM (ThinLTO peaks around 2 GB per linker job).
Both **x86_64 and aarch64** hosts work: `build-all.sh` sets `CROSS_COMPILE=aarch64-linux-gnu-` on
non-aarch64 hosts (install `gcc-aarch64-linux-gnu`), and the patch in `build-patches/` lets the
adaptation tools accept a locally built kernel.

```bash
sudo apt install -y git clang-14 lld-14 llvm-14 libclang-rt-14-dev libssl-dev libelf-dev \
    bc bison flex cpio kmod rsync device-tree-compiler e2fsprogs xxd \
    android-sdk-libsparse-utils zlib1g-dev img2simg fakeroot zip unzip wget
```

### 2. Get the kernel

```bash
git clone --depth=1 --branch android12-5.10-lts \
    https://android.googlesource.com/kernel/common kernel
./scripts/apply_kernel_overlay.sh kernel
```

The defconfig used is `kernel-overlay/configs/tanzanite_defconfig`, copied in by
`scripts/apply_kernel_overlay.sh` along with the device tree. It must provide:

```
CONFIG_SECURITY_APPARMOR=y   # required by Ubuntu Touch app confinement
CONFIG_LTO_CLANG_THIN=y
CONFIG_CFI_CLANG=y
CONFIG_DEVTMPFS=y            # plus the namespace/VT options listed in UBports docs
```

### 3. Build the kernel

```bash
cd kernel
make O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 tanzanite_defconfig
make O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 -j"$(nproc)"
```

Takes ~29 minutes on 8 cores. **Do not delete `out/`** — the 1.2 GB `.thinlto-cache` makes
incremental rebuilds take ~2 minutes instead of ~29.

### 4. Get the build tools

```bash
git clone https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools build
# always apply the patch: it adds UBPORTS_PREBUILT_KERNEL_OBJ support and switches
# the dtbo tool to a Python 3 mkdtboimg (libufdt android13-gsi).
git -C build apply ../build-patches/halium-generic-adaptation-build-tools.patch
```

### 5. Assemble the images

```bash
export UBPORTS_PREBUILT_KERNEL_OBJ="$PWD/kernel/out"   # or an extracted prebuilt kernel object
./build.sh -b workdir
```

This produces `boot.img`, `vendor_boot.img`, `dtbo.img` and `device_tanzanite.tar.xz`.

### 6. Assemble the flashable rootfs image (optional)

Only needed if you want `rootfs.img` / `system.img` instead of the recovery installer:

```bash
export ROOTFS_URL="https://ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%252F24.04-2.x/lastStableBuild/artifact/ubuntu-touch-android9plus-rootfs-arm64.tar.gz"
export OTA_CHANNEL="24.04-2.x/arm64/android9plus/stable"
./build/prepare-fake-ota.sh out/device_tanzanite_usrmerge.tar.xz ota
./build/system-image-from-ota.sh ota/ubuntu_command images
```

### 7. Build the recovery installer zip

```bash
./scripts/build_zip_local.sh
```

---

## Build outputs

Produced by the build described above, on an x86_64 Ubuntu 24.04 host cross-compiling with clang
(`CROSS_COMPILE=aarch64-linux-gnu-`). `rootfs.img` / `system.img` come only from the optional step 6
and are not part of the recovery installer path.

| Artifact | Size | Notes |
| --- | --- | --- |
| `Image` | 35,220,712 B | arm64 kernel, magic `ARMd` |
| `Image.gz` | 13,248,618 B | |
| `tanzanite.dtb` | 178,479 B | |
| `tanzanite-overlay.dtb` | 135,443 B | |
| `dtbo.img` | 135,507 B | magic `d7b7ab1e`, 1 entry |
| `boot.img` | 67,108,864 B | header v4, AVB hash footer |
| `vendor_boot.img` | 67,108,864 B | header v4, kernel@`0x40000000`, ramdisk@`0x66f00000`, tags/dtb@`0x47c80000` |
| `device_tanzanite.tar.xz` | 31,864,824 B | device tarball (overlay store mode) |
| `tanzanite-ut24.04-halium12-v1.2.0-*.zip` | 1,179,271,868 B | recovery installer |

Verified: `md5sum` of `boot.img`, `vendor_boot.img` and `dtbo.img` inside the zip are **identical**
to those in `device_tanzanite.tar.xz`, so the installer ships the kernel built from this recipe.

---

## Hardware status

Inherited from the upstream port (`iprjkt/tanzanite-halium`). **Not independently verified** by this build.

| Feature | Status |
| --- | --- |
| Display / touchscreen | Working |
| Lomiri UI / compositor | Working |
| GPU acceleration (Mali-G57 MC2, libhybris) | Working |
| Battery / power management | Working (UPower BMS filter shim) |
| Rotation / sensors | Working (HIDL 2.0 sensorfw) |
| Cellular / 4G LTE data, dual SIM | Working (ofono, MTK IRadio@1.2) |
| WiFi / Bluetooth | Working (ConnMan, BlueZ, Bluebinder) |
| Audio playback + microphone | **Fixed in this repo** — DSP modules + stock Aurisys config shipped; needs on-device confirmation |
| Flashlight | **Fixed in this repo** — `flashlight`/`mtk-pwm` modules shipped; needs on-device confirmation |
| Vibration | **Fixed in this repo** — was a missing udev rule, not a module; needs on-device confirmation |
| Camera | **Fixed in this repo** — full ISP pipeline shipped; needs on-device confirmation |

Status rows above "Audio" are inherited from the upstream port and have not been independently
verified by this build.

Audio, torch, vibration and camera were all broken in the upstream port and are fixed here. The
first three shared a single cause: 178 vendor kernel modules were missing, because they live on the
`vendor_dlkm` partition inside `super.img` rather than in `vendor_boot` where the port was looking.
They were recovered from official firmware `OS2.0.214.0.VOGEUXM` and are now shipped. Vibration was
a udev permission bug, not a module bug. Full analysis and reproduction steps:
[`docs/MODULE_AUDIT.md`](docs/MODULE_AUDIT.md).

"Needs on-device confirmation" is literal: the modules are present and loadable per
`modules.load`, and every path the audio config references exists, but driver binding and
end-to-end function cannot be verified without hardware.

---

## Repository layout

```
.
├── deviceinfo                  # Halium build configuration (the important file)
├── build.sh                    # wrapper for upstream build tools
├── build-patches/
│   ├── halium-generic-adaptation-build-tools.patch
│   └── UPSTREAM_COMMIT         # upstream revision the patch applies to
├── overlay/system/             # files overlaid onto the UT rootfs
│   ├── etc/                    # ofono, sensorfw, usb-moded, systemd, upower, deviceinfo yaml
│   ├── usr/lib/udev/rules.d/   # 70-tanzanite.rules, 99-z-android.rules
│   ├── usr/lib/aarch64-linux-gnu/mir/   # libhybris Mir client/server platforms
│   └── usr/share/halium-overlay/        # vendor blobs & configs for the Android container
├── ramdisk-overlay/            # boot ramdisk additions
├── ramdisk-recovery-overlay/   # recovery ramdisk additions
├── vendor-ramdisk-overlay/lib/modules/  # prebuilt MTK vendor .ko files
├── flashable_zips/
│   ├── update-binary.template.sh        # the installer logic (10 stages)
│   ├── common/tools/                    # busybox, avbctl, erofs tools, lptools
│   └── format_userdata_ext4/            # ext4 reformat utility
├── switcher-app/               # Android dual-boot switcher (Kotlin/Compose)
├── scripts/                    # build helpers used to produce the artifacts above
├── docs/                       # flashing guides, troubleshooting
└── artifacts/                  # checksums
```

### Key `deviceinfo` values (and where they come from)

All boot image values were extracted from the stock `boot.img` / `vendor_boot.img` using
`unpack_bootimg.py` from `LineageOS/android_system_tools_mkbootimg`:

| Setting | Value | Source |
| --- | --- | --- |
| `deviceinfo_bootimg_header_version` | `4` | GKI device (Android 12) |
| `deviceinfo_flash_pagesize` | `4096` | stock image page size |
| `deviceinfo_flash_offset_kernel` | `0x40000000` | stock kernel load address |
| `deviceinfo_flash_offset_ramdisk` | `0x66f00000` | stock ramdisk load address |
| `deviceinfo_flash_offset_tags` / `_dtb` | `0x47c80000` | stock tags / dtb address |
| `deviceinfo_kernel_cmdline` | `bootopt=64S3,32N2,64N2` | stock cmdline (stripped of `console=tty0`, see caveats) |
| `deviceinfo_bootimg_os_version` | `12` | stock boot image OS version |
| `deviceinfo_bootimg_os_patch_level` | `2025-09` | stock patch level |
| `deviceinfo_ramdisk_compression` | `lz4` | stock ramdisk compression |
| `deviceinfo_rootfs_image_sector_size` | `4096` | UFS storage |
| `deviceinfo_dtb` / `deviceinfo_dtbo` | `mediatek/tanzanite.dtb` / `mediatek/tanzanite-overlay.dtb` | built from kernel source |

---

## Upstream projects and attribution

This work stands on several projects. All credit for the hard parts goes to them:

| Project | Role |
| --- | --- |
| [iprjkt/tanzanite-halium](https://github.com/iprjkt/tanzanite-halium) | Original Halium 12 port for tanzanite: `deviceinfo`, overlay, installer, switcher app. **Base of this repository.** |
| [Google ACK `android12-5.10-lts`](https://android.googlesource.com/kernel/common) | GKI 5.10 kernel base. Tanzanite defconfig + device tree are vendored in `kernel-overlay/`. |
| [UBports](https://ubports.com) / [docs.ubports.com](https://docs.ubports.com) | Porting documentation, rootfs, Halium GSI, build tools |
| [Halium](https://halium.org) | Android/Linux hardware abstraction |
| [libhybris](https://github.com/libhybris/libhybris) | Android driver compatibility layer |
| [LineageOS](https://lineageos.org) | `mkbootimg`, `libufdt`, device trees |
| [itswill00/android_kernel_xiaomi_tanzanite](https://github.com/itswill00/android_kernel_xiaomi_tanzanite) | Community kernel bring-up |

Xiaomi has **not** released kernel source for `tanzanite` (open GPL requests: MiCode issues
#40276, #40803, #40812, #40929, #40940, #41142). Everything here is built on community work and
GKI sources.

---

## Known issues and caveats

1. **`systempart` is not set.** The installer provisions `/data/ubuntu` (subdirectory dual-boot),
   so use `rootfs.img` → `/data/ubuntu`, not `system.img` on the system partition. To switch to
   system-as-root you must add
   `deviceinfo_kernel_cmdline="console=tty0 systempart=/dev/disk/by-partlabel/system"` and
   `deviceinfo_use_overlaystore="true"`, then rebuild.

2. **Missing kernel modules were the dominant bug class — now fixed.** Audio, torch and camera all
   failed because 178 vendor `.ko` files were absent. They are **not** in `vendor_boot` (the stock
   image contains exactly the 207 modules this repo already shipped); they live on the `vendor_dlkm`
   partition inside `super.img`. All 178 have been recovered from official firmware and are now
   shipped, bringing the total to 385. See [`docs/MODULE_AUDIT.md`](docs/MODULE_AUDIT.md).

3. **Rootfs version.** This build tracks the latest Ubuntu Touch release series,
   **24.04-2.x (Noble)**, using the official
   `ubuntu-touch-rootfs/job/ubports%2F24.04-2.x` artifact, which ships libhybris and is what the
   installer expects. Override `ROOTFS_URL` / `OTA_CHANNEL` to pin 24.04-1.x or 20.04 instead.

4. **`mkdtboimg.py` from `libufdt` branch `pie-gsi` is Python 2 only.** It fails on `xrange` and
   `array('c', str)`. Use the `lineage-21.0` version, which is Python 3 native.

5. **Native aarch64 hosts cannot run the upstream prebuilt toolchains** (they are x86_64 binaries).
   Hence `build-patches/`. On x86_64 you do not need the patch.

6. **Firmware lock-in.** Built and tested against `OS2.0.214.0.VOGEUXM`. Newer HyperOS 3.x uses a
   different kernel (6.12) and must be downgraded before installing.

7. **Audio amplifier: resolved.** The fitted amplifier is a **SiA81xx** (`sia81xx_sixth`), not the
   RT5512 the upstream overlay claimed. The stock `aurisys_config.xml` and its DSP payloads are now
   shipped, and every path the config references exists. See `docs/MODULE_AUDIT.md`.

## Self-checks

Three scripts exist so the failure modes above are caught mechanically rather than by ear on a
phone. All three run in CI on every push.

```bash
./scripts/check_modules.sh          # three module lists agree; hardware-critical groups present
./scripts/check_device_config.sh    # cmdline, sysfs paths, audio rates, aurisys, vibrator backend
./scripts/extract_stock_modules.sh vendor_boot.img   # diff stock modules against what ships here
```

`sync_modules_load.sh` and `sync_modules_load_conf.sh` regenerate the two module lists from the
`.ko` files on disk, so they cannot drift again. Both support `--check` for CI.

## Versioning

Port version is in [`VERSION`](VERSION). Artifacts are named
`tanzanite-ut24.04-halium12-v<version>-<yyyymmdd>-<commit>.zip` and every build writes a
`.sha256` and a `.buildinfo` alongside it, plus a `META-INF/tanzanite/build.prop` manifest inside
the zip that the installer records at `/data/ubuntu/etc/tanzanite-build.prop`. Scheme, bump rules
and release checklist: [`docs/VERSIONING.md`](docs/VERSIONING.md).

## What was fixed in this repository

Relative to the upstream port, the following defects were found and corrected:

| Commit | Fix |
|---|---|
| `e3d3b0f` | **178 vendor modules recovered from `vendor_dlkm`** — fixes torch, audio DSP and camera ISP; total 385 modules |
| `117b7e4` | stock `aurisys_config.xml` + DSP payloads replace the wrong RT5512 config; real amp is SiA81xx |
| `f61c30b` | `modules.load` regenerated: 184 → 207 entries, 23 drivers that were shipped but never loaded now load |
| `abff716` | 172 dead entries removed from `modules-load.d` (150 had no matching `.ko`, causing boot-time errors) |
| `44361f5`, `46d1ed8` | udev rules for LED, torch, `timed_output`, `leds/vibrator`, backlight — there were none |
| `99d115e` | flashlight bridge probes multiple node names/formats and logs failures instead of failing silently |
| `f94052b` | audio policy pinned to 48 kHz to match the PulseAudio droid card, removing a CPU resample |
| `ec54bb6` | `console=tty0` added to the kernel cmdline (required by UBports, was absent) |
| `1a1453c`, `13584d1`, `763f447` | module audit, config checker, CI |

---

## Bootloader and AVB

Communities often claim Ubuntu Touch requires patching the bootloader with fenrir or lkpatcher
first. **It does not.** Verified boot is enforced through `vbmeta`, which the installer already
patches to disable verification and verity, and `lkpatcher` cannot patch tanzanite anyway: the tool
only speaks ARM32 Thumb-2 while tanzanite's LK is AArch64 (0 of 6 default patches apply).

Patching LK means modifying `bl2_ext`, which runs at EL3 — a wrong offset there bricks the device
beyond fastboot recovery. Read [`docs/BOOTLOADER.md`](docs/BOOTLOADER.md) before considering it.

## Changelog

Release notes for every version, including what was broken and why, live in
[`CHANGELOG.md`](CHANGELOG.md). Current version: **1.1.1**.

## License

- Contents derived from `iprjkt/tanzanite-halium`: Apache-2.0, see [`LICENSE`](LICENSE).
- Kernel is Google ACK (GPL-2.0). The tanzanite defconfig and device tree in `kernel-overlay/`
  are GPL-2.0 from `iprjkt/evernight-gki`.
- Patches and documentation added here: Apache-2.0.
