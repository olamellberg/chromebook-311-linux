# Debian arm64 on the Acer Chromebook 311 CB311-11H (MT8183, board jacuzzi, model kenzo)

Notes for coding agents and contributors. `README.md` is the user guide; `HANDOFF.md` (current state) and
`tasks/todo.md` (phased plan with checkboxes) are the working notes, `tasks/lessons.md` the mistakes not to repeat.
Read them before changing the build, and update them as work progresses.

## Ground rules
- Device: HWID `KENZO-IGRW`, firmware `Google_Juniper 12573.202.0`, DTB `mt8183-kukui-jacuzzi-kenzo.dtb`.
  Boot chain = depthcharge/vboot: a devkey-signed FIT (kernel + initramfs + DTB) on a ChromeOS kernel partition,
  booted with Ctrl+U (USB) or Ctrl+D (eMMC) in Developer Mode. There is no UEFI on this board.
- Build with `build/image-build.sh` (rootless Podman or Docker) on any Linux host, or `scripts/remote-build.sh` to
  drive a remote one. Do not go back to hand-run steps in a VM.
- Use the Debian kernel + initramfs + depthcharge-tools (`mkdepthcharge` in the build, `depthchargectl` on the
  device; both know kenzo). A self-built kernel is a fallback only (`legacy/`), and its config and patches must then
  be committed.
- Everything that makes the image is in this repo: never leave work only in a VM, container volume or untracked tree.
- Never write to a Chromebook's eMMC (`install-emmc`, `crossystem`, `cgpt` on `/dev/mmcblk0`) without the owner's
  explicit go-ahead. USB sticks are fine to overwrite once the owner has named the device.
- No personal data in the repo: no passwords other than the documented public defaults, no keys, no LAN addresses,
  host or user names of a particular setup. Build settings for one's own image go in environment variables.
- Build hosts may be small shared machines: keep jobs niced (`build/background-build.sh` does) and run one build at
  a time. Root changes on a host go through scripts the owner runs (`scripts/host-setup.sh`).
