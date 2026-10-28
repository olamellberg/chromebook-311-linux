#!/usr/bin/env python3
"""Adds firmware files that Debian's packages lack, from pinned public sources, checked by sha256.
Called by build/make-image.sh (mmdebstrap customize hook) with the rootfs directory as argument.
These blobs never go into git."""
import base64, hashlib, os, sys, urllib.request

CROS_FW = "https://chromium.googlesource.com/chromiumos/third_party/linux-firmware/+/refs/heads/master/{}?format=TEXT"

FILES = [
    # The kenzo DT asks for this NVM (bluetooth node: firmware-name). firmware-atheros only has the _i2s_eu variant,
    # which starts the QCA6174 but then fails (frame reassembly errors, HCI timeouts). Same file as ChromeOS 16404.
    ("qca/nvm_00440302_i2s.bin", CROS_FW, "001a4af8e29282650e84e1237ae4b3e5e7ef6f1afea48a16f39af682873ba5e8"),
]

root = sys.argv[1]
for path, src, sha in FILES:
    with urllib.request.urlopen(src.format(path), timeout=60) as r:
        data = base64.b64decode(r.read())
    got = hashlib.sha256(data).hexdigest()
    if got != sha:
        sys.exit(f"{path}: sha256 {got}, expected {sha}")
    dest = os.path.join(root, "usr/lib/firmware", path)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as f:
        f.write(data)
    print(f"firmware: {path} ({len(data)} bytes, sha256 ok)")
