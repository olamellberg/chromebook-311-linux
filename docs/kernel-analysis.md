# Debian trixie kernel vs. the kenzo device tree

Analysed 2026-10-27 on the build host in the build container: `linux-image-6.12.113+deb13-arm64`, `firmware-mediatek`
and `firmware-atheros` (trixie) extracted with `dpkg-deb -x`. Every enabled node of
`mt8183-kukui-jacuzzi-kenzo.dtb` (model "Google kenzo sku17 board") was mapped to a driver through `modules.alias` and
`modules.builtin.modinfo`. The scripts used are not in the repo; the method is: `dtc -I dtb -O dts`, then match
`of:NxTxC<compatible>` against the alias patterns.

## Kernel
- `vmlinuz` is a plain arm64 `Image` (36 MiB), not EFI zboot. `mkdepthcharge --compress lz4` packs it as it is.
- The kenzo DTB is in the package (`/usr/lib/linux-image-<ver>/mediatek/`), along with all jacuzzi/kukui variants.
- Built in (`=y`): `ARCH_MEDIATEK`, `MTK_PMIC_WRAP`, `MFD_MT6397`, `REGULATOR_MT6358`, `MTK_SCPSYS_PM_DOMAINS`,
  `SERIAL_8250_MT6577`, `FB_SIMPLE`, `FRAMEBUFFER_CONSOLE`, `PSTORE`.
- **Modules (`=m`) that the boot depends on**: `COMMON_CLK_MT8183` (all MT8183 clock drivers), regulator-fixed,
  `USB_MTU3` (the xhci node is its child), `USB_XHCI_MTK`, `PHY_MTK_TPHY`, `USB_STORAGE`, `EXT4_FS`, `MMC_MTK`.
  None of these exist without an initramfs. The old WSL builds had none, and that is the most likely cause of the
  black screens ([`history/error-log.md`](history/error-log.md)).
- Display, all modules: `DRM_MEDIATEK`, `DRM_ANALOGIX_ANX7625`, `DRM_PANEL_EDP`, `PWM_MTK_DISP`, `BACKLIGHT_PWM`,
  `MTK_IOMMU`, `MTK_SMI`, `MTK_MMSYS`, `MTK_CMDQ`. The DT has no simple-framebuffer, so nothing reaches the screen
  before `mediatek-drm` + `anx7625` + `panel-edp` have loaded.
- `PSTORE_RAM=m`, and the DTB has no ramoops node. Whether depthcharge adds one at boot is not verified.

## Hardware ↔ driver (from the DTB)
| Function | DT node / compatible | Driver |
|---|---|---|
| Panel | `dsi@14014000` → `anx7625@58` (i2c@11008000) → `edp-panel`, `pwm-backlight` | mediatek-drm, anx7625, panel-edp, pwm_bl |
| USB | `mediatek,mt8183-mtu3` → `mediatek,mt8183-xhci` → hub `usb5e3,610` | mtu3, xhci-mtk-hcd, onboard_usb_dev |
| eMMC / SD | `mediatek,mt8183-mmc` | mtk-sd |
| Wi-Fi | `qcom,ath10k` on mmc@11240000 (SDIO), `qcom,ath10k-calibration-variant = "GO_JUNIPER"` | ath10k_sdio (QCA6174) |
| Bluetooth | `qcom,qca6174-bt` on serial@11003000 | hci_uart (btqca) |
| Keyboard, battery, Type-C | `google,cros-ec-spi` on spi@11012000 | cros_ec_spi, cros_ec_keyb, sbs_battery, cros_ec_typec |
| Touchpad | `elan,ekth3000` / `hid-over-i2c` | elan_i2c, i2c_hid_of |
| Audio | `mediatek,mt8183_mt6358_ts3a227_max98357` | mt8183-mt6358-ts3a227-max98357 + snd-soc-mt8183-afe |
| GPU | `mediatek,mt8183b-mali` | panfrost |
| TPM | `google,cr50` (SPI) | tpm_tis_spi |

## Firmware
- Wi-Fi: `ath10k/QCA6174/hw3.0/firmware-sdio-6.bin` and `board-2.bin` are in `firmware-atheros`. `board-2.bin`
  contains the `GO_JUNIPER` variant.
- Bluetooth: `qca/rampatch_00440302.bin`, `qca/nvm_00440302.bin` (`firmware-atheros`).
- SCP (video codec, cros-ec-rpmsg): `mediatek/mt8183/scp.img` (`firmware-mediatek`). Not needed to boot.

## What others run on this board (web research 2026-10-27)
- **postmarketOS** (the wiki now redirects to Nura, wiki.nura.eco). The kenzo page
  ([wiki](https://wiki.nura.eco/wiki/Acer_Chromebook_311_(CB311-11H_/_CB311-11HT)_(google-kenzo))) is part of the
  `google-kukui` port and says "Mainline: yes". Screen, keyboard, touchpad, 3D, audio, Wi-Fi, BT, USB-A and battery
  all work. Audio is partial for the family: no jack detection.
  [deviceinfo](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/raw/main/device/community/device-google-kukui/deviceinfo):
  depthcharge, **lzma**, 32 MiB kernel partition, cmdline `quiet loglevel=2`. Its kernel builds the whole display
  path in (DRM_MEDIATEK, ANX7625, MIPI DSI PHY, PANEL_EDP, PWM, CROS_EC_SPI, I2C_MT65XX, MMC_MTK).
  Firmware it ships: ath10k, mediatek, qca, `alsa-ucm-conf-cros`.
- **Collabora LAVA / KernelCI** tests `mt8183-kukui-jacuzzi-juniper-sku16` with mainline kernels: depthcharge, a FIT
  image built by mkimage, a ramdisk, and `console=tty1` + `console=ttyS0,115200n8`
  ([template](https://gitlab.com/lava/lava/-/raw/master/etc/dispatcher-config/device-types/mt8183-kukui-jacuzzi-juniper-sku16.jinja2)).
  Collabora notes that ANX7625 has to be built in when there is no initramfs
  ([patch](https://lkml.iu.edu/hypermail/linux/kernel/2403.0/05334.html)).
- **Debian work by the depthcharge-tools author** ([MR !906](https://salsa.debian.org/kernel-team/linux/-/merge_requests/906),
  tested on cozmo): the display and USB modules must be in the initramfs (initramfs-tools !85–!87, merged), plus
  `softdep` load order (`build/rootfs/etc/modprobe.d/mt8183.conf`). Known problems: some boots stall until
  `i2c_mt65xx` is loaded again, and `cros_ec_keyb` sometimes does not load. The MT6358 regulator had to become
  built-in ([LKML](https://lkml.rescloud.iu.edu/2412.2/09081.html)); it is `=y` in 6.12.113.
- **Regression to avoid**: the display fails on 6.18-rc7 on krane ("Invalid display hw pipeline"), and 6.17.9 works
  ([LKML](https://lkml.iu.edu/2511.3/02952.html)). Debian 6.12 is not affected. Keep this in mind for backports kernels.
- Arch Linux ARM: only black-screen reports, with the wrong (oak) kernel. Nothing found for Fedora, Ubuntu or Eupnea.

## Conclusion for the build
Debian 6.12 has every driver this board needs. Because the display, clock, USB and MMC drivers are modules, the
initramfs carries the whole boot, and `build/rootfs/etc/initramfs-tools/modules` lists them explicitly. The old WSL
images had no initramfs, which matches their black screens. If Debian's modular stack turns out flaky (the
i2c_mt65xx stall), fall back to a kernel with postmarketOS's built-in display config (`legacy/` route, committed config).
