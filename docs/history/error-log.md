# Error log: CB311-11H ARM Linux bringup

## Device identification
- Model: Acer CB311-11H (N19Q10)
- Board: `CHROMEOS_RELEASE_BOARD=jacuzzi-signed-mp-v17keys`
- Firmware ID shown in recovery: `Google_Juniper`
- SoC: MediaTek MT8183 (ARM64)

## Target boot flow
- Chromebook ARM (Depthcharge/vboot) boot from USB.
- Kernel+DTB in ChromeOS kernel partition (`/dev/sdX1`), Debian rootfs on ext4 partition (`/dev/sdX2`).
- Rootfs built via `debootstrap --arch=arm64`.

## USB preparation summary
### Partitioning
- GPT created with:
  - Partition 1: 64 MiB, ChromeOS kernel, label `KERN-A`
  - Partition 2: rest, ext4, label `ROOTFS`
- `cgpt show` confirms:
  - `KERN-A` UUID `AE4F83FB-DACF-F74C-9CE3-260C2AAC2180`
  - `ROOTFS` PARTUUID `c2cbf122-30ab-7841-b8db-eb3ff8cb9920`
- ext4 label confirmed: `ROOTFS`

### Rootfs build
- Initial `debootstrap` failed with:
  - `W: Failure trying to run: chroot "/mnt/usb" /bin/true`
  - Root cause: ARM chroot on x86_64 WSL2.
- Fixed by:
  - Installing `qemu-user-static`, `binfmt-support`.
  - Re-running `debootstrap` in `--foreign` mode.
  - Executing `/debootstrap/debootstrap --second-stage` under QEMU.
- Debian base system installed successfully afterward.

## Kernel build and FIT creation
### Kernel
- Linux stable `linux-6.6.y` checked out and built:
  - `make ARCH=arm64 defconfig`
  - `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image dtbs`
- DTBs available for jacuzzi family; selected DTB based on firmware ID:
  - `mt8183-kukui-jacuzzi-juniper-sku16.dtb`

### FIT image creation issues
- `mkimage` from Ubuntu (`2022.01+dfsg-2ubuntu2.6`) failed with:
  - `mkimage: verify_header failed for FIT Image support`
- Resolution:
  - Built `mkimage` from upstream U‑Boot tools:
    - `make tools-only_defconfig`
    - `make tools-only`
  - Encountered missing `gnutls/gnutls.h`, fixed by installing `libgnutls28-dev`.

### FIT node naming issue
- Initial FIT used `kernel@1` / `fdt@1` nodes, produced:
  - `Image contains unit address @, this will break signing`
- Fixed by removing `@1` node suffixes in `kernel.its`.

## Kernel signing (vboot)
### Error: missing bootloader file
- `vbutil_kernel` failed with:
  - `FATAL: do_vbutil_kernel: Missing required bootloader file.`
- `/dev/null` as bootloader failed under WSL:
  - `Error reading bootloader file.`
- Fix:
  - Created non‑empty file `bootloader.bin` (64 bytes of zeros).
  - Signing succeeded with `--bootloader ~/linux/bootloader.bin`.

## Boot attempts and symptoms
### Boot method
- Chromebook in Developer Mode, boot via `Ctrl+U` from USB.

### Symptom
- Screen stays black after `Ctrl+U` for >5 minutes.
- Power LED blue; no visible text/logs.
- No HDMI output available for external display test.

### Debug attempts
1. **Rootfs label vs PARTUUID**
   - Updated kernel cmdline from:
     - `root=LABEL=ROOTFS`
   - to:
     - `root=PARTUUID=c2cbf122-30ab-7841-b8db-eb3ff8cb9920`
   - No change; still black screen.

2. **Verbose console + logging**
   - Cmdline updated to:
     - `console=tty0 console=tty1 loglevel=7 ignore_loglevel rootdelay=5`
   - No visible output (screen still black).

3. **Persistent journald logs**
   - `/var/log/journal` created on rootfs for persistence.
   - After boot attempt: `journalctl --directory /mnt/usb/var/log/journal -b -1`
     - No journal files found, implying systemd never started.

4. **Display driver enablement**
   - Kernel config updated to include:
     - `DRM`, `DRM_MEDIATEK`, `DRM_PANEL`, `DRM_PANEL_SIMPLE`,
       `DRM_SIMPLEDRM`, `FB_SIMPLE`, `BACKLIGHT_*`
   - Rebuilt kernel and re-signed FIT (juniper DTB).
   - Still black screen.

## Tries check: does the firmware boot the USB at all?

**Goal:** Find out whether the firmware even tries to boot the USB by checking whether the "Tries" counter on the kernel partition goes down.

### Method

This is the quickest way to tell the failure modes apart, and it gives a hard signal without needing a display or logs.

1. **Set Tries on the kernel partition:**
   ```bash
   sudo cgpt add -i 1 -S 1 -T 5 -P 15 /dev/sdX
   ```
   - `-S 1` = Success flag
   - `-T 5` = Tries (number of attempts)
   - `-P 15` = Priority

2. **Try to boot on the Chromebook:**
   - Insert the USB
   - Press `Ctrl+U` to boot from USB
   - Wait 30-60 seconds
   - Power off the Chromebook

3. **Check whether Tries has gone down:**
   - Put the USB back in the build machine
   - Run: `sudo cgpt show -i 1 /dev/sdX`
   - Note the value of "Tries"

### Interpretation

- **Tries goes down** → The firmware loads your kernel (the problem is "later": rootfs, DTB, display, etc.)
- **Tries does not change** → The firmware does not try to boot that partition (then it is almost always `dev_boot_usb`, the partition type, or that it rejects the image/signature)

### Next steps depending on the result

- **If Tries goes down:** Continue with a kernel build with built-in drivers, DTB validation, and a boot marker
- **If Tries does not change:** Focus on:
  1. Verify `crossystem dev_boot_usb=1` and `dev_boot_signed_only=0` (see [`chromeos-boot-config.md`](chromeos-boot-config.md))
  2. Check the partition type and GPT flags
  3. Verify the kernel signature

## Current hypothesis
The system likely fails **before** reaching systemd. Two primary candidates:
1. **Rootfs not mountable early**:
   - Required USB/SCSI/ext4/GPT drivers may be built as modules instead of built‑in.
2. **Display/panel init** still missing:
   - Even if kernel boots, no framebuffer might initialize.

## Next planned action (not yet executed)
- Rebuild kernel with **built‑in** rootfs drivers:
  - `DEVTMPFS`, `DEVTMPFS_MOUNT`, `SCSI`, `BLK_DEV_SD`,
    `USB`, `USB_XHCI_HCD`, `USB_STORAGE`, `EFI_PARTITION`,
    `PARTITION_ADVANCED`, `EXT4_FS` (+ ACL/SECURITY), `CRC16`, `CRC32`.
- Recreate FIT (juniper DTB), re‑sign, and test boot.
- If still black: test alternative DTB (`mt8183-kukui-jacuzzi-kenzo.dtb`).

## Solution (2026-10-27)
A new image (Debian trixie, Debian's kernel 6.12.113, an initramfs with all MT8183 modules, `mkdepthcharge` lzma) boots
to a login prompt on the internal screen. The cause of the black screens was the missing initramfs: the clock, USB,
MMC and display drivers are modules. See [`kernel-analysis.md`](../kernel-analysis.md).
Also: `crossystem` must be set from VT2, because the crosh shell blocks sudo.
