# ChromeOS boot configuration for external USB boot

## Overview

On ARM Chromebooks, external boot must be explicitly allowed in the vboot NVRAM. If `dev_boot_usb` is not set to `1`, Ctrl+U can fail "silently" and show a black screen without actually trying to boot from USB.

## Steps to verify and set the boot settings

### 1. Open the ChromeOS Developer Mode shell

1. Press `Ctrl+Alt+T` to open crosh
2. Type `shell` to open a Linux shell
3. If you are not in Developer Mode, enable it first (this requires a powerwash)

### 2. Check the current settings

Run the following command to see the current values:

```bash
crossystem dev_boot_usb dev_boot_signed_only dev_default_boot
```

Expected values for external USB boot:
- `dev_boot_usb=1` - allows Ctrl+U (external media)
- `dev_boot_signed_only=0` - allows booting your own (devkey-signed) kernels
- `dev_default_boot` can have different values depending on the configuration

### 3. Set the correct values (if needed)

If the values are not correct, set them with:

```bash
sudo crossystem dev_boot_usb=1
sudo crossystem dev_boot_signed_only=0
```

**Important:** These changes require root privileges and may require that you are in Developer Mode.

### 4. Verify that the changes took effect

Run again to confirm:

```bash
crossystem dev_boot_usb dev_boot_signed_only dev_default_boot
```

You should now see:
```
dev_boot_usb = 1
dev_boot_signed_only = 0
```

## Interpretation

- **`dev_boot_usb=1`**: Allows booting from external media (USB/SD) via Ctrl+U
- **`dev_boot_signed_only=0`**: Allows booting kernels signed with devkeys (required for your own kernels)
- If `dev_boot_usb` is not `1`, Ctrl+U can give a black screen without actually trying to boot

## References

- [Depthcharge | The Eupnea Project](https://doodlezucc.github.io/eupnea-linux.github.io/docs/chromebook/depthcharge)
- Chromebook boot flow documentation: https://docs.kernel.org/arch/arm/google/chromebook-boot-flow.html

## Next steps

After verifying these settings, continue with:
1. Tries check (see [`error-log.md`](error-log.md))
2. Kernel build with built-in drivers
3. Test boot with the correct DTB
