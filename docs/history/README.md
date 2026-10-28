# Historical notes

These are notes from earlier attempts to get Linux running on the CB311-11H, kept for reference:

- [`compat-check.md`](compat-check.md) and [`arm-linux-path.md`](arm-linux-path.md): the MrChromebox UEFI firmware is
  Intel-only, so this ARM (MT8183) board needs a depthcharge/vboot boot instead.
- [`chromeos-boot-config.md`](chromeos-boot-config.md) and [`error-log.md`](error-log.md): a self-built 6.6 kernel
  without an initramfs, which only gave a black screen.

They are not the current method. The working method (Debian kernel + initramfs packed with `mkdepthcharge`) is
described in the top-level [`README.md`](../../README.md); [`../kernel-analysis.md`](../kernel-analysis.md) explains
why the initramfs is needed.
