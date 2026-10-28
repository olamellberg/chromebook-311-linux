#!/usr/bin/env bash
# Runs build/image-build.sh in the background as a transient systemd user unit (it survives the ssh session if the
# user lingers: loginctl enable-linger) at nice 10, so a small shared server stays responsive. Results go to out/.
# Started by scripts/remote-build.sh; works the same when run by hand.
#
#   bash build/background-build.sh             # log: out/build.log; status: systemctl --user status chromebook-build
#   FG=1 bash build/background-build.sh        # in the foreground
#   IMG_COMPRESS=none bash build/background-build.sh   (every image-build.sh / make-image.sh setting is passed on)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
LOG=${LOG:-$REPO/out/build.log}
UNIT=chromebook-build

if [ "${FG:-0}" = 1 ]; then
    t0=$SECONDS
    echo "== $(date -Is) build of $(cat "$REPO/.pushed" 2>/dev/null || git -C "$REPO" describe --always --dirty 2>/dev/null || echo '?')"
    nice -n 10 bash "$HERE/image-build.sh"
    echo "== $(date -Is) build finished in $(( (SECONDS - t0) / 60 )) min"
    exit 0
fi

if systemctl --user is-active -q "$UNIT" 2>/dev/null; then
    echo "$UNIT is already running (log: $LOG)" >&2; exit 1
fi
mkdir -p "$(dirname "$LOG")"; : > "$LOG"
envs=()
for v in ENGINE OUT SUITE MIRROR IMG_SIZE_MIB KERN_SIZE_MIB DTB ROOT_PASSWORD KERNEL_COMPRESS KERN_ATTRS \
         EXTRA_CMDLINE EXTRA_PACKAGES IMG_COMPRESS SSH_AUTHORIZED_KEY USER_NAME USER_PASSWORD PASSWORD_EXPIRED KEYBOARD_LAYOUT; do
    [ -n "${!v+x}" ] && envs+=("--setenv=$v=${!v}")
done
systemd-run --user --unit="$UNIT" --collect --quiet "${envs[@]}" --setenv=FG=1 \
    --property=StandardOutput=append:"$LOG" --property=StandardError=append:"$LOG" \
    --working-directory="$REPO" /bin/bash "$HERE/background-build.sh"
echo "started as systemd user unit $UNIT; log: $LOG"
