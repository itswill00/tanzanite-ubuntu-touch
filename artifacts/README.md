# Artifacts

Binaries are **not** stored in git. This directory holds only checksums and pointers.

## Installer zip

| Field | Value |
| --- | --- |
| File | `tanzanite-ut24.04-halium12-v1.2.0-20261112-8930898.zip` |
| Size | 1179273476 bytes (1125 MiB) |
| SHA-256 | `b906dd53a3e0e143e702df78d72489288cc2c07e3ce5756169d15324836a3b1c` |
| MD5 | `0b6ea83b9abbccdecc0320547f84ccf5` |
| Download | https://github.com/itswill00/tanzanite-ubuntu-touch/releases/tag/v1.2.0 |

The v1.1.1 and v1.1.0 builds and their checksums remain recorded under their own
[release tags](https://github.com/itswill00/tanzanite-ubuntu-touch/releases).

Rebuild it with `./scripts/build_zip_local.sh` (see `docs/BUILD_NOTES.md`).

## Zip contents

| Path | Size |
| --- | --- |
| `ubuntu-touch-hybris-rootfs-arm64.tar.gz` | UT Noble arm64 rootfs |
| `halium_halium_arm64.tar.xz` | Halium 12 GSI (contains android-rootfs.img) |
| `partitions/boot.img` | Halium boot image, header v4 |
| `partitions/vendor_boot.img` | Halium vendor_boot, header v4, carries the 207 vendor modules + dtb |
| `partitions/dtbo.img` | Device tree overlay |
| `device_tanzanite.tar.xz` | Device tarball |
| `device_tanzanite_system.tar.gz` | Rootfs overlay (udev, ofono, audio, libhybris) |
| `vbmeta/*.img` | Pre-disabled AVB metadata |
| `tools/*` | busybox, avbctl, erofs tools, lptools |
| `META-INF/com/google/android/update-binary` | Installer logic |

## Prebuilt kernel and modules

`scripts/build-all.sh` uses a prebuilt kernel object by default, and fetches the vendor module set
when the tree has no `.ko`. Both are published as release assets, not stored in git:

| Field | Value |
| --- | --- |
| File | `kernel-5.10.272-tanzanite-prebuilt.tar.gz` |
| SHA-256 | `3b72126b5818d5636ca15d7ab142b91519486ce5675e4ea642adeab3fab86d66` |
| File | `vendor-modules-5.10.236-tanzanite.tar.gz` (207 `.ko`) |
| SHA-256 | `bcf8cd7a77b4984af0e783cf4f911fe34e43eddcb8c06a6736ed4aa2677a24f2` |
| Download | https://github.com/itswill00/tanzanite-ubuntu-touch/releases/tag/kernel-5.10.272-tanzanite |

## Images produced alongside (not uploaded)

`rootfs.img` (3.7 GB) and `system.img` (2.7 GB) exceed per-asset hosting limits and are only
needed for the `fastboot flash system` path, which this port does not use. Rebuild with
`prepare-fake-ota.sh` + `system-image-from-ota.sh`.
