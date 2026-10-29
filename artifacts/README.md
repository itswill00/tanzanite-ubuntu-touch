# Artifacts

Binaries are **not** stored in git. This directory holds only checksums and pointers.

## Installer zip

| Field | Value |
| --- | --- |
| File | `tanzanite-ut20.04-halium12-v1.1.0-20261029-b4e45b1.zip` |
| Size | 978637422 bytes (933 MiB) |
| SHA-256 | `99b429d6292f8220ed25065e1dd70dd6432447505dd04c4a8a681924cd1d9aca` |
| MD5 | `23f604a1947f9cc29f07a31cd84bb889` |
| Download | https://gofile.io/d/xkyY3FRJ |

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
