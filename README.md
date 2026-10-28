# Debian Linux for the Acer Chromebook 311 (CB311-11H)

Bare-metal Debian 13 (trixie, arm64) with an XFCE desktop for the **Acer Chromebook 311 CB311-11H / CB311-11HT**
(MediaTek MT8183, Google board *jacuzzi*, model *kenzo*). It uses Debian's own kernel and packages. Depthcharge, the
Chromebook's firmware, boots it from a USB stick, and an installer replaces ChromeOS on the internal eMMC if you
want that. No firmware flashing and no write-protect removal are needed.

> Running this means putting the Chromebook in Developer Mode, which **erases all local ChromeOS data**. The eMMC
> installer erases ChromeOS itself. You can always get ChromeOS back with a recovery USB stick (see below).

## What works

Tested on a CB311-11H (HWID `KENZO-IGRW`, firmware `Google_Juniper 12573.202.0`) with kernel 6.12 (Debian trixie).

| Part | Status |
|---|---|
| Display (eDP 1366×768), backlight | works |
| GPU (Mali-G72, panfrost) | works: Xorg with glamor acceleration |
| Wi-Fi (QCA6174, SDIO) | works, 2.4 and 5 GHz |
| Bluetooth (QCA6174, UART) | works (needs a firmware file Debian lacks; the build fetches it from ChromiumOS) |
| Keyboard, touchpad, volume keys | work |
| Battery and charging | work |
| CPU frequency scaling (793–1989 MHz), CCI and GPU devfreq | work |
| Speakers | work (stereo) |
| Internal microphone | works, mono with +20 dB software gain (the DMIC is quiet) |
| Suspend (deep): lid, power key, `systemctl suspend` | works; wakes on lid open or power key, Wi-Fi reconnects |
| Boot from USB (Ctrl+U) and from eMMC (Ctrl+D) | works |
| Kernel updates via apt | work: written to the spare kernel partition, with automatic fallback to the old one |
| Headphone jack | not tested yet; no automatic speaker/headphone switching (the UCM profile lacks jack controls) |
| SVS (voltage scaling) | not available (the upstream device tree lacks a `gpu-thermal` zone); not needed |

Other MT8183 Chromebooks (kukui, jacuzzi, kakadu, ...) may work with a different `DTB=`, but only kenzo is tested.

## 1. Prepare the Chromebook

1. **Make a ChromeOS recovery stick first** (8 GB or more): install the *Chromebook Recovery Utility* extension in
   Chrome on any computer and select *Acer Chromebook 311 (CB311-11H / CB311-11HT)*. This is your way back.
2. **Enter Developer Mode:** hold Esc + Refresh (↻) and press Power. At the recovery screen press Ctrl+D, then
   confirm. The Chromebook wipes itself and reboots into ChromeOS with a "OS verification is off" screen.
3. **Allow booting unsigned kernels from USB:** at the developer screen, let ChromeOS start, then switch to a text
   console with Ctrl+Alt+→ (the key above 2/3), log in as `chronos` (no password) and run:
   ```
   sudo crossystem dev_boot_usb=1 dev_boot_signed_only=0
   crossystem dev_boot_usb dev_boot_signed_only     # must print: 1 0
   ```
   (The crosh `shell` in the browser cannot use sudo on current ChromeOS.)

## 2. Build the image

You need a Linux machine (x86-64 or arm64) with Podman or Docker; the whole build runs in a container and needs no
loop devices or mounts. It takes 30–60 minutes, most of it running arm64 package scripts under qemu.

```bash
git clone https://github.com/olamellberg/chromebook-311-linux.git && cd chromebook-311-linux
sudo bash scripts/host-setup.sh      # once: qemu-aarch64 binfmt with the F flag (Debian/Ubuntu host)
build/image-build.sh                 # -> out/chromebook-debian-<date>.img.xz
```

Results in `out/`: `chromebook-debian-<date>.img.xz` (the whole USB stick, 8 GiB), `.kernel.img` (only the kernel
partition), `.txt` (kernel version, command line, partition GUIDs, package list) and `.sha256`.

**Building on another machine** (e.g. from Windows with Git Bash, onto a small Linux server):
```bash
BUILD_HOST=me@buildbox scripts/remote-build.sh build   # copies the tree, builds in the background (niced)
BUILD_HOST=me@buildbox scripts/remote-build.sh log     # follow the log (Ctrl-C stops following, not the build)
BUILD_HOST=me@buildbox scripts/remote-build.sh pull    # fetch the newest image and check its sha256
```
`remote-build.sh build` puts your `~/.ssh/id_ed25519.pub` into the image for root, so the Chromebook is reachable
over SSH from the first boot; set `SSH_AUTHORIZED_KEY=` (empty) to leave it out.

**Settings** are environment variables, for example `KEYBOARD_LAYOUT=de USER_NAME=anna build/image-build.sh`:

| Variable | Default | Meaning |
|---|---|---|
| `USER_NAME`, `USER_PASSWORD` | `user`, same as the name | desktop account (sudo); empty `USER_NAME` makes none |
| `ROOT_PASSWORD` | `debian` | root password |
| `PASSWORD_EXPIRED` | `1` | both passwords must be changed at the first login (root's not if `SSH_AUTHORIZED_KEY` is set, since an expired password also blocks key logins) |
| `KEYBOARD_LAYOUT` | `us` | XKB layout for console and desktop (`gb`, `de`, `se`, ...) |
| `SSH_AUTHORIZED_KEY` | none (`remote-build.sh`: your key) | public key for root over SSH (root never logs in over SSH with a password) |
| `EXTRA_PACKAGES` | | more Debian packages, space separated |
| `IMG_SIZE_MIB` | `8192` | size of the USB image |
| `SUITE`, `MIRROR` | `trixie`, deb.debian.org | Debian release and mirror |
| `DTB` | `mediatek/mt8183-kukui-jacuzzi-kenzo.dtb` | device tree (other MT8183 boards: untested) |
| `KERNEL_COMPRESS`, `KERN_SIZE_MIB`, `KERN_ATTRS`, `EXTRA_CMDLINE`, `IMG_COMPRESS` | see `build/make-image.sh` | kernel partition details |

## 3. Boot from USB

1. Write the `.img.xz` to a USB stick (8 GB or more; everything on it is erased): with Etcher or Rufus (DD mode), or
   `xz -dc chromebook-debian-*.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress`.
2. Plug it into the Chromebook, power on and press **Ctrl+U** at the developer screen.
3. Log in at the LightDM screen as `user` / `user` (or your `USER_NAME`). The default password has to be changed
   now: after the message "Changing password for user" the field asks for the **current** password once more, so
   type `user` again, then the new password twice (Enter after each). Root's password (`debian`) is expired the
   same way: `su -` in a terminal asks for a new one. Connect to Wi-Fi from the network icon in the panel.

## 4. Install on the eMMC (replaces ChromeOS)

Booted from the USB stick, open a terminal and run:
```bash
sudo install-emmc
```
It checks that it runs on a kenzo booted from USB, shows the eMMC and asks you to type `RADERA` ("erase"). Then it
erases the whole eMMC, creates two kernel partitions (KERN-A, KERN-B, 256 MiB each) and a root partition on the
rest, copies the running system, and writes a signed kernel with `depthchargectl`. It logs to
`/var/log/install-emmc.log`. Afterwards: power off, remove the stick, power on and press **Ctrl+D** (or wait 30 s).

**Kernel updates** need nothing manual: depthcharge-tools' hooks build a new kernel image after every kernel or
initramfs update and write it to the other kernel partition with one boot try. `depthcharge-tools.service` marks a
partition good once it has booted; if a new kernel fails to boot, the firmware falls back to the previous one. The
kernel command line is in `/etc/depthcharge-tools/config`.

The USB stick keeps working as a rescue system (Ctrl+U).

## Back to ChromeOS

Power off, hold Esc + Refresh (↻) and press Power, then insert the recovery stick. To leave Developer Mode, press
Space at the developer screen.

## Troubleshooting

- **Ctrl+U only beeps or does nothing:** `dev_boot_usb=1 dev_boot_signed_only=0` is not set (step 1.3).
- **Reboots after about 10 s:** the kernel panicked (`panic=10`), usually because it found no root filesystem.
  Boot ChromeOS or the USB system and read `/sys/fs/pstore/console-ramoops*` for the log of that boot.
- **`/var/log/boot-ok`** on the USB stick shows each boot that reached systemd, with its command line.
- **Kernel partition flags:** `cgpt show /dev/sdX` (USB) or `cgpt show /dev/mmcblk0`; `depthchargectl list` shows
  which partition booted and which is next.

## How it works

| File | Does |
|---|---|
| `build/Containerfile` | build container (Debian trixie): mmdebstrap, depthcharge-tools, vboot tools, cgpt |
| `build/make-image.sh` | in the container: rootfs (mmdebstrap), initramfs, signed FIT kernel (`mkdepthcharge`), ext4 (`mke2fs -d`), GPT image |
| `build/rootfs/` | files copied into the rootfs: initramfs module list, Xorg, PipeWire, WirePlumber and logind settings, `install-emmc` |
| `build/fetch-firmware.py` | fetches the Bluetooth NVM file Debian lacks, pinned by sha256 |
| `build/image-build.sh` | any Linux host: builds the container and runs `make-image.sh` |
| `build/background-build.sh`, `scripts/remote-build.sh` | run the build in the background / on another machine |
| `scripts/host-setup.sh` | one-time root setup of the build host (qemu-aarch64 binfmt) |
| `docs/kernel-analysis.md` | which drivers kenzo needs and why the initramfs is essential |
| `docs/history/` | notes from earlier attempts |
| `HANDOFF.md`, `tasks/` | working notes (partly Swedish): current state, plan, lessons learned |

The key points: the Debian kernel has every needed driver, but the clocks, USB, MMC and display drivers are modules,
so an initramfs with the right module list (`build/rootfs/etc/initramfs-tools/modules`) is essential. Depthcharge
boots a FIT image (kernel + initramfs + DTB) signed with the vboot developer keys, from a GPT partition of type
"ChromeOS kernel". See `docs/kernel-analysis.md` for the details.

## Credits

- [depthcharge-tools](https://github.com/alpernebbi/depthcharge-tools) (Alper Nebi Yasak): `mkdepthcharge`,
  `depthchargectl` and the board database.
- [postmarketOS](https://postmarketos.org) for showing that mainline Linux works
  on kukui/jacuzzi, and Debian's MT8183 work (salsa.debian.org merge request !906) for the module soft dependencies.
- The ChromiumOS project for the Bluetooth firmware and the UCM/audio reference.

## License

MIT, see `LICENSE`. Debian packages and firmware in the built image keep their own licenses.
