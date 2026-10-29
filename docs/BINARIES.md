# Binaries kept in this repository

Some binaries are committed because they are either prebuilt by the device vendor, or because
rebuilding them requires an aarch64 cross toolchain that the build host may not have. They are
not source code; they are inputs.

## `vendor-ramdisk-overlay/lib/modules/` (~31 MB)

MediaTek vendor kernel modules taken from the stock `vendor_boot` of the device firmware
(`OS2.0.214.0.VOGEUXM`). They are shipped inside `vendor_boot.img` as a `platform` ramdisk
fragment, because `deviceinfo` sets:

```
deviceinfo_kernel_disable_modules="true"
```

so the Halium kernel build does not compile modules. This is the standard approach for GKI
devices whose vendor modules are built against a specific GKI KMI.

**They are not built here and cannot be rebuilt from this repository.** They belong to the
vendor (MediaTek / Xiaomi) and are redistributed as part of a device port, in the same way every
Android custom ROM ships vendor blobs.

Examples: `mkp.ko`, `bootprof.ko`, `mrdump.ko`, `mtk_disp_notify.ko`, `pinctrl-mt6789.ko`,
`mediatek-drm.ko`, `ufs-mediatek-mod.ko`.

## `overlay/system/usr/share/halium-overlay/vendor/lib64/`

Vendor Android libraries needed by the Halium container through libhybris:

- `libmtkcam_metastore.so` — camera metadata service
- `hw/audio.primary.mediatek.so` — MediaTek primary audio HAL

Same rationale: vendor binaries, not buildable from source here.

## `overlay/system/usr/lib/aarch64-linux-gnu/mir/`

libhybris platform plugins for Mir:

- `client-platform/android2.so.5`
- `server-platform/graphics-android2.so.15`

Prebuilt against the device's Android 12 gralloc/EGL. Rebuilding them would require the full
libhybris tree configured for MT6789.

## `overlay/system/usr/bin/umtprd`, `usr/sbin/usb_moded`

aarch64 ELF binaries for MTP and USB mode handling. Upstream sources:
[umtprd](https://github.com/viveris/umtprd), [usb-moded](https://github.com/mer-hybris/usb-moded).

## `overlay/system/usr/local/bin/tanzanite-flashlight-bridge`, `usr/local/lib/libupower_filter_bms.so`

Small helpers written for this device (C sources are committed alongside them in
`overlay/system/usr/local/bin/*.c`):

- `tanzanite-flashlight-bridge` — exposes the MTK torch sysfs node as a stable path for
  `ayatana-indicator-power`.
- `libupower_filter_bms.so` — `LD_PRELOAD` shim that filters bogus battery devices out of UPower's
  GUdev query so the fuel gauge reports correctly.

Rebuild on an aarch64 host:

```bash
gcc -shared -fPIC -O2 overlay/system/usr/local/bin/upower_filter_bms.c \
    -o overlay/system/usr/local/lib/libupower_filter_bms.so -ldl
```

## `flashable_zips/common/tools/` (~5 MB)

Recovery-side utilities bundled into the installer zip:

| Binary | Purpose |
| --- | --- |
| `busybox` | aarch64 static busybox, shell utilities inside recovery |
| `avbctl` | Android Verified Boot control |
| `dump.erofs`, `mkfs.erofs`, `fsck.erofs`, `extract.erofs` | unpack/repack the EROFS `vendor` partition to patch its fstab |
| `lptools` | logical partition helpers |

## `flashable_zips/vbmeta/*.img` (24 MB)

Pre-disabled AVB metadata images (flags set to `0x03` = verification + verity disabled) for
`vbmeta`, `vbmeta_system`, `vbmeta_vendor`. The installer writes these over the on-device
partitions so the bootloader accepts the unsigned Halium boot images.

Regenerate with `avbtool` if the stock firmware changes.

## `ramdisk-overlay/ramdisk-recovery.img` (11 MB)

Recovery ramdisk used when building a bootable UBports recovery. Not required for the standard
installer path.
