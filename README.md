# Debian 13 for the Samsung Galaxy A40

A GitHub Actions build of a ready-to-flash Debian 13 (trixie) image for
the Galaxy A40 (SM-A405F, Exynos 7885), on the mainline-based
[a405f kernel](https://github.com/mskvortsov/linux-a405f):

| file | goes to | what |
|---|---|---|
| `boot.img` | `boot` | U-Boot, wrapped in an Android boot image for S-Boot |
| `rootfs.img.zst` | `userdata` | btrfs root filesystem: Debian, the kernel, shannon |
| `linux-image-*.deb`, `shannon_*.deb` | | the packages in the image, for updating an installed one |
| `linux-headers-*.deb` | | for building out-of-tree modules; not in the image |

S-Boot starts U-Boot from `boot`. U-Boot runs `/boot/boot.scr` from
`userdata` (`mmcblk0p32`), which loads `/boot/vmlinuz`, `/boot/initramfs`
and `/boot/dtbs/exynos/exynos7885-a40.dtb` and boots with
`root=/dev/mmcblk0p32`.

## What is in the image

- **Kernel**: `linux-image-*` built from `a405f` with `defconfig` +
  `exynos7870.config` + `exynos7885.config`. Installing a kernel package
  later makes it the booting one: `/etc/kernel/postinst.d/zz-a40-boot`
  copies it to the fixed names above (decompressing the Image, which
  `booti` needs), and `update-initramfs -u` refreshes `/boot/initramfs`.
- **USB networking**: `usb0-gadget.service` sets up an NCM gadget, and
  ifupdown runs a DHCP client (dhcpcd) on `usb0`. The gadget's MAC
  addresses are derived from the eMMC CID, so a phone keeps its lease;
  pin them in `/etc/default/usb0-gadget`. The DHCP request carries the
  hostname (`a405f`).
- **Firmware**: none is in the image. On the first boot,
  `a40-firmware.service` copies it from the phone's own stock partitions,
  which flashing `userdata` leaves in place, before udev loads the
  drivers:
  - `vendor:/etc/wifi/{mx140.bin,mx140_bt.hcf,mx140_wlan.hcf}` →
    `/lib/firmware/` (WiFi and Bluetooth)
  - the `radio` partition → `/lib/firmware/samsung/a40/modem.bin`
  - `efs:/nv_data.bin` → `/lib/firmware/samsung/a40/nv_data.bin`, and
    into shannon's RFS sandbox `/var/lib/shannon/rfs` (`efs/`, plus a
    `pristine/` copy)
  - a tarball of the whole `efs` partition (IMEI, calibration) →
    `/var/lib/a40-firmware/efs.tar`. Copy it off the phone.

  The partitions are only read (`efs` is mounted `ro,noload`). Rerun with
  `sudo a40-firmware-extract --force`.
- **shannon**: the modem daemon, enabled. It starts the CP and serves its
  files, with no data connection until an APN is set in
  `/etc/default/shannon` (`SHANNOND_ARGS="--apn ..."`).
- **First boot** also grows the filesystem to the whole partition and
  generates the machine id and SSH host keys.
- **Login**: `root` with the password **`root`**, on the console and
  over SSH (`/etc/ssh/sshd_config.d/a40-root.conf`). That is open to
  anyone who can reach the phone, over USB or later WiFi: change the
  password or remove that file once you are in. root is the only account, and the
  image has no SSH keys of its own.

## Flashing

The bootloader must be unlocked, as for any custom boot image. Flashing
`userdata` erases Android's data; `efs`, `radio` and `vendor` are not
touched, and the firmware is read from them.

    zstd -d rootfs.img.zst

First put U-Boot on `boot`, from download mode (Volume Down + Volume
Up, then connect USB):

    heimdall flash --BOOT boot.img

The phone restarts into U-Boot. With nothing bootable on `userdata` yet,
it stops at its menu: Volume Up and Down move, Power selects. Choose
**USB Storage (eMMC)**. The eMMC appears on the host as a disk (say
`/dev/sdX`, check with `lsblk`); partition 32 is `userdata`:

    sudo dd if=rootfs.img of=/dev/sdX32 bs=4M conv=fsync status=progress

The image is smaller than the partition; the first boot grows the
filesystem to fill it. When `dd` is done, eject the disk and the phone
restarts:

    sudo eject /dev/sdX

Unplugging the cable does not end USB Storage mode; if the phone stays
in it, hold Power + Volume Down for about 7 seconds.

The first boot takes longer (firmware extraction, the filesystem
resize). Connect over USB: the phone asks for an address by
DHCP, so the host has to offer one (share its connection on the new
USB network interface, or bridge it into a LAN), then

    ssh root@a405f      # or the address from the DHCP server's leases

To reinstall later, the same U-Boot menu is shown for 2 seconds on every
boot.

## Building

    ./build.sh

builds everything in the container from `Dockerfile` (Debian 13,
cross-compiling for arm64) and leaves the files in `out/`. It needs
docker, git and arm64 binfmt on the host (`qemu-user-static`); the rootfs
step runs `mmdebstrap` in a privileged container.

Sources are fetched into `src/` unless they are there already, so a
working tree can be dropped in instead (`src/linux`, `src/shannon`,
`src/u-boot`). Settings, as environment variables:

| variable | default |
|---|---|
| `KERNEL_REPO`, `KERNEL_REF` | `https://github.com/mskvortsov/linux-a405f.git`, `a405f` |
| `SHANNON_REPO`, `SHANNON_REF` | `https://github.com/mskvortsov/shannon.git`, `main` |
| `UBOOT_REPO`, `UBOOT_REF` | `https://github.com/u-boot/u-boot.git`, `v2026.07`, with `u-boot/galaxy-a40.patch` applied |

`.github/workflows/build.yml` runs `build.sh` on pushed tags, pull
requests and by hand (with the kernel and shannon refs as inputs). It needs
no secrets. A pushed tag publishes `out/` as a release named after it,
e.g. a date:

    git tag $(date +%Y%m%d)
    git push origin $(date +%Y%m%d)
