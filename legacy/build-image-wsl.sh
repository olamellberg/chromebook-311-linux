#!/bin/bash
# Legacy (2026-03): the old hand-run WSL build with a self-built 6.6 kernel and no initramfs. It gave a black screen
# (docs/history/error-log.md). Kept for reference only; use build/image-build.sh.
set -e

WORKDIR=${WORKDIR:-$HOME}   # holds the kernel tree in linux/
LINUX=$WORKDIR/linux
IMGFILE=$WORKDIR/chromebook-debian.img
IMGSIZE=4G
DTB=mt8183-kukui-jacuzzi-kenzo.dtb
MOUNTPOINT=/mnt/rootfs

echo "=== Step 1: Create disk image ==="
fallocate -l $IMGSIZE $IMGFILE

echo "=== Step 2: Partition image (GPT + ChromeOS kernel + Linux rootfs) ==="
# Create GPT with two partitions
# Part 1: 64MiB ChromeOS kernel
# Part 2: rest as Linux filesystem
parted -s $IMGFILE mklabel gpt
parted -s $IMGFILE mkpart KERN-A 1MiB 65MiB
parted -s $IMGFILE mkpart ROOTFS 65MiB 100%

# Set up loop device
LOOPDEV=$(losetup --show -fP $IMGFILE)
echo "Loop device: $LOOPDEV"

# Set ChromeOS kernel partition type with cgpt
cgpt add -i 1 -t kernel -l KERN-A $LOOPDEV
cgpt add -i 2 -t data -l ROOTFS $LOOPDEV

# Format rootfs
mkfs.ext4 -F -L ROOTFS ${LOOPDEV}p2

echo "=== Step 3: Install Debian ARM64 rootfs ==="
mkdir -p $MOUNTPOINT
mount ${LOOPDEV}p2 $MOUNTPOINT

# debootstrap with foreign mode (ARM64 on x86_64)
debootstrap --arch=arm64 --foreign stable $MOUNTPOINT http://deb.debian.org/debian

# Second stage with qemu
cp /usr/bin/qemu-aarch64-static $MOUNTPOINT/usr/bin/ 2>/dev/null || true
chroot $MOUNTPOINT /debootstrap/debootstrap --second-stage

echo "=== Step 4: Configure rootfs ==="
# Set root password to 'debian'
chroot $MOUNTPOINT bash -c "echo 'root:debian' | chpasswd"

# Hostname
echo "debian-chromebook" > $MOUNTPOINT/etc/hostname

# fstab
cat > $MOUNTPOINT/etc/fstab <<'FSTAB'
LABEL=ROOTFS / ext4 defaults,noatime 0 1
FSTAB

# Enable serial console and tty1
mkdir -p $MOUNTPOINT/etc/systemd/system/getty.target.wants
ln -sf /lib/systemd/system/getty@.service $MOUNTPOINT/etc/systemd/system/getty.target.wants/getty@tty1.service

# Network config
cat > $MOUNTPOINT/etc/network/interfaces <<'NET'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

allow-hotplug wlan0
iface wlan0 inet dhcp
NET

# DNS
echo "nameserver 8.8.8.8" > $MOUNTPOINT/etc/resolv.conf

# Install kernel modules
cd $LINUX
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=$MOUNTPOINT modules_install

# Clean up qemu
rm -f $MOUNTPOINT/usr/bin/qemu-aarch64-static

echo "=== Step 5: Build FIT image ==="
cd $LINUX

cat > kernel.its <<ITS
/dts-v1/;
/ {
  description = "Linux kernel with MT8183 jacuzzi kenzo DTB";
  images {
    kernel {
      description = "Linux kernel";
      data = /incbin/("arch/arm64/boot/Image");
      type = "kernel_noload";
      arch = "arm64";
      os = "linux";
      compression = "none";
      load = <0>;
      entry = <0>;
    };
    fdt {
      description = "$DTB";
      data = /incbin/("arch/arm64/boot/dts/mediatek/$DTB");
      type = "flat_dt";
      arch = "arm64";
      compression = "none";
    };
  };
  configurations {
    default = "conf";
    conf {
      kernel = "kernel";
      fdt = "fdt";
    };
  };
};
ITS

mkimage -f kernel.its kernel.itb

echo "=== Step 6: Sign kernel with vboot ==="
cat > cmdline.txt <<'CMD'
root=LABEL=ROOTFS rw rootwait console=tty0 console=tty1 loglevel=7 earlycon
CMD

# Create bootloader stub
dd if=/dev/zero of=bootloader.bin bs=64 count=1 2>/dev/null

vbutil_kernel --pack kernel.signed \
  --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
  --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
  --version 1 \
  --vmlinuz kernel.itb \
  --bootloader bootloader.bin \
  --arch arm64 \
  --config cmdline.txt

echo "=== Step 7: Write kernel to partition 1 ==="
dd if=kernel.signed of=${LOOPDEV}p1 bs=4M status=progress

# Set vboot flags
cgpt add -i 1 -S 1 -T 5 -P 15 $LOOPDEV

echo "=== Step 8: Unmount and detach ==="
umount $MOUNTPOINT
losetup -d $LOOPDEV

echo "=== Step 9: Done ==="
echo "copy $IMGFILE to a USB stick, e.g. with dd or Etcher"

echo ""
echo "=========================================="
echo "DONE! Image at: $IMGFILE"
echo "Flash with Rufus (DD mode) or Etcher"
echo "Root password: debian"
echo "=========================================="
