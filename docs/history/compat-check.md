## Compatibility check: CB311-11H (N19Q10) UEFI

### Result
- The Acer Chromebook 311 CB311-11H uses a MediaTek MT8183 CPU (ARM architecture).
- MrChromebox Full ROM UEFI firmware targets Intel-based Chromebooks only.
- Therefore the standard UEFI firmware route is **not supported** for this model.

### Evidence
- Acer product page for CB311-11H lists MediaTek MT8183 (ARM): https://www.acer.com/us-en/chromebooks/acer-chromebook-311-cb311-11h-cb311-11ht/pdp/NX.AAYAA.004
- Datasheet/retailer spec confirms MT8183: https://gzhls.at/blob/ldb/5/f/9/0/c84c73e9a4f2482bc710d53f100bfa193516.pdf

### Implication
- If the goal is a full Linux install, the device needs an ARM-specific approach rather than MrChromebox UEFI.
