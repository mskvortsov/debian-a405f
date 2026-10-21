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

# root is the only account, with the password "root", also over SSH
# (sshd_config.d/a40-root.conf)
echo root:root | chpasswd

# en_US.UTF-8 by default. ssh clients also pass their own LANG and LC_*
# (sshd's AcceptEnv); one that is not generated makes perl, and so apt,
# warn on every run.
echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# The SSH host keys are made on the first boot (sshd-keygen.service), and
# so is the machine id. mmdebstrap leaves /etc/machine-id empty, which is
# not a first boot (machine-id(5)): "uninitialized" is, and makes
# ConditionFirstBoot true.
rm -f /etc/ssh/ssh_host_*
echo uninitialized > /etc/machine-id

# On the first boot systemd also enables the units its presets name,
# which would add systemd-networkd and its wait-online beside ifupdown.
# Everything the image needs is enabled by now, so enable nothing more.
# Not in the overlay: deb-systemd-helper enables units through the
# presets as their packages install, and this would block all of them.
# a40-firstboot removes it again, for the packages installed later.
mkdir -p /etc/systemd/system-preset
echo 'disable *' > /etc/systemd/system-preset/00-a40.preset

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/a40
