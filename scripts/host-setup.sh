#!/usr/bin/env bash
# host-setup.sh: one-time root setup of the build machine (Debian or Ubuntu) for the arm64 image build.
# Run with sudo:  sudo bash scripts/host-setup.sh      (over ssh:  ssh -t me@buildbox 'sudo bash -s' < scripts/host-setup.sh)
#
# mmdebstrap runs the arm64 rootfs' maintainer scripts (and update-initramfs) in a chroot inside the build container.
# That needs a qemu-aarch64 binfmt entry with the F (fix-binary) flag, so the kernel opens the static interpreter on
# the host and it also works in containers that do not contain qemu. binfmt_misc is global, so this is host setup.
# Undo: apt-get remove qemu-user-binfmt; rm -f /etc/binfmt.d/qemu-aarch64-F.conf; systemctl restart systemd-binfmt
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
F=/proc/sys/fs/binfmt_misc/qemu-aarch64

DEBIAN_FRONTEND=noninteractive apt-get install -y qemu-user-binfmt
systemctl restart systemd-binfmt
[ -f "$F" ] || { echo "no $F after installing qemu-user-binfmt" >&2; exit 1; }

INTERP=$(sed -n 's/^interpreter //p' "$F")
file -L "$INTERP" | grep -Eq 'statically linked|static-pie linked' || { echo "$INTERP is not static: $(file -L "$INTERP")" >&2; exit 1; }

if ! grep -q '^flags:.*F' "$F"; then
    # Same entry again with the F flag, from the registered magic and mask
    magic=$(sed -n 's/^magic //p' "$F" | sed 's/../\\x&/g')
    mask=$(sed -n 's/^mask //p' "$F" | sed 's/../\\x&/g')
    flags=$(sed -n 's/^flags: //p' "$F")
    echo ":qemu-aarch64:M::$magic:$mask:$INTERP:${flags}F" > /etc/binfmt.d/qemu-aarch64-F.conf
    echo -1 > "$F"
    systemctl restart systemd-binfmt
fi
cat "$F"
