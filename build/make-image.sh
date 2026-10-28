#!/usr/bin/env bash
# Builds the bootable USB image for the Acer CB311-11H (MT8183 jacuzzi/kenzo). Runs inside the build container
# (build/Containerfile) as container root; started by build/image-build.sh. Needs no loop devices or mounts on the
# host: the rootfs is a directory (mmdebstrap), the ext4 file is made with mke2fs -d, and the disk image is put
# together with cgpt and dd.
#   /port  this repository (read-only)   /work  scratch (volume, kept between runs)   /out  results
#
# Settings (environment): SUITE, MIRROR, IMG_SIZE_MIB, KERN_SIZE_MIB, DTB, ROOT_PASSWORD, KERNEL_COMPRESS (lz4|lzma),
# KERN_ATTRS (cgpt flags of KERN-A), EXTRA_CMDLINE, EXTRA_PACKAGES, IMG_COMPRESS (xz|none),
# SSH_AUTHORIZED_KEY (a public key for root over SSH; password logins stay off), USER_NAME and USER_PASSWORD (the
# desktop account; an empty USER_NAME makes none), PASSWORD_EXPIRED (1: both passwords must be changed at the first
# login; root's not when SSH_AUTHORIZED_KEY is set), KEYBOARD_LAYOUT (XKB layout, default us).
set -euo pipefail

SUITE=${SUITE:-trixie}
MIRROR=${MIRROR:-http://deb.debian.org/debian}
IMG_SIZE_MIB=${IMG_SIZE_MIB:-8192}   # the rootfs with XFCE is about 2.7 GiB
KERN_SIZE_MIB=${KERN_SIZE_MIB:-128}   # Image 36 MiB + an initrd with MODULES=most can pass 64 MiB
DTB=${DTB:-mediatek/mt8183-kukui-jacuzzi-kenzo.dtb}
ROOT_PASSWORD=${ROOT_PASSWORD:-debian}
USER_NAME=${USER_NAME-user}
USER_PASSWORD=${USER_PASSWORD:-$USER_NAME}
USER_GROUPS=sudo,audio,video,render,input,plugdev,netdev,bluetooth
# The default passwords are public, so they must be changed at the first login (PASSWORD_EXPIRED=0 turns that off)
PASSWORD_EXPIRED=${PASSWORD_EXPIRED:-1}
KEYBOARD_LAYOUT=${KEYBOARD_LAYOUT:-us}   # an XKB layout: us, gb, de, se, ...
export USER_NAME USER_PASSWORD USER_GROUPS PASSWORD_EXPIRED KEYBOARD_LAYOUT   # read by the customize hooks
# depthcharge-tools boards.ini: kukui boots lz4 and lzma FIT kernels and loads the FIT ramdisk; max 512 MiB.
# lzma is what postmarketOS ships on kenzo (device-google-kukui deviceinfo)
KERNEL_COMPRESS=${KERNEL_COMPRESS:-lzma}
# S=0: vboot counts down the tries until boot-marker.service sets S=1 (docs/history/error-log.md, tries check)
KERN_ATTRS=${KERN_ATTRS:--S 0 -T 15 -P 15}
EXTRA_CMDLINE=${EXTRA_CMDLINE:-loglevel=7 ignore_loglevel panic=10}
IMG_COMPRESS=${IMG_COMPRESS:-xz}

PACKAGES="systemd-sysv udev kmod dbus linux-image-arm64 initramfs-tools zstd
    firmware-linux-free firmware-mediatek firmware-atheros firmware-misc-nonfree
    e2fsprogs network-manager wpasupplicant iw wireless-regdb sudo less vim-tiny procps iproute2 iputils-ping ca-certificates cgpt
    console-setup openssh-server bluez alsa-utils alsa-ucm-conf depthcharge-tools
    xserver-xorg xfce4 xfce4-goodies lightdm pipewire-audio wireplumber rtkit network-manager-gnome blueman
    ${EXTRA_PACKAGES:-}"

NAME=chromebook-debian-$(date +%Y%m%d-%H%M)
ROOTFS=/work/rootfs
ROOT_GUID=$(cat /proc/sys/kernel/random/uuid)
KERN_GUID=$(cat /proc/sys/kernel/random/uuid)
CMDLINE="console=tty1 root=PARTUUID=$ROOT_GUID rootwait rw $EXTRA_CMDLINE"

log() { echo "== $(date +%T) $*"; }

log "rootfs: Debian $SUITE arm64 (mmdebstrap)"
rm -rf "$ROOTFS" /work/kernel /work/root.ext4 /work/disk.img
mmdebstrap --mode=root --architectures=arm64 --variant=minbase --include="$(echo $PACKAGES | tr ' ' ,)" \
    --customize-hook='sync-in /port/build/rootfs /' \
    --customize-hook='chmod 755 "$1"/usr/local/sbin/*' \
    --customize-hook='python3 /port/build/fetch-firmware.py "$1"' \
    --customize-hook='sed -i "s/^XKBLAYOUT=.*/XKBLAYOUT=\"$KEYBOARD_LAYOUT\"/" "$1"/etc/default/keyboard' \
    --customize-hook="echo 'PARTUUID=$ROOT_GUID / ext4 defaults,noatime 0 1' > \"\$1\"/etc/fstab" \
    --customize-hook='echo "127.0.1.1 $(cat "$1"/etc/hostname)" >> "$1"/etc/hosts' \
    --customize-hook="echo 'root:$ROOT_PASSWORD' | chroot \"\$1\" chpasswd" \
    --customize-hook='mkdir -p "$1"/var/log/journal' \
    --customize-hook='chroot "$1" systemctl enable boot-marker.service' \
    --customize-hook='if [ -n "$USER_NAME" ]; then chroot "$1" useradd -m -s /bin/bash -G "$USER_GROUPS" "$USER_NAME";
        echo "$USER_NAME:$USER_PASSWORD" | chroot "$1" chpasswd; fi' \
    --customize-hook='[ "$PASSWORD_EXPIRED" = 0 ] || for u in root $USER_NAME; do
        # an expired password also blocks key logins, so root stays reachable over SSH when a key is given
        [ "$u" = root ] && [ -n "${SSH_AUTHORIZED_KEY:-}" ] || chroot "$1" passwd -q -e "$u"; done' \
    --customize-hook='if [ -n "${SSH_AUTHORIZED_KEY:-}" ]; then install -d -m 700 "$1"/root/.ssh;
        echo "$SSH_AUTHORIZED_KEY" > "$1"/root/.ssh/authorized_keys; chmod 600 "$1"/root/.ssh/authorized_keys; fi' \
    --customize-hook='chroot "$1" update-initramfs -u -k all' \
    "$SUITE" "$ROOTFS" \
    "deb $MIRROR $SUITE main non-free-firmware" \
    "deb $MIRROR $SUITE-updates main non-free-firmware" \
    "deb http://security.debian.org/debian-security $SUITE-security main non-free-firmware"

log "kernel"
mkdir -p /work/kernel
VMLINUZ=$(ls "$ROOTFS"/boot/vmlinuz-* | sort -V | tail -1)
KVER=${VMLINUZ##*/vmlinuz-}
INITRD=$ROOTFS/boot/initrd.img-$KVER
DTB_FILE=$ROOTFS/usr/lib/linux-image-$KVER/$DTB
[ -f "$INITRD" ] || { echo "missing $INITRD" >&2; exit 1; }
[ -f "$DTB_FILE" ] || { echo "missing $DTB_FILE" >&2; exit 1; }
# Debian 6.12 ships a plain arm64 Image (36 MiB); still checked, so a format mkdepthcharge cannot unpack (e.g. EFI zboot) fails here
case "$(file -b "$VMLINUZ")" in
    gzip*) zcat "$VMLINUZ" > /work/kernel/Image ;;
    *) cp "$VMLINUZ" /work/kernel/Image ;;
esac
[ "$(dd if=/work/kernel/Image bs=1 skip=56 count=4 2>/dev/null)" = ARMd ] \
    || { echo "$VMLINUZ is not an arm64 Image ($(file -b "$VMLINUZ"))" >&2; exit 1; }

# What of build/rootfs/etc/initramfs-tools/modules really is in the initrd (or built into the kernel)
lsinitramfs "$INITRD" | sed -n 's|.*/\([^/]*\)\.ko\(\.[a-z]*\)\?$|\1|p' | tr - _ | sort -u > /work/kernel/initrd-modules
sed 's|.*/\([^/]*\)\.ko$|\1|' "$ROOTFS/lib/modules/$KVER/modules.builtin" | tr - _ | sort -u > /work/kernel/builtin-modules
MISSING=()
while read -r m; do
    m=${m%%#*}; m=${m// /}; [ -n "$m" ] || continue
    if grep -qx "${m//-/_}" /work/kernel/initrd-modules; then echo "   initrd    $m"
    elif grep -qx "${m//-/_}" /work/kernel/builtin-modules; then echo "   built-in  $m"
    else echo "   MISSING   $m"; MISSING+=("$m"); fi
done < /port/build/rootfs/etc/initramfs-tools/modules

mkdepthcharge -o /work/kernel/kernel.img --arch arm64 --format fit --compress "$KERNEL_COMPRESS" \
    --keydir /usr/share/vboot/devkeys --vmlinuz /work/kernel/Image --initramfs "$INITRD" --dtbs "$DTB_FILE" \
    --cmdline "$CMDLINE"
KERN_BYTES=$(stat -c %s /work/kernel/kernel.img)
[ "$KERN_BYTES" -le $(( KERN_SIZE_MIB * 1024 * 1024 )) ] \
    || { echo "kernel.img ($KERN_BYTES bytes) does not fit in KERN-A ($KERN_SIZE_MIB MiB)" >&2; exit 1; }

log "rootfs -> ext4"
ROOT_START_MIB=$(( 1 + KERN_SIZE_MIB ))
ROOT_SIZE_MIB=$(( IMG_SIZE_MIB - ROOT_START_MIB - 1 ))   # the last MiB holds the backup GPT
mke2fs -q -t ext4 -L ROOTFS -d "$ROOTFS" /work/root.ext4 "${ROOT_SIZE_MIB}M"

log "disk image: GPT, KERN-A $KERN_SIZE_MIB MiB, ROOTFS $ROOT_SIZE_MIB MiB"
truncate -s "${IMG_SIZE_MIB}M" /work/disk.img
cgpt create /work/disk.img
# shellcheck disable=SC2086
cgpt add -i 1 -b 2048 -s $(( KERN_SIZE_MIB * 2048 )) -t kernel -l KERN-A -u "$KERN_GUID" $KERN_ATTRS /work/disk.img
cgpt add -i 2 -b $(( ROOT_START_MIB * 2048 )) -s $(( ROOT_SIZE_MIB * 2048 )) -t data -l ROOTFS -u "$ROOT_GUID" \
    /work/disk.img
cgpt boot -p /work/disk.img
dd if=/work/kernel/kernel.img of=/work/disk.img bs=1M seek=1 conv=notrunc,sparse status=none
dd if=/work/root.ext4 of=/work/disk.img bs=1M seek="$ROOT_START_MIB" conv=notrunc,sparse status=none
cgpt show /work/disk.img

log "results -> /out/$NAME.*"
cp /work/kernel/kernel.img "/out/$NAME.kernel.img"
{
    echo "image:    $NAME.img"
    echo "debian:   $SUITE, kernel $KVER, dtb $DTB"
    echo "cmdline:  kern_guid=%U $CMDLINE"
    echo "KERN-A:   $KERN_GUID ($KERN_ATTRS), kernel.img $KERN_BYTES bytes ($KERNEL_COMPRESS)"
    echo "ROOTFS:   $ROOT_GUID"
    echo "login:    root / $ROOT_PASSWORD${USER_NAME:+, $USER_NAME / $USER_PASSWORD (groups $USER_GROUPS)}"
    echo "missing initramfs modules: ${MISSING[*]:-none}"
    echo "packages:"; dpkg-query --admindir="$ROOTFS/var/lib/dpkg" -W -f '  ${Package} ${Version}\n'
} > "/out/$NAME.txt"
if [ "$IMG_COMPRESS" = xz ]; then
    xz -T0 -3 -c /work/disk.img > "/out/$NAME.img.xz"
else
    cp --sparse=always /work/disk.img "/out/$NAME.img"
fi
(cd /out && files=$(ls "$NAME".*img*) && sha256sum $files > "$NAME.sha256" && ls -l "$NAME".*)
log "done"
