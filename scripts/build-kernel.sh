#!/bin/sh
# Build the a405f kernel as a Debian linux-image package. Runs in the
# build container (see build.sh):
#
#   scripts/build-kernel.sh SRCDIR OUTDIR
#
# The config is the one the a40 runs: defconfig plus the exynos7870 and
# exynos7885 fragments from the kernel tree, without the git suffix, so
# the packages are linux-image-7.3.0-exynos7885_20261021_arm64.deb and
# linux-headers-...: the kernel release, and the build date as the
# version (KDEB_PKGVERSION overrides it).
set -eu

SRC=$(cd "$1" && pwd)
OUT=$(mkdir -p "$2" && cd "$2" && pwd)

# Keep the source tree clean, so a checkout can be reused
BUILD=${KBUILD_OUTPUT:-$SRC/../../build/linux}
mkdir -p "$BUILD"
BUILD=$(cd "$BUILD" && pwd)

export KDEB_PKGVERSION=${KDEB_PKGVERSION:-$(date -u +%Y%m%d)}

# LOCALVERSION set, even empty: without it and LOCALVERSION_AUTO, a tree
# that is not at a tag gets a "+" appended to the release
MAKE="make -C $SRC O=$BUILD ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION="
$MAKE defconfig exynos7870.config exynos7885.config
"$SRC"/scripts/config --file "$BUILD"/.config --disable LOCALVERSION_AUTO
# olddefconfig with the cross compiler: some symbols depend on what the
# aarch64 toolchain supports
$MAKE olddefconfig

# No debug-symbols package
$MAKE -j"$(nproc)" \
    DEB_BUILD_PROFILES="pkg.linux-upstream.nokerneldbg" \
    bindeb-pkg

# bindeb-pkg leaves the packages next to the output directory
mv "$BUILD"/../linux-image-*.deb "$BUILD"/../linux-headers-*.deb "$OUT"/
rm -f "$BUILD"/../linux-libc-dev_*.deb "$BUILD"/../linux-upstream_*
ls "$OUT"/linux-image-*.deb "$OUT"/linux-headers-*.deb
