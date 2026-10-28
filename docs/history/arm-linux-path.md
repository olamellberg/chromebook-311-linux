## ARM path for CB311-11H (MediaTek MT8183)

### Summary
CB311-11H is an ARM Chromebook. The standard MrChromebox Full ROM UEFI path is Intel-only, so a full disk Linux install via UEFI is not supported. Use one of the ARM-compatible options below.

### Option A: Keep ChromeOS, use built-in Linux (Crostini)
Use this if you want Linux apps and dev tools without replacing ChromeOS.

1. In ChromeOS settings, enable Linux (Beta).
2. Install packages via `apt` in the Linux container.
3. For GUI apps, use the built-in windowing support.

Pros: safest, no firmware changes.  
Cons: not a full bare-metal Linux install.

### Option B: Boot alternate OS (ARM) with board-specific tooling
Use this if you need a more native Linux experience. This is advanced and board-specific.

#### Step-by-step (board-specific ARM install)
1. Identify the board name in ChromeOS:
   - Open crosh: `Ctrl` + `Alt` + `T`
   - Run: `shell` then `cat /etc/lsb-release`
   - Note `CHROMEOS_RELEASE_BOARD`
2. Verify the board has an ARM Linux port:
   - Look for a dedicated guide for that board name (kernel, DTB, boot chain).
   - Confirm Wi-Fi, audio, and suspend/resume are known to work.
3. Back up your data and create ChromeOS recovery media:
   - Use the Chromebook Recovery Utility to make a USB recovery drive.
4. Enable Developer Mode:
   - This is required for most ARM boot-chain modifications.
5. Follow the board-specific guide exactly:
   - Install the required kernel and device tree.
   - Configure boot chain (board-specific; often involves `cgpt`, `vboot`, or custom scripts).
6. Test hardware basics after first boot:
   - Wi-Fi, audio, keyboard, touchpad, sleep/wake, and battery status.
7. Keep recovery media ready:
   - If the boot chain breaks, restore ChromeOS using the recovery USB.

#### Your board (from `/etc/lsb-release`)
- `CHROMEOS_RELEASE_BOARD=jacuzzi-signed-mp-v17keys`
- This is the **jacuzzi** board family (MediaTek MT8183, ARM64).

#### What this means for booting
- You cannot use a standard x86 Linux live USB.
- You need a **Depthcharge/vboot-compatible kernel image** (FIT) on a ChromeOS-style kernel partition.

#### Reference docs for jacuzzi/Depthcharge
- Jacuzzi board overview: https://lava.pages.collabora.com/docs/boards/chromebooks/boards/jacuzzi/
- Chromebook boot flow (Depthcharge/vboot): https://docs.kernel.org/arch/arm/google/chromebook-boot-flow.html
- Creating bootable media for Depthcharge devices: https://wiki.gentoo.org/wiki/Creating_bootable_media_for_depthcharge_based_devices

Pros: closer to native Linux.  
Cons: higher risk, device-specific, often incomplete.

### Option C: Replace with ARM Chromebook firmware (rare, experimental)
This is uncommon for MediaTek devices and generally not recommended.

### Recommendation
For CB311-11H, the reliable path is **Option A (Crostini)**.  
Only pursue Option B if you have a known, well-tested guide for your board.

### Next step to continue the plan
Default to **Debian ARM64** (best general support and documentation). The kernel/FIT + rootfs steps below are written for Debian.

#### Debian ARM64 outline for jacuzzi (high-level)
1. Prepare a bootable USB with ChromeOS-style kernel and root partitions (GPT + kernel partition).
2. Build or obtain a Depthcharge-compatible kernel FIT image that includes the correct DTB for jacuzzi.
3. Install a Debian ARM64 root filesystem onto the root partition.
4. Set kernel partition flags with `cgpt` and boot via Developer Mode.
5. Verify hardware (Wi-Fi/audio/suspend) and iterate on kernel config if needed.

#### Debian ARM64 steps (practical, WSL2 + USB)
These steps assume you will build the media on Windows 11 + WSL2 Ubuntu 22.04.  
WSL2 cannot see USB block devices by default; you must attach the USB drive.

##### A) Attach USB to WSL2 (Windows 11)
1. Install `usbipd` (PowerShell, admin):
   - `winget install --id=Microsoft.usbipd -e`
2. List USB devices:
   - `usbipd list`
3. Identify your USB drive (by size/vendor) and note its BUSID.
4. Attach to WSL2:
   - `usbipd attach --busid <BUSID>`
5. In WSL2, confirm it appears:
   - `lsblk` (you should see something like `/dev/sdX`)

If USB attach is not possible, use a separate Linux PC to build the USB.

##### B) Install required tools in WSL2
```
sudo apt update
sudo apt install -y cgpt vboot-kernel-utils u-boot-tools debootstrap fdisk git \
  build-essential bc bison flex libssl-dev libelf-dev \
  gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
```

##### C) Partition the USB for Depthcharge
Replace `/dev/sdX` with your USB device. This will erase the USB.
First, confirm the device:
```
lsblk -o NAME,SIZE,MODEL,TRAN
```
```
sudo fdisk /dev/sdX
```
Create:
- Partition 1: 64 MiB, type `ChromeOS kernel`
- Partition 2: remaining space, type `Linux filesystem`

Then set GPT attributes and format:
```
sudo cgpt add -i 1 -t kernel -l KERN-A /dev/sdX
sudo cgpt add -i 2 -t data -l ROOTFS /dev/sdX
sudo mkfs.ext4 -L ROOTFS /dev/sdX2
```

##### D) Create Debian ARM64 rootfs
```
sudo mkdir -p /mnt/usb
sudo mount /dev/sdX2 /mnt/usb
sudo debootstrap --arch=arm64 stable /mnt/usb http://deb.debian.org/debian
```

##### D2) Basic Debian setup (recommended)
```
sudo mount --bind /dev /mnt/usb/dev
sudo mount --bind /proc /mnt/usb/proc
sudo mount --bind /sys /mnt/usb/sys
sudo chroot /mnt/usb /bin/bash
passwd
echo "debian" > /etc/hostname
cat > /etc/fstab <<'EOF'
LABEL=ROOTFS / ext4 defaults 0 1
EOF
exit
sudo umount /mnt/usb/dev /mnt/usb/proc /mnt/usb/sys
```

##### E) Build a Depthcharge-compatible kernel FIT (upstream kernel)
This uses the upstream Linux kernel and the jacuzzi DTB for **kenzo**.

1) Get the kernel source (LTS recommended):
```
git clone https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
cd linux
git checkout linux-6.6.y
```
If `linux-6.6.y` is not present, use the latest `v6.6.x` tag.

2) Configure and build:
```
make ARCH=arm64 defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image dtbs
```
Confirm the DTB exists:
```
ls arch/arm64/boot/dts/mediatek/mt8183-kukui-jacuzzi-kenzo.dtb
```

3) Create a FIT image:
```
cat > kernel.its <<'EOF'
/dts-v1/;
/ {
  description = "Linux kernel with MT8183 jacuzzi kenzo DTB";
  images {
    kernel@1 {
      description = "Linux kernel";
      data = /incbin/("arch/arm64/boot/Image");
      type = "kernel_noload";
      arch = "arm64";
      os = "linux";
      compression = "none";
      load = <0>;
      entry = <0>;
    };
    fdt@1 {
      description = "mt8183-kukui-jacuzzi-kenzo.dtb";
      data = /incbin/("arch/arm64/boot/dts/mediatek/mt8183-kukui-jacuzzi-kenzo.dtb");
      type = "flat_dt";
      arch = "arm64";
      compression = "none";
    };
  };
  configurations {
    default = "conf@1";
    conf@1 {
      kernel = "kernel@1";
      fdt = "fdt@1";
    };
  };
};
EOF

mkimage -f kernel.its kernel.itb
```

4) Create kernel cmdline and sign with vboot:
```
cat > cmdline.txt <<'EOF'
root=LABEL=ROOTFS rw rootwait console=tty1
EOF

vbutil_kernel --pack kernel.signed \
  --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
  --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
  --version 1 \
  --vmlinuz kernel.itb \
  --arch arm64 \
  --config cmdline.txt
```

##### F) Write kernel to the kernel partition
```
sudo dd if=kernel.signed of=/dev/sdX1 bs=4M status=progress
sudo cgpt add -i 1 -S 1 -T 5 -P 15 /dev/sdX
```

##### G) Boot on Chromebook
1. Enable Developer Mode.
2. Insert the USB and boot with `Ctrl` + `U`.
3. If it boots, complete Debian setup and verify hardware.

##### H) Validation and recovery
- Validate: Wi‑Fi, audio, keyboard, touchpad, sleep/wake, battery.
- Keep ChromeOS recovery media ready to restore if boot fails.
