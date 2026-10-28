# HANDOFF

Uppdaterad 2026-10-28.

## Läge (2026-10-28): Debian med XFCE är installerat på eMMC, ChromeOS är borta
- **eMMC** (`/dev/mmcblk0`, 58 GB): KERN-A och KERN-B på 256 MiB vardera, ROOTFS mmcblk0p3 (57 GB), installerat med
  `install-emmc` från USB-stickan. Boot: Ctrl+D på utvecklarskärmen (eller vänta 30 s). Ctrl+U bootar fortfarande USB.
- **Kärnuppdateringar:** depthcharge-tools system-hooks bygger en ny image vid varje kärn- eller initramfs-uppdatering
  och skriver den till den andra KERN-partitionen (tries=1); `depthcharge-tools.service` (`depthchargectl bless`)
  markerar den bootade som lyckad. Kommandoraden kommer från `/etc/depthcharge-tools/config` (skriven av
  `install-emmc`), root= från fstab. boot-marker är avstängd på eMMC (den markerar alltid partition 1).
- **Återställning:** ChromeOS-återställningssticka (Chromebook Recovery Utility, kenzo) finns hos användaren:
  Esc+Uppdatera+Power. USB-stickan har image 20261028-0635 plus live-ändringar och bootar med Ctrl+U.
- Användarkonto (sudo); SSH `root@<chromebook-ip>` med PC:ns nyckel.
- Bygget har ändringar som inte är ombyggda: e2fsprogs, rtkit, `etc/locale.conf` och den rättade `install-emmc`.

## Historik
- Byggmiljön är flyttad från WSL2 (trasig: VT-x av) till en projektspecifik container på NUC:en, se `README.md`.
  Alla gamla försök (egen 6.6-kernel, ingen initramfs) gav svart skärm; se `docs/history/error-log.md`.

## Första bygget (2026-10-27): `out/chromebook-debian-20261027-2107.*`
- Host-setupen är gjord (qemu-aarch64 binfmt, flaggor POF). Bygget tog 25 min på NUC:en.
- Alla 31 initramfs-moduler finns med. vboot-signaturen är giltig (devkeys).
- FIT: kernel lzma 9,3 MiB, kenzo-DTB, ramdisk 36 MiB, totalt 47,6 MiB. KERN-A är 128 MiB med S=0 T=15 P=15.
- I rootfs: fstab (PARTUUID), softdeps, ath10k-firmware för SDIO, boot-marker, NetworkManager.
- **Bootar på enheten (2026-10-27):** Ctrl+U → login-prompt på den interna skärmen, inloggning som root fungerar.

## Hårdvarustatus (2026-10-27, SSH `root@<chromebook-ip>` med PC:ns nyckel; lösenordsinloggning avstängd)
| Del | Status |
|---|---|
| Skärm eDP 1366×768, bakgrundsbelysning | fungerar |
| Wi-Fi (QCA6174 SDIO, ath10k) | fungerar, 5 GHz. `wireless-regdb` tillagt |
| Tangentbord, touchpad, volymknappar | fungerar (svensk konsollayout via console-setup) |
| Batteri och laddning (cros-ec, sbs) | fungerar |
| GPU (panfrost, Mali-G72) | fungerar: Xorg glamor på Mali-G72. Xorg behöver `etc/X11/xorg.conf.d/20-mediatek.conf` (PrimaryGPU på mediatek-drm), annars "Cannot run in framebuffer mode" |
| CPU-frekvens, CCI, GPU devfreq | fungerar: `governor_passive` + `mediatek-cpufreq` i modules-load.d (autoladdas aldrig); 793–1989 MHz, CCI passive, GPU simple_ondemand |
| Bluetooth (QCA6174 UART) | fungerar (sökning: 15 enheter) med ChromeOS `nvm_00440302_i2s.bin`; `_i2s_eu` från Debian ger HCI-timeouts. Bygget hämtar filen (`build/fetch-firmware.py`, sha256-pinnad). Enstaka "Frame reassembly"-varningar |
| SVS (spänningsoptimering) | ger upp: DT saknar termisk zon `gpu-thermal` (lucka i upstream-DT). Inte nödvändig |
| Ljud: högtalare | fungerar, båda kanaler (Debians alsa-ucm-conf har profilen mt8183_mt6358_ts3a227_max98357: verb HiFi, Speaker via I2S3 → max98357a) |
| Ljud: inbyggd mikrofon | fungerar (DMIC, UCM "Mic"). Bara FL har signal, låg nivå (−42 dBFS vid tal). PipeWire-källan "Inbyggd mikrofon" (`etc/pipewire/pipewire.conf.d/50-internal-mic.conf`) tar FL, +20 dB, mono, standardkälla |
| Ljud: profil | UCM saknar JackControl, så WirePlumber valde hörlurar+headset. `etc/wireplumber/wireplumber.conf.d/50-mt8183-profile.conf` föredrar "HiFi (Mic, Speaker)". Jack-kontrollerna finns i ALSA (`Headphone Jack`, `Headset Mic Jack`): en UCM-fix ger automatisk växling senare |
| Skrivbord | XFCE + LightDM + PipeWire, ett användarkonto (sudo m.fl.). Installerat live; bygget har paketen och kontot (USER_NAME/USER_PASSWORD, standard user/user) |
| Ljud: hörlurar | inte testat (inga hörlurar till hands) |
| Suspend/resume (deep) | fungerar: `rtcwake -m mem -s 20` sov 20 s och vaknade (suspend_stats success=1 fail=0). Wi-Fi, BT, alla 8 kärnor och bakgrundsbelysning tillbaka. SDIO-kortet initieras om vid resume (msdc-varningar, ofarligt). Locket och strömknappen fungerar (2026-10-28): `etc/systemd/logind.conf.d/50-chromebook.conf`, lock och kort tryck söver (deep), långt tryck stänger av; väcks av lock och strömknapp, Wi-Fi återansluter |
| pstore | depthcharge lägger in ramoops (1 MiB), så det fungerar |
| vboot tries | räknas ner på USB (15 → 14), boot-marker satte S=1 |

Alla fixar på stickan finns också i bygget (`build/rootfs/`, `build/make-image.sh`), men är inte ombyggda och testade som en ny image.

## Nästa steg
1. Klart: andra omstarten verifierad. Bluetooth, CCI, GPU devfreq och cpufreq fungerar direkt vid boot, och inga enheter väntar (devices_deferred tom).
2. Klart: ljud, suspend/resume (rtcwake), XFCE-skrivbord. Kvar: hörlurar (UCM JackControl), lock/strömknapp-suspend.
3. Bygg om imagen med fixarna (`scripts/remote-build.sh build`, nu 8 GiB med XFCE) och verifiera den från noll. Stickan har bara 945 MB ledigt (rootfs 3,8 GB).

## Erfarenheter från första booten
- crosh `shell` blockerar sudo i nyare ChromeOS ("no new privileges"). `crossystem` måste köras i VT2
  (Ctrl+Alt+→, login `chronos`).
- `dev_boot_usb=1 dev_boot_signed_only=0` måste vara satt. Med standardvärdena (0 1) bootar Ctrl+U inte.

## Research klar (2026-10-27): `docs/kernel-analysis.md`
- Debian 6.12.113 har alla drivrutiner kenzo behöver, men kärnan i bootkedjan är moduler (klockor, USB/MTU3, MMC, display).
  Initramfs-listan bygger nu på en kartläggning DTB → `modules.alias`, och softdeps kommer från Debian MR !906.
- vmlinuz är en vanlig Image (36 MiB), kenzo-DTB:n finns, och firmware för Wi-Fi, BT och SCP finns i trixie-paketen.
- postmarketOS kör mainline på kenzo och allt testat fungerar. Vi använder lzma som de gör.

## Ej verifierat
- Om depthcharge lägger in en ramoops-region (DTB:n har ingen), alltså om pstore-diagnostiken fungerar.
- Den kända Debian-instabiliteten (i2c_mt65xx som hänger sig ibland, cros_ec_keyb som inte laddas).
- Att vboot räknar ner Tries på USB-media.
