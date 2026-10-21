#!/bin/sh
# Boot rootfs.img under QEMU and check that root can log in over SSH, on
# the first boot and on the one after it. Runs on the host, not in the
# build container (it needs qemu-system-aarch64, sudo for a loop mount,
# ssh and sshpass):
#
#   scripts/test-rootfs.sh OUTDIR [WORKDIR]
#
# The kernel is the image's own, on QEMU's virt machine. Its config has
# no PCI and no PL011, so the disk and network are virtio-mmio and there
# is no console: on a failure the guest's journal is read from the disk.
# What QEMU cannot show: the USB gadget network (the kernel's ip=dhcp
# stands in for it) and the firmware the phone's partitions provide.
set -eu

OUT=$(cd "$1" && pwd)
WORK=${2:-$OUT/../build/test}
WORK=$(mkdir -p "$WORK" && cd "$WORK" && pwd)
PORT=${SSH_PORT:-2222}
# Without KVM a boot takes a minute or two; leave room for a slow runner
BOOT_TIMEOUT=${BOOT_TIMEOUT:-600}

cd "$WORK"
rm -f qemu.pid
zstd -dqf "$OUT/rootfs.img.zst" -o rootfs.img
# Bigger than the image, so a40-firstboot has something to grow into
truncate -s 2G rootfs.img

mkdir -p mnt
sudo mount -o ro,loop rootfs.img mnt
cp mnt/boot/vmlinuz mnt/boot/initramfs .
sudo umount mnt

log() { echo "test-rootfs: $*"; }

guest() {
    sshpass -p root ssh -p "$PORT" -o ConnectTimeout=5 \
        -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR root@127.0.0.1 "$@"
}

running() { [ -s qemu.pid ] && kill -0 "$(cat qemu.pid)" 2>/dev/null; }

start() {
    rm -f qemu.pid
    qemu-system-aarch64 \
        -M virt -cpu max -smp 4 -m 2G \
        -display none -serial none -monitor none \
        -daemonize -pidfile qemu.pid \
        -kernel vmlinuz -initrd initramfs \
        -append "root=/dev/vda rw ip=dhcp" \
        -drive if=none,file=rootfs.img,format=raw,id=hd \
        -device virtio-blk-device,drive=hd \
        -netdev user,id=n,hostfwd=tcp:127.0.0.1:$PORT-:22 \
        -device virtio-net-device,netdev=n \
        -device virtio-rng-device
}

# Root logs in with the password "root", through sshpass
wait_login() {
    deadline=$(( $(date +%s) + BOOT_TIMEOUT ))
    until guest true 2>/dev/null; do
        running || { log "QEMU exited before root could log in"; return 1; }
        [ "$(date +%s)" -lt "$deadline" ] ||
            { log "no SSH login after ${BOOT_TIMEOUT}s"; return 1; }
        sleep 5
    done
    log "root logged in over SSH"
}

stop() {
    guest systemctl poweroff 2>/dev/null || true
    for _ in $(seq 120); do
        running || return 0
        sleep 1
    done
    log "guest did not power off, killing QEMU"
    kill "$(cat qemu.pid)"
    sleep 2
}

# The guest's checks; "first" or "again" says which boot it is
checks() {
    guest sh -s "$1" <<'EOF'
set -u
failed=0
check() {
    desc=$1; shift
    if "$@" >/dev/null 2>&1; then echo "  ok    $desc"
    else echo "  FAIL  $desc"; failed=1; fi
}
first_boot() { journalctl -b --no-pager | grep -q 'Detected first boot'; }
no_failed_units() { [ -z "$(systemctl --failed --no-legend)" ]; }

if [ "$1" = first ]; then
    check "systemd detected the first boot" first_boot
    for u in a40-firstboot sshd-keygen; do
        check "$u ran" systemctl is-active "$u.service"
    done
    check "preset for the first boot removed" \
        test ! -e /etc/systemd/system-preset/00-a40.preset
else
    check "not a first boot" sh -c '! journalctl -b --no-pager | grep -q "Detected first boot"'
fi
check "ssh active" systemctl is-active ssh.service
for k in rsa ecdsa ed25519; do
    check "host key $k" test -s /etc/ssh/ssh_host_${k}_key
done
for u in sshd-keygen.service networking.service wpa_supplicant.service \
        cron.service systemd-timesyncd.service apt-daily.timer \
        logrotate.timer; do
    check "$u enabled" systemctl is-enabled "$u"
done
for u in systemd-networkd.service systemd-networkd-wait-online.service; do
    check "$u not enabled" sh -c "! systemctl is-enabled -q $u"
done
check "root filesystem grown" sh -c \
    '[ "$(btrfs filesystem show --raw / | sed -n "s/.* size \([0-9]*\) .*/\1/p")" -gt 1073741824 ]'
check "default locale set" grep -qx 'LANG=en_US.UTF-8' /etc/default/locale
check "en_US.UTF-8 works for perl" sh -c \
    '[ -z "$(LANG=en_US.UTF-8 perl -e 1 2>&1)" ]'
check "no failed units" no_failed_units
systemctl --failed --no-legend
exit $failed
EOF
}

# The guest's own view of what went wrong, from its disk
journal() {
    running && kill "$(cat qemu.pid)" && sleep 2
    # QEMU may have been killed: do not replay the btrfs log
    sudo mount -o ro,loop,rescue=nologreplay rootfs.img mnt || return 0
    echo "--- guest journal, last boot"
    sudo journalctl -D mnt/var/log/journal --no-pager -b -o short-monotonic |
        tail -n 300 || true
    echo "--- guest units"
    ls -R mnt/etc/systemd/system || true
    sudo umount mnt
}

trap 'status=$?; [ "$status" = 0 ] || journal; exit $status' EXIT
# QEMU is daemonized and outlives the script: an interrupted run goes
# through the EXIT trap too, which stops it
trap 'exit 130' INT TERM HUP

log "first boot"
start
wait_login
checks first
key=$(guest cat /etc/ssh/ssh_host_ed25519_key.pub)
id=$(guest cat /etc/machine-id)
stop

log "second boot"
start
wait_login
checks again
[ "$(guest cat /etc/ssh/ssh_host_ed25519_key.pub)" = "$key" ] ||
    { log "host key changed on the second boot"; exit 1; }
[ "$(guest cat /etc/machine-id)" = "$id" ] ||
    { log "machine id changed on the second boot"; exit 1; }
log "host key and machine id kept"
stop

rm -f rootfs.img
log "passed"
