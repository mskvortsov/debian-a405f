setenv bootargs root=/dev/mmcblk0p32 rw console=tty0 loglevel=7 s3c2410_wdt.tmr_atboot=1 consoleblank=0

load mmc 0:0x20 ${kernel_addr_r} /boot/vmlinuz

load mmc 0:0x20 ${ramdisk_addr_r} /boot/initramfs
setenv initrd_size ${filesize}

load mmc 0:0x20 ${fdt_addr_r} /boot/dtbs/exynos/exynos7885-a40.dtb

booti ${kernel_addr_r} ${ramdisk_addr_r}:${initrd_size} ${fdt_addr_r}

# Rebuild boot.scr in place after editing this file, so the file keeps
# its "compression none" property (U-Boot cannot read a small
# compressed file on btrfs):
# mkimage -C none -A arm64 -T script -d /boot/boot.cmd /boot/boot.scr
