#!/bin/sh
# Build the a40 Debian image: U-Boot, the kernel package, the shannon
# package and the rootfs, in the container from ./Dockerfile. The
# results go to out/.
#
#   ./build.sh
#
# Needs docker, git, and arm64 binfmt (qemu-user-static, or
# `docker run --privileged --rm tonistiigi/binfmt --install arm64`).
#
# Sources go to src/ and are reused if they are there already, so a CI
# checkout (or a local working tree) can be put in place first:
#   src/linux    KERNEL_REPO at KERNEL_REF
#   src/shannon  SHANNON_REPO at SHANNON_REF
#   src/u-boot   UBOOT_REPO at u-boot/BASE, with u-boot/patches applied
#
set -eu

cd "$(dirname "$0")"

KERNEL_REPO=${KERNEL_REPO:-https://github.com/mskvortsov/linux-a405f.git}
KERNEL_REF=${KERNEL_REF:-a405f}
SHANNON_REPO=${SHANNON_REPO:-https://github.com/mskvortsov/shannon.git}
SHANNON_REF=${SHANNON_REF:-main}
UBOOT_REPO=${UBOOT_REPO:-https://github.com/u-boot/u-boot.git}
BUILDER=${BUILDER:-a40-debian-builder}

if ! grep -qs enabled /proc/sys/fs/binfmt_misc/qemu-aarch64; then
    echo "build.sh: no arm64 binfmt; install qemu-user-static" >&2
    exit 1
fi

# A shallow fetch of one ref (branch, tag or commit) into an empty repo
fetch() {
    git init -q "$1"
    git -C "$1" fetch -q --depth 1 "$2" "$3"
    git -C "$1" checkout -q FETCH_HEAD
}

mkdir -p src
[ -d src/linux ]   || fetch src/linux "$KERNEL_REPO" "$KERNEL_REF"
[ -d src/shannon ] || fetch src/shannon "$SHANNON_REPO" "$SHANNON_REF"
if [ ! -d src/u-boot ]; then
    fetch src/u-boot "$UBOOT_REPO" "$(cat u-boot/BASE)"
    git -C src/u-boot -c user.name=build -c user.email=build@localhost \
        am -q "$PWD"/u-boot/patches/*.patch
fi

docker build -t "$BUILDER" .

# privileged: mmdebstrap mounts /proc, /sys and /dev in the chroot
docker run --rm --privileged \
    -v "$PWD:/work" -w /work \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    "$BUILDER" sh -euc '
        rm -rf out build/debs
        scripts/build-uboot.sh src/u-boot out
        scripts/build-kernel.sh src/linux build/debs
        scripts/build-shannon.sh src/shannon build/debs
        scripts/build-rootfs.sh build/debs out
        cp build/debs/*.deb out/
        zstd -q -T0 -12 --rm out/rootfs.img
        (cd out && sha256sum -- * > SHA256SUMS)
        chown -R "$HOST_UID:$HOST_GID" out build src
    '

cat out/SHA256SUMS
