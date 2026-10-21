#!/bin/sh
# Set up the USB gadget (ncm.usb0) through configfs. ifupdown then runs a
# DHCP client on usb0 (/etc/network/interfaces).
#
# The MAC addresses are derived from the eMMC's CID, so they stay the same
# across boots and reinstalls of one phone (and the host's DHCP server
# hands out the same lease) but differ between phones. Set DEV_ADDR and
# HOST_ADDR in /etc/default/usb0-gadget to pin them instead.
set -e

CONFIGFS=/sys/kernel/config/usb_gadget
GADGET="$CONFIGFS/g1"

USB_ID_VENDOR="0x04e8"
USB_ID_PRODUCT="0x6860"
USB_MANUFACTURER="Samsung"
USB_PRODUCT="Samsung Galaxy A40 (Debian)"
USB_SERIALNUMBER="Debian"
USB_FUNCTION="ncm.usb0"
DEV_ADDR=
HOST_ADDR=

[ -r /etc/default/usb0-gadget ] && . /etc/default/usb0-gadget

# A locally administered unicast MAC from a hash of the CID and a salt
mac_from_cid() {
    cid=$(cat /sys/block/mmcblk0/device/cid 2>/dev/null) || return 1
    [ -n "$cid" ] || return 1
    h=$(printf '%s %s' "$cid" "$1" | sha256sum)
    first=$(( (0x$(echo "$h" | cut -c1-2) & 0xfe) | 0x02 ))
    printf '%02x%s\n' "$first" "$(echo "$h" | cut -c3-12)" | sed 's/../&:/g; s/:$//'
}

[ -n "$DEV_ADDR" ]  || DEV_ADDR=$(mac_from_cid dev)   || DEV_ADDR=
[ -n "$HOST_ADDR" ] || HOST_ADDR=$(mac_from_cid host) || HOST_ADDR=

[ -e "$CONFIGFS" ] || { echo "configfs not mounted, skipping gadget setup"; exit 0; }
[ -e "$GADGET" ] && { echo "gadget already configured, skipping"; exit 0; }

# The UDC is built in, but give it a moment in case it probes late
for _ in 1 2 3 4 5 6 7 8 9 10; do
    UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
    [ -n "$UDC" ] && break
    sleep 1
done
[ -n "$UDC" ] || { echo "no UDC found, skipping gadget setup"; exit 0; }

mkdir "$GADGET"
echo "$USB_ID_VENDOR"  > "$GADGET/idVendor"
echo "$USB_ID_PRODUCT" > "$GADGET/idProduct"

mkdir "$GADGET/strings/0x409"
echo "$USB_MANUFACTURER" > "$GADGET/strings/0x409/manufacturer"
echo "$USB_SERIALNUMBER" > "$GADGET/strings/0x409/serialnumber"
echo "$USB_PRODUCT"      > "$GADGET/strings/0x409/product"

mkdir "$GADGET/functions/$USB_FUNCTION"
# Without a CID the kernel picks random addresses
[ -n "$HOST_ADDR" ] && echo "$HOST_ADDR" > "$GADGET/functions/$USB_FUNCTION/host_addr"
[ -n "$DEV_ADDR" ]  && echo "$DEV_ADDR"  > "$GADGET/functions/$USB_FUNCTION/dev_addr"

mkdir "$GADGET/configs/c.1"
mkdir "$GADGET/configs/c.1/strings/0x409"
echo "USB network" > "$GADGET/configs/c.1/strings/0x409/configuration"

ln -s "$GADGET/functions/$USB_FUNCTION" "$GADGET/configs/c.1/"

echo "$UDC" > "$GADGET/UDC"

echo "usb0 gadget up: dev=${DEV_ADDR:-random} host=${HOST_ADDR:-random} udc=$UDC"
