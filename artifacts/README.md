# Artifacts

Binaries are **not** stored in git. This directory holds only checksums and pointers.

## Installer zip

| Field | Value |
| --- | --- |
| File | `tanzanite-halium.zip` |
| Size | 963251086 bytes (919 MiB) |
| SHA-256 | `e2b6dbf452ba349e2285d78d9bbee00b8eca5aeb37ebf01aaa199a5f3c69b3b4` |
| MD5 | `b70026f7ab7be675b81658a01081b6e9` |
| Download | https://gofile.io/d/hXCvFAqw |

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
