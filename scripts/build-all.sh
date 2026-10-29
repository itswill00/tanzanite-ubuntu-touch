#!/bin/bash
# Reproducible build of the Ubuntu Touch port for Redmi Note 14 4G (tanzanite)
# on a native aarch64 host.
#
# Upstream tooling expects x86_64 prebuilt Android toolchains, so the kernel is
# built natively here and injected into the UBports image assembly via
# UBPORTS_PREBUILT_KERNEL_OBJ (small patch to build/build.sh).
set -euo pipefail

ROOT=/root/ut-build
export PATH="$ROOT/shims:/usr/lib/llvm-14/bin:$PATH"

# 1. Kernel (Halium-compatible: AppArmor + GKI 5.10, ThinLTO/CFI enabled)
if [ "${SKIP_KERNEL:-0}" != "1" ]; then
    cd "$ROOT/kernel"
    make O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 tanzanite_defconfig
    make O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 -j"$(nproc)"
fi

# 2. Device tarball + boot/vendor_boot/dtbo images
export UBPORTS_PREBUILT_KERNEL_OBJ="$ROOT/kernel/out"
cd "$ROOT/halium-device"
./build.sh -b workdir

# 3. Rootfs + Halium 12 GSI -> flashable images
export ROOTFS_URL="https://ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%252Ffocal/lastSuccessfulBuild/artifact/ubuntu-touch-android9plus-rootfs-arm64.tar.gz"
export OTA_CHANNEL="20.04/arm64/android9plus/stable"
./build/prepare-fake-ota.sh out/device_tanzanite_usrmerge.tar.xz ota
./build/system-image-from-ota.sh ota/ubuntu_command images
