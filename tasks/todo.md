# Plan: Bare-metal Linux på Acer CB311-11H (MT8183, jacuzzi/kenzo)

Uppdaterad 2026-10-27.

## Läget
- Alla bootförsök hittills: svart skärm efter Ctrl+U, ingen journal. Vi vet fortfarande inte om depthcharge laddar kerneln.
- WSL2 startar inte (VT-x avstängt). Bygget har flyttats till en container på NUC:en, se Fas 0.
- `~/Downloads/chromebook-debian.img` (från 2026-03-15) finns inte längre. Den ligger förhoppningsvis kvar som `~/chromebook-debian.img` i WSL-VHDX:en.
- Mars-imagen (6.6.120, kenzo-DTB, display/USB/ext4 inbyggt) har troligen aldrig testats.

## Fel i den nuvarande metoden
1. **Tries-testet i error-log.md kan inte fungera.** Med `-S 1` räknar vboot aldrig ner Tries. Testet måste köras med `-S 0 -T 5` (det är också osäkert om vboot skriver till GPT på USB-media).
2. **Egenbyggd kernel utan initramfs.** Allt som behövs för att nå rootfs (xhci-mtk, tphy, scpsys, mt6358-regulatorer, ext4) måste vara inbyggt. Ett enda saknat beroende ger svart skärm utan någon logg.
3. ~~Okomprimerad FIT för stor~~: avfärdat. depthcharge-tools anger max 512 MiB för kukui.
4. **Vi felsöker blint.** Inget av försöken ger en tydlig signal om vad som gick fel.

## Plan

### Fas 0: Byggmiljö (klar 2026-10-27, utom root-setupen)
WSL2 är inte längre byggmiljön. Allt byggs i en projektspecifik container på en byggdator (här en liten server) (se `README.md`).
- [x] `build/Containerfile`, `build/make-image.sh`, `build/image-build.sh`, `build/background-build.sh`, `scripts/remote-build.sh`
- [x] Containern byggd på NUC:en; mmdebstrap (root-läge i rootless Podman), `mke2fs -d` och cgpt verifierade med en amd64-testrootfs
- [x] Användaren kör `ssh -t me@buildbox 'sudo bash -s' < scripts/host-setup.sh` (qemu-aarch64 binfmt med F-flagga)
- [x] Första arm64-bygget: 25 min, `out/chromebook-debian-20261027-2107.*`
- [ ] (Valfritt) VT-x i BIOS: behövs inte längre för bygget, bara om WSL ska användas igen. Hämta i så fall ut `~/linux`-konfigurationen till `legacy/`

### Fas 1: Testa bootkedjan med en image som redan fungerar (cirka 30 min, kan göras parallellt med Fas 0)
- [ ] Ladda ner en färdig postmarketOS-image för `google-kukui` (kenzo: "Mainline: yes", allt testat fungerar enligt wikin, se `docs/kernel-analysis.md`) och flasha den med Rufus i DD-läge eller med Etcher
- [ ] I ChromeOS-shell: `crossystem dev_boot_usb dev_boot_external dev_boot_signed_only`. Sätt `dev_boot_usb=1` och `dev_boot_signed_only=0`
- [ ] Ctrl+U:
  - **pmOS bootar och visar bild** → firmware, inställningar och hårdvara fungerar. Felet ligger i vår image. Gå till Fas 2.
  - **pmOS ger också svart skärm eller pip** → felet ligger i firmware eller inställningar. Felsök crossystem och USB-port (testa en annan port eller en annan sticka).

### Fas 2: Debian-image med Debians kernel (byggskriptet är klart, inte testat på enheten)
Debian 13 (trixie) med kernel 6.12, initramfs-tools och `mkdepthcharge` från depthcharge-tools. Kenzo finns i verktygets `boards.ini` (HWID KENZO-IGRW): FIT, lz4/lzma, FIT-ramdisk stöds, max 512 MiB. Teorin om en kernelbuffert på 32 MiB stämmer alltså inte.
- [x] `build/make-image.sh`: mmdebstrap trixie arm64 + linux-image-arm64 + firmware (mediatek, atheros, misc-nonfree) + NetworkManager
- [x] Kernelpartition via `mkdepthcharge` (lzma som pmOS, 128 MiB, kenzo-DTB, `root=PARTUUID=… rootwait panic=10`)
- [x] KERN-A skrivs med `-S 0 -T 15 -P 15`; `boot-marker.service` sätter S=1 och skriver `/var/log/boot-ok`
- [x] Initramfs-moduler och softdeps härledda från kenzo-DTB + Debians `modules.alias` (`docs/kernel-analysis.md`)
- [x] Kontroll i bygget av vilka initramfs-moduler (USB, eMMC, EC-tangentbord, panel) som faktiskt finns med (`.txt`-filen)
- [x] Första bygget: inga saknade moduler, giltig signatur, FIT 47,6 MiB
- [x] Flasha och boota med Ctrl+U: **bootar till login-prompt** (2026-10-27)
- [ ] Senare: depthcharge-tools i målsystemet, så att kernel-uppdateringar skriver KERN-A automatiskt

Reservspår: egen kernel med pmOS-konfigurationen för kukui (`linux-postmarketos-mediatek-mt8183`); konfiguration och patchar committas i repot.

### Fas 3: Diagnostik om skärmen fortfarande är svart
- [ ] **Panic-reboot-test:** med `panic=10` ska enheten starta om efter cirka 10 sekunder om kerneln kör men inte hittar rootfs. Startar den om har kerneln kört. Står den still svart har kerneln hängt sig tidigt, eller så laddades den aldrig.
- [ ] **pstore/ramoops:** efter en panik och varm omstart, boota ChromeOS med Ctrl+D och kör `cat /sys/fs/pstore/console-ramoops*`. Då syns förra bootens kernellogg.
- [ ] **Tries:** `cgpt show -i 1 /dev/sdX` efter försöket (imagen har redan S=0)
- [x] **Bootmarkör:** inbyggd i imagen (`/var/log/boot-ok`, läsbar från ChromeOS)
- [ ] **Sista utväg:** köp en SuzyQable (USB-C CCD-kabel), som ger AP-UART-konsol. Då får vi riktig seriell logg.

### Fas 4: Få hårdvaran att fungera
- [x] Wi-Fi, tangentbord och touchpad, ljud (högtalare, mikrofon), batteri, suspend (rtcwake) och bakgrundsbelysning (se HANDOFF.md)
- [ ] Hörlurar (UCM saknar JackControl)
- [ ] Bluetooth kraschar ibland vid boot efter andra QCA-setupen (tx timeout, memdump), se HANDOFF.md. Undersök:
      lägre `max-speed` för UART:en (DT-overlay; bitfel syns även när BT fungerar), att undvika auto-off mellan
      kärnans setup och bluetoothd. Efter en krasch sparar systemd-rfkill ett soft-block som ligger kvar efter omstart
- [x] Lock och strömknapp för suspend (logind-drop-in, testat 2026-10-28: suspend_stats success=2 fail=0)
- [x] Skrivbordsmiljö: XFCE + LightDM + PipeWire (2026-10-28), användarkonto; Xorg-, WirePlumber- och mikrofonkonfig i build/rootfs

### Fas 5: Installation på eMMC i stället för ChromeOS (beslut 2026-10-28: "installera debian över chromeos")
ChromeOS KERN-partitioner är 32 MiB, och depthchargectl bygger en 91 MB-image (okomprimerad; `compress` går bara att
sätta som argument). En ny GPT behövs alltså: KERN-A och KERN-B på 256 MiB vardera, ROOTFS på resten (cirka 57 GB).
- [x] `depthcharge-tools` i imagen: system-hooks skriver om kärnpartitionen vid kärn- och initramfs-uppdateringar, bara på disken som håller `/` (verifierat: `depthchargectl list` visar bara /dev/sda på stickan). `depthchargectl bless` (depthcharge-tools.service) markerar den bootade partitionen
- [x] `install-emmc` (build/rootfs/usr/local/sbin): kontroller (kenzo, depthcharge-boot, rot inte på eMMC), skriv RADERA, blkdiscard, ny GPT, ext4, tar-kopia av /, fstab, boot-marker av, depthchargectl write till KERN-A, kontroll av root=PARTUUID i den signerade kärnan
- [x] Ny image 20261028-0635 (8 GiB, XFCE, depthcharge-tools) byggd, flashad (byte-identisk) och verifierad från noll: X/glamor, högtalare, "Inbyggd mikrofon" som standard, BT, bless. Saknade e2fsprogs (nu i bygget, plus rtkit)
- [x] Testkörning av `install-emmc` mot en loop-enhet i tmpfs: EXIT=0, GPT A/B/ROOTFS, KERN-A P=1 T=1 S=0, fstab och kärnans root= samma PARTUUID, cmdline från målets /etc/depthcharge-tools/config (utan den blev cmdline bara root=), setuid kvar
- [x] Användaren gör ett ChromeOS-återställningsmedium (Chromebook Recovery Utility, kenzo) **innan** eMMC skrivs; kräver en andra USB-sticka eller att stickan skrivs om efteråt
- [x] Omstart från stickan med kärnan som depthchargectl skrev automatiskt (okomprimerad, 91 MB, två DTB): bootar
- [x] `install-emmc` på riktigt (2026-10-28; första försöket avbröts efter tar, se lessons.md). Bootar från eMMC med Ctrl+D, rot mmcblk0p3, KERN-A blessad
- [x] Kärnuppdatering: `depthchargectl write` skrev KERN-B (P=2 T=1 S=0), KERN-A kvar som reserv (P=1 S=1)
- [x] Omstart: KERN-B bootade (kern_guid 9e65b72b…) och blessades (P=2 S=1), KERN-A kvar som reserv (P=1 S=1)
- [x] `/etc/default/locale` är en länk till `/etc/locale.conf` (systemd), så LANG ligger nu i `build/rootfs/etc/locale.conf`

## Granskning
(fylls i efter genomförande)
