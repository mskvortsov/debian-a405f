#!/bin/sh
# Build the Debian 13 root filesystem image for the a40's userdata
# partition. Runs in the build container (see build.sh), which must be
# privileged, with arm64 binfmt (qemu-user) registered on the host:
#
#   scripts/build-rootfs.sh DEBSDIR OUTDIR
#
# DEBSDIR holds the linux-image and shannon packages.
set -eu

TOP=$(cd "$(dirname "$0")/.." && pwd)
DEBS=$(cd "$1" && pwd)
OUT=$(mkdir -p "$2" && cd "$2" && pwd)

MIRROR=http://deb.debian.org/debian

ls "$DEBS"/linux-image-*.deb "$DEBS"/shannon_*.deb >/dev/null

PACKAGES="
    systemd-sysv udev dbus kmod initramfs-tools zstd
    btrfs-progs e2fsprogs u-boot-tools
    ifupdown dhcpcd-base iproute2 iputils-ping netbase
    iw wpasupplicant wireless-regdb
    openssh-server sudo ca-certificates curl
    systemd-timesyncd cron logrotate tzdata locales
    less nano vim-tiny procps psmisc file rsync xz-utils
"

ROOT=$(mktemp -d /tmp/a40-rootfs.XXXXXX)
STAGE=$(mktemp -d /tmp/a40-stage.XXXXXX)
trap 'rm -rf "$ROOT" "$STAGE"' EXIT

export ROOT_UUID=$(uuidgen)

# The overlay as root:root, without group or other write: the checkout's
# owner is a uid that the image's own user may get, and tar keeps owners
mkdir -p "$STAGE/overlay"
cp -r "$TOP/rootfs/overlay/." "$STAGE/overlay/"
chown -R root:root "$STAGE/overlay"
chmod -R go-w "$STAGE/overlay"

mkdir -p "$STAGE/chroot/debs"
cp "$DEBS"/linux-image-*.deb "$DEBS"/shannon_*.deb "$STAGE/chroot/debs/"
cp "$TOP/rootfs/setup.sh" "$STAGE/chroot/"

# The overlay goes in before the packages, so the kernel's postinst finds
# the a40-boot hook. The cleanup would empty /etc/machine-id after
# setup.sh has written "uninitialized" to it.
mmdebstrap \
    --mode=root \
    --skip=cleanup/reproducible/machine-id \
    --arch=arm64 \
    --variant=minbase \
    --include="$(echo $PACKAGES | tr ' ' ,)" \
    --essential-hook="sync-in '$STAGE/overlay' /" \
    --customize-hook='mkdir "$1/tmp/a40"' \
    --customize-hook="sync-in '$STAGE/chroot' /tmp/a40" \
    --customize-hook='chroot "$1" sh /tmp/a40/setup.sh' \
    trixie "$ROOT" \
    "deb $MIRROR trixie main" \
    "deb $MIRROR trixie-updates main" \
    "deb $MIRROR-security trixie-security main"

IMG="$OUT/rootfs.img"
rm -f "$IMG"
# The filesystem grows to the whole partition on the first boot
truncate -s 1G "$IMG"
mkfs.btrfs -q -L a40-root -U "$ROOT_UUID" --rootdir "$ROOT" "$IMG"
echo "rootfs: $IMG ($(du -sh "$ROOT" | cut -f1) of files, uuid $ROOT_UUID)"
