#!/bin/sh
# Configure the rootfs. build-rootfs.sh runs this inside the arm64 chroot,
# after the overlay and the local packages have been copied in.
#
# Environment: ROOT_UUID, the root filesystem's UUID.
set -eu

export DEBIAN_FRONTEND=noninteractive

echo a405f > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1	a405f localhost.localdomain localhost
::1		localhost localhost.localdomain ip6-localhost ip6-loopback
EOF

cat > /etc/fstab <<EOF
UUID=$ROOT_UUID / btrfs compress=zstd:1,noatime,ssd 0 0
EOF

# The kernel, then shannon. Installing the kernel runs update-initramfs
# and the a40-boot hook, which puts vmlinuz, initramfs and the dtb where
# U-Boot loads them.
apt-get install -y -q /tmp/a40/debs/linux-image-*.deb
apt-get install -y -q /tmp/a40/debs/shannon_*.deb
test -s /boot/vmlinuz
test -s /boot/initramfs
test -s /boot/dtbs/exynos/exynos7885-a40.dtb

mkimage -C none -A arm64 -T script -d /boot/boot.cmd /boot/boot.scr

systemctl enable usb0-gadget.service a40-firmware.service \
    a40-firstboot.service shannond.service ssh.service

# root is the only account, with an empty password, also over SSH
# (sshd_config.d/a40-root.conf)
passwd -d root

# The SSH host keys are made on the first boot (sshd-keygen.service).
# So is the machine id: mmdebstrap empties /etc/machine-id, which also
# makes ConditionFirstBoot true.
rm -f /etc/ssh/ssh_host_*

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/a40
