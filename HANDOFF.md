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
  Esc+Uppdatera+Power. USB-stickan har image 20261028-1131 (publika standardvärden) och bootar med Ctrl+U.
- Användarkonto (sudo); SSH `root@<chromebook-ip>` med PC:ns nyckel.
- Publikt repo: https://github.com/olamellberg/chromebook-311-linux (`main`).
- **Image 20261028-1131 testad från USB:** `user`/`user` tvingar fram nytt lösenord i LightDM (efter "Changing
  password for user" frågar fältet efter det nuvarande lösenordet igen), layout `us`, `LANG=C.UTF-8`, glamor,
  högtalare och `internal_mic` som standard. Fel: utgånget root-lösenord stoppade även SSH-nyckelinloggning;
  rättat i `make-image.sh` (root går inte ut när `SSH_AUTHORIZED_KEY` är satt), inte ombyggt.
- **Bluetooth kraschar ofta, ej löst (felsökning pausad 2026-10-29).** Se avsnittet "Bluetooth: felsökning" nedan.
  Efter en krasch sparar systemd-rfkill soft=1 (`/var/lib/systemd/rfkill/platform-11003000.serial:bluetooth`) och
  lägger tillbaka blocket vid nästa boot: `echo 0 > /sys/class/rfkill/rfkillN/soft` (typ `bluetooth`) häver det.
- **USB-stickan har testrester** från BT-felsökningen: `/etc/apt/sources.list.d/backports.list`, paketet
  linux-image-7.2.11+deb13-arm64 (dess depthcharge-hook skriver om `/dev/sda1` vid kärnuppdateringar) och
  `/root/bt-test/` (testkärnor och DTB:er). KERN-A är återställd till originalkärnan från 1131 (6.12). Allt försvinner
  när stickan flashas med nästa image.

## Bluetooth: felsökning (2026-10-29, pausad)
QCA6174 (ROME) på UART1 (`serial@11003000`, serdev `serial0-0`, `hci_uart_qca`), bt_en = pio 120 (gpio-632).

**Symptom:** setupen blir klar ("QCA setup on UART is completed"), alla små HCI-kommandon efteråt går igenom, men det
första kommandot med ett stort svar (`0x0c14` Read Local Name, cirka 255 byte, ibland `0x1002`, cirka 68 byte) får
tx timeout. Sedan "crash the soc", memdump med hundratals "missed packet" och `Frame reassembly failed (-84)`.

**Vad som är visat:**
- Det händer på **varje** setup med en nystartad krets (efter `qca_power_off`, efter bt_en låg i 1 s för hand eller
  vid kall start), även med nytt drivrutinstillstånd (unbind/bind). Setup som "fungerar" är nästan alltid en krets som
  redan körde firmware från förra sessionen (rampatchen "laddas" då på några ms, vilket är för snabbt för 68 kB).
  Auto-off 2 s efter boot-setupen och av/på i blueman eller bluetoothctl ger alltså nästan alltid en krasch.
- UART-räknaren (`/proc/tty/driver/serial`, raden för 11003000) visar `oe:` (overrun) i samma ögonblick: en setup
  med 594 mottagna byte gav `oe:1`, och det tappade svaret är det långa paketet. H4-parsern väntar på resten, alltså
  timeout. Grundorsaken är att RX-vägen tappar byte i PIO-läge (8250_mtk, ingen DMA, ST16650V2-FIFO).
- Det är **inte** hastigheten: overruns och krascher finns på 3M, 2M och 1M (1M: `oe:4` på 588 byte, vilket
  är omöjligt med vanlig avbrottslatens). Det är inte heller fbcon-loggning: `ignore_loglevel=N` och `dmesg -n 1` gav
  samma krasch.
- Det är **inte** kärnversionen (Debian 7.2.11 från trixie-backports beter sig likadant) och inte firmware:
  rampatchen i Debian är byte-identisk med ChromeOS, NVM-filen är ChromeOS egen, och NVM:s HCI-tagg har rätt baudkod
  (0x0e = 3M). DT-noden (bluetooth, clk32k) är identisk med ChromeOS 6.6, och ChromeOS hci_qca/btqca skiljer sig
  bara med backports. ChromeOS har inte heller DMA på uart1.
- 115200 baud går inte att testa: ROME-patchen skickas utan svar per segment, och 68 kB tar cirka 6 s, så HCI-kärnans
  kommandotimer (2 s) löper ut.
- Utan `enable-gpios` (bt_en alltid hög via pinctrl `output-high`) laddas firmware bara en gång per boot. Men en
  hängd krets kan då aldrig nollställas, och av/på kraschade ändå på `0x0c14`. Det är ingen lösning.
- APDMA (UART-DMA, upstream-nod i commit `5551862f57e5`, v7.3-rc1) med 6.12-drivrutinen: firmware-nedladdningen
  får tx timeout, "flush: fail" och "Runtime PM usage count underflow".

**Nästa steg:** testa APDMA med 7.2-kärnan. Testkärnan finns på stickan som `/root/bt-test/kernel-a72.img`
(7.2-DTB + nod `dma-controller@11000780`, phandle 0xac, interrupts `0 6c 8 … 0 71 8` mot sysirq, clocks
`<0x2b 0x2a>` = infracfg CLK_INFRA_AP_DMA, uart1 `dmas = <0xac 2 0xac 3>`). Skriv den till KERN-A med `dd`, boota med
Ctrl+U och kör av/på-stresstestet; räkna `oe:` och setuper. Fungerar det blir lösningen backports-kärnan plus
DTB-patch i bygget (och en hook så att depthchargectl använder den patchade DTB:n vid kärnuppdateringar). Annars:
en fråga till linux-mediatek / linux-bluetooth med spåret ovan.

Hjälpmedel: `echo "file hci_qca.c +pt; file hci_h4.c +pt" > /sys/kernel/debug/dynamic_debug/control` ger IBS- och
H4-spår; `/sys/kernel/debug/bluetooth/hci0/ibs/` visar IBS-tillståndet. Nollställ kretsen för hand: unbind
`serial0-0`, `gpio-632` låg 1 s (sysfs export), bind.

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
| Bluetooth (QCA6174 UART) | opålitlig: kraschar efter setup med nystartad krets (RX-overruns), se "Bluetooth: felsökning". Bygget hämtar ChromeOS `nvm_00440302_i2s.bin` (`build/fetch-firmware.py`, sha256-pinnad); att `_i2s_eu` "gav HCI-timeouts" var troligen samma fel |
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
