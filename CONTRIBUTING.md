# Contributing

Thanks for looking. This is a single-device Ubuntu Touch port, so most useful contributions are
bug reports with logs, not large patches.

## Before you open anything

Read [`docs/MODULE_AUDIT.md`](docs/MODULE_AUDIT.md) and [`docs/BOOTLOADER.md`](docs/BOOTLOADER.md).
They cover the two failure classes this port has actually hit: missing vendor kernel modules and
mistaking a `vbmeta` problem for a bootloader problem.

If your device does not boot, collect this first:

```bash
fastboot getvar unlocked
fastboot getvar current-slot
adb shell 'dd if=/dev/block/by-name/vbmeta_a bs=1 skip=120 count=4 2>/dev/null | xxd'
adb shell 'dd if=/dev/block/by-name/boot_a bs=64 count=1 2>/dev/null | xxd'
```

If it boots but a feature is broken:

```bash
cat /etc/tanzanite-build.prop
dmesg | tail -100
journalctl -b --no-pager | tail -200
lsmod
```

A report without at least `dmesg` and the build version usually cannot be acted on.

## Local checks

Everything that CI runs can be run locally. Do this before opening a pull request:

```bash
shellcheck -S info scripts/*.sh build.sh    # must be silent
./scripts/check_modules.sh                  # module lists must agree
./scripts/sync_modules_load.sh --check      # modules.load up to date
./scripts/sync_modules_load_conf.sh --check
./scripts/check_device_config.sh            # device config consistent
```

`bash -n` alone is not enough: it parses but does not catch unquoted expansions, ignored
parameters or masked failures.

## Commit conventions

Subject line, imperative mood, no trailing period, prefixed by area:

```
modules: ship the 178 vendor_dlkm modules that fix audio, torch and camera
udev: add permissions for LEDs, torch, haptics and backlight
audio: pin audio policy to the 48 kHz native rate of the MT6789 AFE
docs: rewrite the module audit with the actual root cause
ci: run shellcheck on every push
```

Common areas: `modules`, `audio`, `camera`, `udev`, `deviceinfo`, `flashlight`, `boot`, `scripts`,
`docs`, `ci`, `build`, `release`, `artifacts`, `repo`.

The body should explain **why**, not restate the diff. If a change fixes a symptom, name the symptom
and the mechanism. If an assumption was wrong, say which one and what disproved it — several
entries in [`CHANGELOG.md`](CHANGELOG.md) exist because that was recorded properly the first time.

Sign off your work:

```
Signed-off-by: Your Name <you@example.com>
```

`git commit -s` adds it automatically.

## Changing the module set

The module set is the most fragile part of this port. Never edit `modules.load` or
`modules-load.d/tanzanite.conf` by hand — they are generated:

```bash
./scripts/sync_modules_load.sh        # from the .ko files present
./scripts/sync_modules_load_conf.sh
```

To add modules, drop the `.ko` into `vendor-ramdisk-overlay/lib/modules/` and regenerate. To obtain
them, see [`docs/MODULE_AUDIT.md`](docs/MODULE_AUDIT.md): they live on `vendor_dlkm` inside
`super.img`, not in `vendor_boot`.

`vendor-ramdisk-overlay/lib/modules/` is ~63 MB of vendor binaries. That is intentional and
explained in [`docs/BINARIES.md`](docs/BINARIES.md). Do not "clean it up".

## Changing the audio configuration

`overlay/system/usr/share/halium-overlay/vendor/etc/aurisys_config.xml` must stay byte-identical to
the stock file from firmware `OS2.0.214.0.VOGEUXM`. It is 28.8 KB and names the libraries the
hardware actually uses. The previous 4.4 KB file named a RT5512 amplifier that this device does not
have, and pointed at libraries that exist nowhere — that is what broke audio, and it took a firmware
comparison to notice.

Line endings matter. `.gitattributes` marks the vendor tree `-text` so git never normalises the CRLF
in `sixth_param*.txt` and `audio_param*/*.xml`. Do not remove that rule.

## Release process

See [`docs/VERSIONING.md`](docs/VERSIONING.md). Short form:

```bash
# bump VERSION, commit
PORT_VERSION="$(cat VERSION)" ./scripts/build_zip_local.sh
./scripts/publish_artifact.sh dist/<name>.zip
git tag -s v<version> -F <notes> && git push --tags
gh release create v<version> --notes-file <notes> dist/<name>.zip dist/<name>.zip.sha256 dist/<name>.buildinfo
```

Tags must be signed. The GPG key must match the commit author email.

## What not to send

- Bootloader patches (fenrir, lkpatcher, `modlk`). See [`docs/BOOTLOADER.md`](docs/BOOTLOADER.md)
  for why they are not needed here and cannot be applied to this device.
- Unversioned installer zips. Builds are named and checksummed for a reason.
- "It doesn't work" without logs.
- Changes that hand-edit generated files.

## Licensing

By contributing you agree your work is licensed under Apache-2.0, matching [`LICENSE`](LICENSE).
Vendor binaries in the overlay and `vendor-ramdisk-overlay/` remain the property of their
manufacturers; see [`docs/BINARIES.md`](docs/BINARIES.md).
