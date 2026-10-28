#!/usr/bin/env bash
# Builds the CB311-11H USB image on any Linux host with rootless Podman or Docker, plus a qemu-aarch64 binfmt entry
# with the F flag (scripts/host-setup.sh). Works the same on a server (build/background-build.sh), in WSL2 or a VM.
#
#   build/image-build.sh                            # -> out/chromebook-debian-<date>.{img.xz,kernel.img,txt,sha256}
#   IMG_COMPRESS=none KERNEL_COMPRESS=lzma build/image-build.sh
#
# Settings: ENGINE (podman|docker), OUT (default <repo>/out), and every setting of build/make-image.sh.
# The container runs --privileged; with rootless Podman that is root in the user's namespace only, not on the host.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
ENGINE=${ENGINE:-$(command -v podman >/dev/null && echo podman || echo docker)}
IMAGE=chromebook-linux-build
OUT=${OUT:-$REPO/out}

f=/proc/sys/fs/binfmt_misc/qemu-aarch64
if ! grep -qs '^flags:.*F' "$f"; then
    echo "no qemu-aarch64 binfmt entry with the F flag ($f): run scripts/host-setup.sh as root" >&2
    exit 1
fi

"$ENGINE" build -q -t "$IMAGE" -f "$HERE/Containerfile" "$HERE"
mkdir -p "$OUT"
envs=()
for v in SUITE MIRROR IMG_SIZE_MIB KERN_SIZE_MIB DTB ROOT_PASSWORD KERNEL_COMPRESS KERN_ATTRS EXTRA_CMDLINE \
         EXTRA_PACKAGES IMG_COMPRESS SSH_AUTHORIZED_KEY USER_NAME USER_PASSWORD PASSWORD_EXPIRED KEYBOARD_LAYOUT; do
    [ -n "${!v+x}" ] && envs+=(-e "$v=${!v}")
done
exec "$ENGINE" run --rm --privileged -v "$REPO:/port:ro" -v chromebook-linux-work:/work -v "$OUT:/out" \
    "${envs[@]}" "$IMAGE" bash /port/build/make-image.sh
