# Build notes — reproducing the artifacts in this repository

Everything below was executed on an **aarch64 Ubuntu 24.04 host** (8 cores, 30 GB RAM).
Timings are from that machine.

## One command

`scripts/build-all.sh` runs the whole chain and is the recommended entry point:

```bash
./scripts/build-all.sh                     # full build
SKIP_KERNEL=1 ./scripts/build-all.sh       # reuse an existing kernel/out
SKIP_IMAGES=1 ./scripts/build-all.sh       # stop after the device tarball
```

It checks host tools up front, clones the kernel and the UBports build tools if
absent, applies `build-patches/` when needed, and verifies that each stage
produced its expected output before moving on. `WORKSPACE`, `KERNEL_SRC` and
`JOBS` are configurable; nothing outside the repository is referenced.

The stages below are what it runs, listed separately for when a single step needs
to be re-run by hand.

## Timeline

| Stage | Wall time | Notes |
| --- | --- | --- |
| `apt install` toolchain | ~2 min | clang-14, lld-14, llvm-14, libclang-rt-14-dev, dtc, img2simg, fakeroot |
| Clone `evernight-gki` (depth 1) | ~1 min | 1.4 GB, 71,084 files |
| `tanzanite_defconfig` | ~10 s | |
| `make -j8` compile | ~7 min | 4,485 objects, ~475/min |
| `LTO vmlinux.o` (ThinLTO final link) | **~15 min** | single-threaded, `ld.lld` at 99% CPU, 1.5 GB RSS |
| `vmlinux` + `Image` + `Image.gz` | ~2 min | kallsyms two-pass |
| **Kernel total** | **~29 min** | |
| `./build.sh -b workdir` | ~1 min | images + device tarball |
| `prepare-fake-ota.sh` | ~2 min | unpacks 710 MB rootfs, repacks |
| `system-image-from-ota.sh` | ~2 min | mkfs.ext4 3584 MB + sparse convert |
| `scripts/build_zip_local.sh` | ~4 min | zip -9 of ~1.1 GB payload |

## Kernel configuration

The defconfig is `arch/arm64/configs/tanzanite_defconfig` from `iprjkt/evernight-gki`.
Relevant resolved options:

```
CONFIG_SECURITY_APPARMOR=y
CONFIG_SECURITY_APPARMOR_HASH=y
CONFIG_LTO_CLANG_THIN=y
CONFIG_CFI_CLANG=y
CONFIG_CFI_CLANG_SHADOW=y
CONFIG_LOCALVERSION="-EvernightKernel-1.1"
```

Resulting release string: `5.10.269-EvernightKernel-1.1`.

`CONFIG_SECURITY_APPARMOR=y` is the one that matters for Ubuntu Touch: without it the port boots
but application confinement (`apparmor-easyprof-ubuntu_*` profiles shipped in the overlay) cannot
be enforced, and snaps/click packages fail to launch.

## Why the build tools were patched

`halium-generic-adaptation-build-tools` downloads prebuilt **x86_64** Android toolchains:

```
prebuilts/clang/host/linux-x86          -> clang-r416183b (x86_64 binaries)
prebuilts/gcc/linux-x86/aarch64/...     -> aarch64-linux-android-4.9 (x86_64 host binaries)
prebuilts/build-tools/linux-x86/bin     -> toybox, etc. (x86_64)
```

On an aarch64 host those cannot execute. The patch adds a `UBPORTS_PREBUILT_KERNEL_OBJ` escape
hatch: when set, `build.sh` copies the locally built `KERNEL_OBJ` tree into `workdir/downloads/`
and `setup_repositories.sh` skips `setup_gcc`, `setup_clang` and `setup_kernel`. The rest of the
pipeline (`mkbootimg`, `avbtool`, ramdisk merging, dtbo creation) is Python/shell and runs fine
natively.

Applied against upstream commit `dd1afd8efc5bb895efc313b61960bd6537dee24a`.

## Boot image assembly details

`deviceinfo` sets `deviceinfo_bootimg_header_version="4"`, which routes through the GKI path in
`make-bootimage.sh`:

- `boot.img` gets the kernel and an empty cmdline; the ramdisk lives in `vendor_boot.img`.
- `vendor_boot.img` receives the Halium dynparts initramfs plus `vendor-ramdisk-overlay/`
  (prebuilt MTK modules) as a `platform` ramdisk fragment, plus `tanzanite.dtb`.
- Both images are padded to 64 MiB with an AVB hash footer (`deviceinfo_bootimg_partition_size`
  and `deviceinfo_vendor_boot_partition_size` = `67108864`).

Because `deviceinfo_kernel_disable_modules="true"`, no vendor modules are compiled — they are
shipped prebuilt in `vendor-ramdisk-overlay/lib/modules/` (mkp, bootprof, mrdump, pinctrl-mt6789,
mediatek-drm, ufs-mediatek-mod, etc.).

## Pitfalls hit during this build

1. **`mkdtboimg.py` is Python 2.** The `libufdt` branch `pie-gsi` (which the build tools clone)
   fails on Python 3 with `NameError: xrange` and later `TypeError: cannot use a str to initialize
   an array with typecode 'c'`. Replacing it with the `lineage-21.0` version (Python 3 native)
   fixes dtbo creation. Verified output: magic `d7b7ab1e`, 1 entry, `dt_size 135443`.

2. **`build.sh` deletes `tmp/`,** so `out/partitions/` does not survive. Extract the images from
   `out/device_tanzanite.tar.xz` if you need them afterwards (they are byte-identical to what
   ends up in `images/`).

3. **Upstream rootfs URL is dead.** `ci.ubports.com/job/focal-hybris-rootfs-arm64/...` returns 404.
   Use `ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%252Ffocal/lastSuccessfulBuild/artifact/ubuntu-touch-android9plus-rootfs-arm64.tar.gz`.

4. **`prepare-fake-ota.sh` prints `cp: cannot stat 'partitions/*'`** — harmless. The device tarball
   has no `partitions/` payload beyond the boot images already handled, and the script continues.

5. **`losetup ... detach failed`** in `system-image-from-ota.sh` — harmless container artifact;
   the ext4 image is built via the `mke2fs -d` fallback path instead of a loop mount.

## Verification performed

```
$ file Image                      -> ARM aarch64 (magic "ARMd")
$ unpack_bootimg.py boot.img      -> header v4, kernel 13,466,550 B, ramdisk 18,017,215 B, os 12.0.0
$ unpack_bootimg.py vendor_boot.img
                                  -> VNDRBOOT v4, kernel@0x40000000, ramdisk@0x66f00000,
                                     tags/dtb@0x47c80000, page 0x1000, dtb 178,479 B,
                                     cmdline "bootopt=64S3,32N2,64N2"
$ mkdtboimg.py dump dtbo.img      -> magic d7b7ab1e, 1 entry, dt_size 135443
$ dumpe2fs -h rootfs.img          -> 917504 blocks x 4096, metadata_csum
$ od -An -tx4 system.img          -> ed26ff3a (sparse)
$ debugfs -R "cat /usr/lib/os-release" rootfs.img
                                  -> Ubuntu 20.04.6 LTS (Focal Fossa)
$ md5sum boot.img vendor_boot.img dtbo.img
                                  -> identical between out/ and images/
```

Device overlay confirmed present in `device_tanzanite_usrmerge.tar.xz`:
`70-tanzanite.rules`, `tanzanite.yaml`, ofono MTK config, usb-moded units, repowerd
`config-tanzanite.xml`, apparmor `graphics.d/apparmor-easyprof-ubuntu_android12`,
`libmtkcam_metastore.so`, `audio.primary.mediatek.so`.
