#!/usr/bin/env bash
# End-to-end build of the Ubuntu Touch port for Redmi Note 14 4G (tanzanite).
#
# Runs the whole chain: kernel, boot images, rootfs images, installer zip.
# Each stage can be skipped or run on its own; see the flags below.
#
# By default the kernel is NOT compiled: a prebuilt kernel object is downloaded
# (a release asset) and injected via UBPORTS_PREBUILT_KERNEL_OBJ, which the
# patched adaptation tools accept. Set BUILD_KERNEL=1 to build the kernel from
# the Android Common Kernel source instead, or KERNEL_OBJ_DIR to reuse a local
# kernel out tree.
#
# Building the kernel on a non-aarch64 host needs a cross toolchain
# (aarch64-linux-gnu-); CROSS_COMPILE is set automatically in that case.
#
# Usage:
#   ./scripts/build-all.sh                            # full build, prebuilt kernel
#   BUILD_KERNEL=1 ./scripts/build-all.sh             # also compile the kernel
#   KERNEL_OBJ_DIR=/path/to/out ./scripts/build-all.sh  # reuse a local kernel out
#   SKIP_IMAGES=1 ./scripts/build-all.sh              # stop after the device tarball
#
# Environment:
#   WORKSPACE              build root              (default: <repo>/build-workspace)
#   KERNEL_SRC             kernel source checkout  (default: $WORKSPACE/kernel)
#   BUILD_KERNEL           set to 1 to compile the kernel from source
#   KERNEL_OBJ_DIR         use this kernel out tree, no download/build
#   PREBUILT_KERNEL_URL    prebuilt kernel tarball (default: release asset)
#   PREBUILT_KERNEL_SHA256 expected sha256 of that tarball
#   PREBUILT_MODULES_URL   vendor module tarball, used when no *.ko are present
#   PREBUILT_MODULES_SHA256 expected sha256 of that tarball
#   SKIP_IMAGES            set to 1 to stop before the rootfs images
#   SKIP_ZIP               set to 1 to skip the installer zip
#   JOBS                   parallel build jobs     (default: nproc)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${WORKSPACE:-$REPO/build-workspace}"
KERNEL_SRC="${KERNEL_SRC:-$WORKSPACE/kernel}"
KERNEL_PREBUILT="${KERNEL_PREBUILT:-$WORKSPACE/kernel-prebuilt}"
JOBS="${JOBS:-$(nproc)}"

KERNEL_REPO="https://android.googlesource.com/kernel/common"
KERNEL_BRANCH="android12-5.10-lts"
DEFCONFIG="tanzanite_defconfig"
KERNEL_ARCH="arm64"
KERNEL_LLVM_ARGS=(ARCH="$KERNEL_ARCH" LLVM=1 LLVM_IAS=1)

# Prebuilt kernel published as a release asset; override to pin another build.
PREBUILT_KERNEL_URL="${PREBUILT_KERNEL_URL:-https://github.com/itswill00/tanzanite-ubuntu-touch/releases/download/kernel-5.10.272-tanzanite/kernel-5.10.272-tanzanite-prebuilt.tar.gz}"
PREBUILT_KERNEL_SHA256="${PREBUILT_KERNEL_SHA256:-3b72126b5818d5636ca15d7ab142b91519486ce5675e4ea642adeab3fab86d66}"

# MediaTek vendor modules (gitignored *.ko), fetched only when absent.
PREBUILT_MODULES_URL="${PREBUILT_MODULES_URL:-https://github.com/itswill00/tanzanite-ubuntu-touch/releases/download/kernel-5.10.272-tanzanite/vendor-modules-5.10.236-tanzanite.tar.gz}"
PREBUILT_MODULES_SHA256="${PREBUILT_MODULES_SHA256:-bcf8cd7a77b4984af0e783cf4f911fe34e43eddcb8c06a6736ed4aa2677a24f2}"

ROOTFS_URL="${ROOTFS_URL:-https://ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%252F24.04-2.x/lastStableBuild/artifact/ubuntu-touch-android9plus-rootfs-arm64.tar.gz}"
OTA_CHANNEL="${OTA_CHANNEL:-24.04-2.x/arm64/android9plus/stable}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[31m[-] %s\033[0m\n' "$*" >&2; exit 1; }

mkdir -p "$WORKSPACE"

# ---------------------------------------------------------------- toolchain ---
step "Checking host tools"
missing=()
for t in git make python3 cpio xz lz4 zip unzip curl wget \
         img2simg mkfs.ext4 fakeroot; do
    command -v "$t" >/dev/null || missing+=("$t")
done
if [ "${BUILD_KERNEL:-0}" = "1" ]; then
    for t in clang lld ld.lld; do
        command -v "$t" >/dev/null || missing+=("$t")
    done
fi
if [ ${#missing[@]} -gt 0 ]; then
    die "missing tools: ${missing[*]}
Install: apt install clang lld llvm libclang-rt-14-dev libssl-dev libelf-dev bc \\
         bison flex cpio kmod rsync device-tree-compiler e2fsprogs xxd \\
         android-sdk-libsparse-utils zlib1g-dev img2simg fakeroot zip unzip lz4"
fi
echo "    ok"

# ------------------------------------------------------------------- kernel ---
KERNEL_OBJ=""
if [ -n "${KERNEL_OBJ_DIR:-}" ]; then
    step "Using local kernel object ($KERNEL_OBJ_DIR)"
    [ -s "$KERNEL_OBJ_DIR/arch/$KERNEL_ARCH/boot/Image.gz" ] \
        || die "no Image.gz under $KERNEL_OBJ_DIR"
    KERNEL_OBJ="$KERNEL_OBJ_DIR"
elif [ "${BUILD_KERNEL:-0}" = "1" ]; then
    # Cross-compile when the host is not aarch64. CROSS_COMPILE also gives clang
    # the right --target; without it clang emits host objects and the arm64 asm
    # fails with "unknown register name 'x1'".
    if [ "$(uname -m)" != "aarch64" ]; then
        export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
    fi

    if [ ! -d "$KERNEL_SRC" ]; then
        step "Cloning kernel ($KERNEL_REPO)"
        git clone --depth=1 --single-branch --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_SRC"
    fi

    step "Applying device kernel overlay (tanzanite)"
    "$REPO/scripts/apply_kernel_overlay.sh" "$KERNEL_SRC"

    step "Configuring kernel ($DEFCONFIG)"
    make -C "$KERNEL_SRC" O=out "${KERNEL_LLVM_ARGS[@]}" "$DEFCONFIG"

    step "Building kernel (-j$JOBS; ThinLTO link is single-threaded and slow)"
    make -C "$KERNEL_SRC" O=out "${KERNEL_LLVM_ARGS[@]}" -j"$JOBS"
    make -C "$KERNEL_SRC" O=out "${KERNEL_LLVM_ARGS[@]}" dtbs

    for f in Image Image.gz; do
        [ -s "$KERNEL_SRC/out/arch/$KERNEL_ARCH/boot/$f" ] || die "kernel build produced no $f"
    done
    echo "    Image.gz: $(stat -c%s "$KERNEL_SRC/out/arch/$KERNEL_ARCH/boot/Image.gz") bytes"
    KERNEL_OBJ="$KERNEL_SRC/out"
else
    step "Fetching prebuilt kernel ($(basename "$PREBUILT_KERNEL_URL"))"
    tarball="$WORKSPACE/$(basename "$PREBUILT_KERNEL_URL")"
    [ -s "$tarball" ] || wget -q -O "$tarball" "$PREBUILT_KERNEL_URL"
    echo "$PREBUILT_KERNEL_SHA256  $tarball" | sha256sum -c - \
        || die "prebuilt kernel checksum mismatch"
    rm -rf "$KERNEL_PREBUILT"
    mkdir -p "$KERNEL_PREBUILT"
    tar -C "$KERNEL_PREBUILT" -xzf "$tarball"
    [ -s "$KERNEL_PREBUILT/arch/$KERNEL_ARCH/boot/Image.gz" ] \
        || die "prebuilt kernel is missing arch/$KERNEL_ARCH/boot/Image.gz"
    KERNEL_OBJ="$KERNEL_PREBUILT"
fi

# ------------------------------------------------------------ vendor modules ---
# The MediaTek .ko are gitignored (*.ko) and are not in a clean checkout. Fetch
# the published set once so vendor_boot is not shipped module-less.
MODDIR="$REPO/vendor-ramdisk-overlay/lib/modules"
if ! compgen -G "$MODDIR/*.ko" >/dev/null; then
    step "Fetching vendor kernel modules"
    mt="$WORKSPACE/$(basename "$PREBUILT_MODULES_URL")"
    [ -s "$mt" ] || wget -q -O "$mt" "$PREBUILT_MODULES_URL"
    echo "$PREBUILT_MODULES_SHA256  $mt" | sha256sum -c - \
        || die "vendor modules checksum mismatch"
    tar -C "$MODDIR" -xzf "$mt"
    echo "    $(compgen -G "$MODDIR/*.ko" | wc -l) modules"
fi

# --------------------------------------------------------- build tools setup ---
if [ ! -d "$REPO/build" ]; then
    step "Fetching UBports adaptation build tools"
    git clone --depth=1 \
        https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools \
        "$REPO/build"
    if [ -f "$REPO/build-patches/halium-generic-adaptation-build-tools.patch" ]; then
        echo "    applying build-patches/"
        git -C "$REPO/build" apply \
            "$REPO/build-patches/halium-generic-adaptation-build-tools.patch"
    fi
fi

# ------------------------------------------------------------ boot images ----
step "Assembling boot images and device tarball"
export UBPORTS_PREBUILT_KERNEL_OBJ="$KERNEL_OBJ"
( cd "$REPO" && ./build.sh -b "$WORKSPACE/workdir" )

[ -s "$REPO/out/device_tanzanite_usrmerge.tar.xz" ] \
    || die "device tarball missing at out/device_tanzanite_usrmerge.tar.xz"

if [ "${SKIP_IMAGES:-0}" = "1" ]; then
    step "Skipping rootfs images (SKIP_IMAGES=1)"
else
    # ------------------------------------------------------- rootfs images ---
    step "Downloading rootfs and Halium GSI"
    mkdir -p "$REPO/ota"
    rootfs_name="$(basename "$ROOTFS_URL")"
    [ -s "$REPO/ota/$rootfs_name" ] || wget -q -P "$REPO/ota" "$ROOTFS_URL"
    gsi_url="https://ci.ubports.com/job/UBportsCommunityPortsJenkinsCI/job/ubports%252Fporting%252Fcommunity-ports%252Fjenkins-ci%252Fgeneric_arm64/job/halium-12.0/lastSuccessfulBuild/artifact/halium_halium_arm64.tar.xz"
    [ -s "$REPO/ota/halium_halium_arm64.tar.xz" ] || wget -q -P "$REPO/ota" "$gsi_url"

    step "Building flashable rootfs images"
    export ROOTFS_URL OTA_CHANNEL
    ( cd "$REPO" \
      && ./build/prepare-fake-ota.sh out/device_tanzanite_usrmerge.tar.xz ota \
      && ./build/system-image-from-ota.sh ota/ubuntu_command images )
fi

# -------------------------------------------------------------------- zip ----
if [ "${SKIP_ZIP:-0}" = "1" ]; then
    step "Skipping installer zip (SKIP_ZIP=1)"
else
    step "Building installer zip"
    ( cd "$REPO" \
      && PORT_VERSION="$(cat VERSION)" \
         PART_DIR="$WORKSPACE/workdir/tmp/partitions" \
         ./scripts/build_zip_local.sh )
fi

step "Done"
echo "    workspace : $WORKSPACE"
if [ -d "$REPO/dist" ]; then
    find "$REPO/dist" -maxdepth 1 -name '*.zip' -printf '    %p (%s bytes)\n' 2>/dev/null || true
fi
