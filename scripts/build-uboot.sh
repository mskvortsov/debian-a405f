#!/bin/sh
# Build U-Boot for the Galaxy A40 and wrap it in an Android boot image,
# which is what S-Boot loads from the `boot` partition. Runs in the
# build container (see build.sh):
#
#   scripts/build-uboot.sh SRCDIR OUTDIR
set -eu

SRC=$(cd "$1" && pwd)
OUT=$(mkdir -p "$2" && cd "$2" && pwd)

cd "$SRC"
make -s CROSS_COMPILE=aarch64-linux-gnu- galaxy-a40_defconfig
make -s CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)"

# S-Boot jumps to the "kernel" at 0x10008000; there is no ramdisk
mkbootimg \
    --kernel u-boot.bin \
    --base 0 \
    --kernel_offset 0x10008000 \
    --ramdisk_offset 0 \
    --tags_offset 0x10000100 \
    --pagesize 2048 \
    --header_version 0 \
    -o "$OUT/boot.img"

echo "U-Boot: $OUT/boot.img"
