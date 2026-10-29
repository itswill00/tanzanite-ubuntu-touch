#!/usr/bin/env bash
# End-to-end build of the Ubuntu Touch port for Redmi Note 14 4G (tanzanite).
#
# Runs the whole chain: kernel, boot images, rootfs images, installer zip.
# Each stage can be skipped or run on its own; see the flags below.
#
# Upstream tooling downloads x86_64 prebuilt Android toolchains, which cannot run
# on an aarch64 host. On such hosts the kernel is built natively and injected via
# UBPORTS_PREBUILT_KERNEL_OBJ, which requires build-patches/ to be applied to the
# adaptation build tools. On x86_64 the patch is unnecessary but harmless.
#
# Usage:
#   ./scripts/build-all.sh                 # full build
#   SKIP_KERNEL=1 ./scripts/build-all.sh   # reuse an existing kernel/out
#   SKIP_IMAGES=1 ./scripts/build-all.sh   # stop after the device tarball
#
# Environment:
#   WORKSPACE      build root              (default: <repo>/build-workspace)
#   KERNEL_SRC     kernel source checkout  (default: $WORKSPACE/kernel)
#   SKIP_KERNEL    set to 1 to reuse $KERNEL_SRC/out
#   SKIP_IMAGES    set to 1 to stop before the rootfs images
#   SKIP_ZIP       set to 1 to skip the installer zip
#   JOBS           parallel build jobs     (default: nproc)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${WORKSPACE:-$REPO/build-workspace}"
KERNEL_SRC="${KERNEL_SRC:-$WORKSPACE/kernel}"
JOBS="${JOBS:-$(nproc)}"

KERNEL_REPO="https://github.com/iprjkt/evernight-gki"
KERNEL_BRANCH="main"
DEFCONFIG="tanzanite_defconfig"
KERNEL_ARCH="arm64"
KERNEL_LLVM_ARGS=(ARCH="$KERNEL_ARCH" LLVM=1 LLVM_IAS=1)

ROOTFS_URL="${ROOTFS_URL:-https://ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%252Ffocal/lastSuccessfulBuild/artifact/ubuntu-touch-android9plus-rootfs-arm64.tar.gz}"
OTA_CHANNEL="${OTA_CHANNEL:-20.04/arm64/android9plus/stable}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[31m[-] %s\033[0m\n' "$*" >&2; exit 1; }

mkdir -p "$WORKSPACE"

# ---------------------------------------------------------------- toolchain ---
step "Checking host tools"
missing=()
for t in git make clang lld ld.lld python3 cpio xz lz4 zip unzip curl wget \
         img2simg mkfs.ext4 fakeroot; do
    command -v "$t" >/dev/null || missing+=("$t")
done
if [ ${#missing[@]} -gt 0 ]; then
    die "missing tools: ${missing[*]}
Install: apt install clang lld llvm libclang-rt-14-dev libssl-dev libelf-dev bc \\
         bison flex cpio kmod rsync device-tree-compiler e2fsprogs xxd \\
         android-sdk-libsparse-utils zlib1g-dev img2simg fakeroot zip unzip"
fi
echo "    ok"

# ------------------------------------------------------------------- kernel ---
if [ "${SKIP_KERNEL:-0}" = "1" ]; then
    step "Skipping kernel build (SKIP_KERNEL=1)"
    [ -d "$KERNEL_SRC/out" ] || die "SKIP_KERNEL=1 but $KERNEL_SRC/out does not exist"
else
    if [ ! -d "$KERNEL_SRC" ]; then
        step "Cloning kernel ($KERNEL_REPO)"
        git clone --depth=1 --single-branch --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_SRC"
    fi

    step "Configuring kernel ($DEFCONFIG)"
    make -C "$KERNEL_SRC" O=out "${KERNEL_LLVM_ARGS[@]}" "$DEFCONFIG"

    step "Building kernel (-j$JOBS; ThinLTO link is single-threaded and slow)"
    make -C "$KERNEL_SRC" O=out "${KERNEL_LLVM_ARGS[@]}" -j"$JOBS"

    for f in Image Image.gz; do
        [ -s "$KERNEL_SRC/out/arch/$KERNEL_ARCH/boot/$f" ] || die "kernel build produced no $f"
    done
    echo "    Image.gz: $(stat -c%s "$KERNEL_SRC/out/arch/$KERNEL_ARCH/boot/Image.gz") bytes"
fi

# --------------------------------------------------------- build tools setup ---
if [ ! -d "$REPO/build" ]; then
    step "Fetching UBports adaptation build tools"
    git clone --depth=1 \
        https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools \
        "$REPO/build"
    if [ -f "$REPO/build-patches/halium-generic-adaptation-build-tools.patch" ]; then
        echo "    applying build-patches/ (needed for non-x86_64 hosts)"
        git -C "$REPO/build" apply \
            "$REPO/build-patches/halium-generic-adaptation-build-tools.patch"
    fi
fi

# ------------------------------------------------------------ boot images ----
step "Assembling boot images and device tarball"
export UBPORTS_PREBUILT_KERNEL_OBJ="$KERNEL_SRC/out"
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
