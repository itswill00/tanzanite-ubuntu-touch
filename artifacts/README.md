# Artifacts

Binaries are **not** stored in git. This directory holds only checksums and pointers.

## Installer zip

| Field | Value |
| --- | --- |
| File | `tanzanite-halium.zip` |
| Size | 962,716,095 bytes (918 MiB) |
| SHA-256 | `18393dd19e5be2ae61982b87a2aae50ef2c3f4b5cd3c583ba88afa520bb9c402` |
| Download | https://gofile.io/d/h2oELXdq |

Rebuild it with `./scripts/build_zip_local.sh` (see `docs/BUILD_NOTES.md`).

## Zip contents

| Path | Size |
| --- | --- |
| `ubuntu-touch-hybris-rootfs-arm64.tar.gz` | 743,455,763 B |
| `halium_halium_arm64.tar.xz` | 147,425,392 B |
| `partitions/boot.img` | 67,108,864 B |
| `partitions/vendor_boot.img` | 67,108,864 B |
| `partitions/dtbo.img` | 135,507 B |
| `device_tanzanite.tar.xz` | 38,280,192 B |
| `device_tanzanite_system.tar.gz` | 1,663,845 B |
| `vbmeta/vbmeta.img`, `vbmeta_system.img`, `vbmeta_vendor.img` | 8,388,608 B each |
| `tools/*` | busybox, avbctl, erofs tools, lptools |
| `META-INF/com/google/android/update-binary` | installer logic |

## Images produced alongside (not uploaded)

`rootfs.img` (3.7 GB) and `system.img` (2.7 GB) exceed per-asset hosting limits and are only
needed for the `fastboot flash system` path, which this port does not use. Rebuild with
`prepare-fake-ota.sh` + `system-image-from-ota.sh`.
