# Artifacts

Binaries are **not** stored in git. This directory holds only checksums and pointers.

## Installer zip

| Field | Value |
| --- | --- |
| File | `tanzanite-ut20.04-halium12-v1.1.1-20261030-a8d594e.zip` |
| Size | 971331131 bytes (927 MiB) |
| SHA-256 | `b4804db36e71b6918f5b4cc457aba45f90c07acba8c557376c28c7b4d1a68374` |
| MD5 | `68f0d83e8d3295db783e4d79e7f8a318` |
| Download | https://github.com/itswill00/tanzanite-ubuntu-touch/releases/tag/v1.1.1 |

The v1.1.0 build and its checksums remain recorded under the
[v1.1.0 release](https://github.com/itswill00/tanzanite-ubuntu-touch/releases/tag/v1.1.0).

Rebuild it with `./scripts/build_zip_local.sh` (see `docs/BUILD_NOTES.md`).

## Zip contents

| Path | Size |
| --- | --- |
| `ubuntu-touch-hybris-rootfs-arm64.tar.gz` | UT Focal arm64 rootfs |
| `halium_halium_arm64.tar.xz` | Halium 12 GSI (contains android-rootfs.img) |
| `partitions/boot.img` | Halium boot image, header v4 |
| `partitions/vendor_boot.img` | Halium vendor_boot, header v4, carries ramdisk + dtb |
| `partitions/dtbo.img` | Device tree overlay |
| `device_tanzanite.tar.xz` | Device tarball |
| `device_tanzanite_system.tar.gz` | Rootfs overlay (udev, ofono, audio, libhybris) |
| `vbmeta/*.img` | Pre-disabled AVB metadata |
| `tools/*` | busybox, avbctl, erofs tools, lptools |
| `META-INF/com/google/android/update-binary` | Installer logic |

## Images produced alongside (not uploaded)

`rootfs.img` (3.7 GB) and `system.img` (2.7 GB) exceed per-asset hosting limits and are only
needed for the `fastboot flash system` path, which this port does not use. Rebuild with
`prepare-fake-ota.sh` + `system-image-from-ota.sh`.
