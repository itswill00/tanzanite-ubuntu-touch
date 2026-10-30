# Changelog

All notable changes to this port are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) with the bump rules described in
[`docs/VERSIONING.md`](docs/VERSIONING.md).

Artifacts are named `tanzanite-ut<UT>-halium<H>-v<version>-<date>-<commit>.zip`. Only the newest
artifact is linked from the README; older ones remain under their release tags.

## [1.1.1] — 2026-10-30

Hotfix from the first on-device test of 1.1.0. Torch and vibration verified working; audio did
not survive contact with the hardware — PulseAudio aborted in a loop.

### Fixed

**PulseAudio no longer crash-loops on speaker playback.** The stock
`aurisys_config.xml` runs `aurisys_demo` + `sia81xx_sixth` in the SMARTPA scenario; on Ubuntu
Touch that chain aborts PulseAudio with a SIGBUS through libhybris before one frame is written.
The scenario now runs `misoundcrossfade` + `misound` (the proven `PLAYBACK_NORMAL` chain), while
the kernel `snd_soc_sipa` driver keeps powering the SiA amplifier. On-device evidence, diagnosis
and A/B steps: [`docs/releases/v1.1.1.md`](docs/releases/v1.1.1.md).

### Known issues

- Camera still crash-loops (`camerahalserver` signal 6 every ~5 s). Next in line.
- `audio_policy_configuration.xml` is still the hand-written file; to be replaced with the stock
  one once audio is confirmed working.

---

## [1.1.0] — 2026-10-29

First versioned release. The port built and installed, but audio was degraded, the torch and
vibration did nothing, and the camera crashed on open. All four are addressed.

### Fixed

**Camera no longer crashes on open.** The entire ISP pipeline was absent — `camera_isp`,
`camera_mem`, `imgsensor_isp6s`, `camera_eeprom`, `camera_dip_isp6s`, `camera_rsc_isp60`,
`camera_fdvt_isp51`, `mtk-composite`, plus autofocus (`mainaf`, `main2af`, `main3af`, `subaf`,
`sub2af`) and `sensorhub`. Without `mtk-composite` no `/dev/mtk_cam*` node exists at all, so the
HAL dereferenced a null device handle instead of failing cleanly.

**Audio no longer thin or distorted.** The MT6789 DSP chain was missing: `snd-soc-mt6789-afe`,
`snd-soc-mt6366`, `mt6789-mt6366`, `audio_ipi`, `adsp`, `snd-soc-audiodsp-common`,
`mtk-scp-audio`. PulseAudio had been falling back to a generic PCM route with no Aurisys
processing and no smartpa initialisation. The audio policy also advertised 44100 Hz on 39 profiles
while the droid card was forced to 48000, causing a CPU resample that the missing DSP would
normally have handled; the policy is now 48000 only.

**Torch works.** `flashlight`, `flashlights-mt6789-o7` and `mtk-pwm` were missing, so
`/sys/class/flashlight_core` never existed and the bridge daemon's writes silently failed. The
bridge also now probes five candidate node names and two write formats, and logs failures through
syslog instead of returning silently.

**Vibration works.** This was never a module bug: `regulator-vibrator.ko` was shipped and loaded.
`hfd-service` probes binder AIDL/HIDL, then `/sys/class/leds/vibrator`, then
`/sys/class/timed_output/vibrator`, then force-feedback, then falls back to `VibratorDummy` which
ignores everything. `usable()` calls `access()`, which failed without a udev rule, so the dummy
backend was selected. udev rules for `timed_output`, `leds/vibrator`, `leds`, `flashlight_core` and
`backlight` were added.

**Boot has a console.** `console=tty0` was absent from the kernel cmdline; UBports requires it and
without it a failed boot produces no output at all.

**Module loading is consistent.** `modules.load` named 184 entries while 207 files shipped, so 23
drivers were never loaded. It is now generated from the shipped set (385 entries, matching 385
files). `modules-load.d/tanzanite.conf` listed 174 modules of which 150 had no file, producing a
boot-time error for each; it is now generated and contains only the two that are valid.

### Added

- 178 vendor kernel modules recovered from the `vendor_dlkm` partition inside `super.img` of
  official firmware `OS2.0.214.0.VOGEUXM`, bringing the shipped set from 207 to 385
- Stock `aurisys_config.xml` (28.8 KB, replacing a 4.4 KB file that named an amplifier the device
  does not have), its 110 `audio_param` files, SiA81xx tuning data, and the lib/lib64 DSP libraries
- `scripts/check_modules.sh` — cross-checks the three module lists and verifies seven
  hardware-critical module groups
- `scripts/check_device_config.sh` — verifies cmdline requirements, sysfs paths against shipped
  drivers, audio sample rates, Aurisys payload paths and the vibrator backend
- `scripts/extract_firmware_modules.sh` — pulls modules out of an official fastboot package
- `scripts/sync_modules_load.sh`, `scripts/sync_modules_load_conf.sh` — regenerate the load lists
  from the files on disk, with `--check` modes for CI
- `scripts/publish_artifact.sh` — uploads the zip and rewrites every recorded checksum and link
  from the actual file
- `scripts/build_zip_local.sh` — assembles the recovery installer, now versioned
- GitHub Actions workflow running all consistency checks on every push
- `docs/MODULE_AUDIT.md`, `docs/VERSIONING.md`, `docs/BINARIES.md`, `docs/BUILD_NOTES.md`
- Build manifest inside the zip (`META-INF/tanzanite/build.prop`), recorded by the installer at
  `/data/ubuntu/etc/tanzanite-build.prop`

### Changed

- Artifact naming: `tanzanite-ut20.04-halium12-v1.1.0-<date>-<commit>.zip`, with `.sha256` and
  `.buildinfo` companions, and a `-dirty` suffix when built from a modified tree
- Rootfs URL switched from the dead `focal-hybris-rootfs-arm64` CI job to the official
  `ubuntu-touch-rootfs/job/ubports/focal` artifact
- `.gitattributes` marks vendor binaries and MTK audio payloads as non-text, so CRLF line endings
  in the tuning data are never normalised

### Known limitations

- **Not verified on hardware.** The four repaired features are verified structurally — modules
  present and loadable per `modules.load`, every path the audio config references exists — but
  driver binding and end-to-end function have not been observed on a device.
- **`systempart` is not set**, so the installer provisions `/data/ubuntu` rather than using
  system-as-root. Switching requires a rebuild with `systempart=` in the cmdline and
  `deviceinfo_use_overlaystore="true"`.
- **Firmware lock-in:** built against `OS2.0.214.0.VOGEUXM`. HyperOS 3.x uses a different kernel
  (6.12) and must be downgraded first.
- Xiaomi has not released kernel source for tanzanite; the kernel is `iprjkt/evernight-gki` GKI
  5.10 with AppArmor enabled.

### Verification performed

```
vendor_boot cmdline   console=tty0 bootopt=64S3,32N2,64N2   (header v4)
vendor_boot ramdisk   385 .ko files, modules.load 385 entries
device tarball        45.5 MB (was 38.5 MB; the delta is the module payload)
overlay               aurisys_config.xml 28.8 KB, 110 audio_param files,
                      9 DSP libraries (lib + lib64)
check_modules.sh      all module lists consistent, 7/7 hardware groups ok
check_device_config   8/8 checks pass
```

### Artifact

| | |
|---|---|
| File | `tanzanite-ut20.04-halium12-v1.1.0-20261029-b4e45b1.zip` |
| Size | 978,637,422 bytes (933 MiB) |
| SHA-256 | `99b429d6292f8220ed25065e1dd70dd6432447505dd04c4a8a681924cd1d9aca` |
| MD5 | `23f604a1947f9cc29f07a31cd84bb889` |
| Kernel | 5.10.269-EvernightKernel-1.1 |
| Modules | 385 |

---

## Pre-release history

Before 1.1.0 the port was unversioned. Two unversioned builds were produced during development and
are superseded:

- `tanzanite-halium.zip` (962,716,095 B, sha256 `18393dd1…c402`) — first successful build from
  scratch, before any bug fixes
- `tanzanite-halium.zip` (963,251,086 B, sha256 `e2b6dbf4…b3b4`) — rebuild with the module load
  list and udev fixes, before the missing drivers were recovered

Both are obsolete. Use 1.1.0.
