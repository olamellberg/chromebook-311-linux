#!/usr/bin/env bash
# Runs the build on another Linux machine over ssh, e.g. from Windows (Git Bash) or a laptop to a small server.
# On a Linux machine that builds for itself, run build/image-build.sh directly instead.
#
#   BUILD_HOST=user@host scripts/remote-build.sh push    # copy the working tree (tracked + untracked, not ignored)
#   BUILD_HOST=user@host scripts/remote-build.sh build   # push, then start build/background-build.sh there
#   BUILD_HOST=user@host scripts/remote-build.sh log     # follow out/build.log
#   BUILD_HOST=user@host scripts/remote-build.sh pull    # copy the newest image set to ./out/ and check its sha256
#
# Settings: BUILD_HOST (required, an ssh destination), BUILD_DIR (default chromebook-linux, relative to the remote
# home), and every build setting of build/make-image.sh, which travels along (e.g. IMG_COMPRESS=none).
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_HOST=${BUILD_HOST:?set BUILD_HOST to the ssh destination of the build machine, e.g. BUILD_HOST=me@buildbox}
BUILD_DIR=${BUILD_DIR:-chromebook-linux}

push() {
    # out/ and other build results are git-ignored, so they never travel
    git describe --always --dirty 2>/dev/null > .pushed || echo unversioned > .pushed
    { git ls-files -co --exclude-standard -z; printf '.pushed\0'; } | tar --null -T - -czf - \
        | ssh "$BUILD_HOST" "mkdir -p '$BUILD_DIR' && tar xzf - -C '$BUILD_DIR'"
    rm -f .pushed
    echo "pushed to $BUILD_HOST:$BUILD_DIR"
}

case "${1:-}" in
    push) push ;;
    build)
        push
        # The image gets this machine's public key for root, so it is reachable over SSH from the first boot.
        # SSH_AUTHORIZED_KEY= (empty) builds without one.
        if [ -z "${SSH_AUTHORIZED_KEY+x}" ] && [ -f ~/.ssh/id_ed25519.pub ]; then
            SSH_AUTHORIZED_KEY=$(cat ~/.ssh/id_ed25519.pub)
        fi
        envs=
        for v in SUITE MIRROR IMG_SIZE_MIB KERN_SIZE_MIB DTB ROOT_PASSWORD KERNEL_COMPRESS KERN_ATTRS EXTRA_CMDLINE \
                 EXTRA_PACKAGES IMG_COMPRESS SSH_AUTHORIZED_KEY USER_NAME USER_PASSWORD PASSWORD_EXPIRED KEYBOARD_LAYOUT; do
            [ -n "${!v+x}" ] && envs+=" $v=$(printf %q "${!v}")"
        done
        ssh "$BUILD_HOST" "cd '$BUILD_DIR' &&$envs bash build/background-build.sh"
        ;;
    log) ssh "$BUILD_HOST" "tail -n 50 -f '$BUILD_DIR/out/build.log'" ;;
    pull)
        name=$(ssh "$BUILD_HOST" "cd '$BUILD_DIR/out' && ls -t chromebook-debian-*.sha256 | head -1")
        name=${name%.sha256}
        mkdir -p out
        scp "$BUILD_HOST:$BUILD_DIR/out/$name.*" out/
        (cd out && sha256sum -c "$name.sha256")
        ;;
    *) sed -n '2,11p' "$0" >&2; exit 2 ;;
esac
