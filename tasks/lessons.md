# Lessons

- **vboot only counts down Tries when the success flag is 0.** The Tries test in docs/history/error-log.md used `-S 1`, so it
  could never show anything. Diagnostic images are written with `-S 0`, and Linux sets `S=1` itself (boot-marker).
- **Check the depthcharge-tools board DB before guessing at firmware limits.** `boards.ini` has kenzo (HWID
  KENZO-IGRW): FIT, lz4/lzma, FIT ramdisk supported, max image 512 MiB. The 32 MiB kernel buffer theory was wrong.
- **Work that lives only in WSL is lost when WSL breaks** (VT-x off, 2026-08). Same lesson as elsewhere:
  everything that makes the image is in this repo, and the build runs in a container on any host.
- **One unknown at a time.** Six black-screen attempts each changed several things (kernel config, DTB, cmdline)
  without a signal that told the failure stages apart. Every image now carries its own diagnostics.
- **Check what the distro kernel actually builds, not what upstream defconfig does.** Debian builds the MT8183 clocks,
  USB, MMC and the whole display path as modules, so for this board the initramfs *is* the boot. Map the DTB to
  `modules.alias` (docs/kernel-analysis.md) before guessing module lists.
- **Drivers that match the DT root never autoload.** mediatek-cpufreq matches the machine compatible, which sends no uevent,
  so udev never loads it, and ccifreq/svs defer forever. Look at `/sys/kernel/debug/devices_deferred` after the first boot.
- **crosh `shell` cannot sudo on current ChromeOS.** Use VT2 (Ctrl+Alt+→, `chronos`) for `crossystem`. Give the user
  commands that avoid characters that are hard to find on a US layout, or set the layout first.

## mmdebstrap minbase har inte e2fsprogs (2026-10-28)
- `--variant=minbase` tar bara Priority required. e2fsprogs är "important", så `mkfs.ext4`, `fsck.ext4` och `resize2fs`
  saknades i imagen, och roten kontrollerades aldrig med fsck vid boot. Lista uttryckligen allt som körs vid boot eller av
  egna skript, och kör skripten i den byggda imagen innan de anses klara.
- Imagen har inga apt-listor (mmdebstrap tar bort dem): `apt-get update` först, annars "no installation candidate",
  vilket är lätt att läsa som att paketet inte finns i Debian.

## Testa kopieringsskript med testmålet utanför källan (2026-10-28)
- `install-emmc` mot en loop-fil i `/var/tmp` kopierade loop-filen in i sig själv (`tar --one-file-system` ser den som en
  vanlig fil på /). Uteslut testmålets backing-fil, och räkna med att läsa och skriva samma USB-sticka är mycket
  långsamt (cirka 1 MB/s, timmar för 1,6 GB).
- `pkill -f <namn>` över ssh matchar också ssh-sessionens egen `bash -c`. Döda på PID.

## Kopiering av ett levande system: testa med samma last (2026-10-28)
- `install-emmc` klarade testet men avbröts på riktigt direkt efter `tar` (fstab och kärnan skrevs aldrig). Skillnaden: en
  inloggad XFCE-session som ändrar filer under kopieringen. tar ger då exit 1 ("file changed as we read it") eller 2
  (fil borta), och `set -euo pipefail` avbryter. Godta exit 1 från den läsande tar och uteslut cacher och temp-kataloger.
- Skript som användaren kör i en terminal ska logga till fil (`exec > >(tee -a LOG) 2>&1`): utskriften i terminalen går
  inte att få tillbaka efteråt.

## Bluetooth-felsökning: mät kretsens tillstånd innan en hypotes testas (2026-10-29)
- En varm omstart, avstängning och EC-reset nollställer inte BT-kretsen (bt_en ligger kvar hög). En "fungerande" boot
  var oftast en krets med firmware kvar från förra sessionen. Nollställ den för hand (bt_en låg 1 s) före varje test,
  och läs nedladdningstiden: några ms för en 68 kB-rampatch betyder att inget laddades.
- Läs UART-räknarna (`/proc/tty/driver/serial`: `oe:`, `fe:`) före och efter varje försök. Overruns förklarade
  timeouts som annars såg ut som protokollfel (IBS, baudrate, firmware), och hypoteser om dem kostade flera omstarter.
- Efter unbind/bind heter enheten hci1 och rfkill-numret ändras: hitta dem med `bluetoothctl list` och
  `/sys/class/rfkill/*/type`, inte hci0/rfkill0.
- `fdtput -t x` tolkar alla värden som hex. Mediateks sysirq (phandle 1) har 3 interrupt-celler. Hitta noder med
  `fdtget -l` i stället för att gissa sökvägar.
