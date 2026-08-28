#!/usr/bin/env bash
# Builds the qBittorrent QPKG for every QNAP CPU architecture that has a
# matching static qbittorrent-nox build available.
#
# CAVEAT: only x86_64 has actually been run/tested against a real binary
# (see README.md). Every other architecture below is packaged the same way
# and *should* work, but is unverified on real hardware — this dev machine
# can't execute non-x86_64 binaries, and QDK's packaging step doesn't run
# the binary, only bundles it.
#
# What this does:
#   1. Fetches QNAP's official QDK build tool (qnap-dev/QDK on GitHub) into
#      .qdk-toolkit/ if it isn't already there. This is a build dependency,
#      not part of the package, so it's git-ignored rather than vendored.
#   2. Downloads the latest static qbittorrent-nox binary for each
#      supported architecture from userdocs/qbittorrent-nox-static.
#   3. Runs qbuild to produce one build/<QPKG_NAME>_<version>_<arch>.qpkg
#      per architecture, where <version> is <qbt_version>-<QPKG_REVISION>
#      (e.g. 5.2.3-1.0) — the qBittorrent version and this package's own
#      revision are versioned independently, so a packaging-only fix can
#      bump QPKG_REVISION without waiting on a new qBittorrent release.
#   4. If QPKG_GPG_KEY is set to a GPG key ID you hold the secret key for,
#      signs each .qpkg (both QDK's own embedded signature, verifiable with
#      `qbuild --verify`, and a standalone build/*.qpkg.asc detached
#      signature that anyone can check with plain `gpg --verify` — see
#      README.md). Signing is skipped entirely if QPKG_GPG_KEY is unset.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

QDK_REPO="https://github.com/qnap-dev/QDK.git"
QDK_REF="${QDK_REF:-master}"
TOOLKIT_DIR="$ROOT_DIR/.qdk-toolkit"
NOX_REPO="userdocs/qbittorrent-nox-static"

# This package's own revision, independent of the qBittorrent version it
# bundles. Bump this (and only this) when shipping a packaging-only change
# (e.g. an init script fix) against an already-packaged qBittorrent version.
# Reset it to 1.0 whenever qbt_version below moves to a new upstream release.
QPKG_REVISION="${QPKG_REVISION:-1.0}"

# QNAP arch directory -> qbittorrent-nox-static release asset prefix.
#
# arm-x09 (ARMv5TE Kirkwood, e.g. TS-119/TS-219/TS-419) has no match: the
# static builds' minimum ARM baseline is ARMv6 hard-float, so it's skipped.
# x86_ce53xx (a narrow legacy QNAP variant) and riscv64 (no QNAP hardware
# uses it) are skipped for the same reason: no sensible 1:1 match exists.
#
# arm-x19/arm-x31/arm-x41 (Marvell Armada XP / Annapurna Alpine, all real
# ARMv7-A Cortex-A9/A15-class chips) all get the "armv7" build, which
# targets ARMv7-A specifically (see userdocs/qbt-musl-cross-make's
# triples.json) rather than the more conservative ARMv6 "armhf" build.
ARCH_DIRS=(x86 x86_64 arm_64 arm-x19 arm-x31 arm-x41)
arch_asset(){
    case "$1" in
        x86)      echo x86 ;;
        x86_64)   echo x86_64 ;;
        arm_64)   echo aarch64 ;;
        arm-x19)  echo armv7 ;;
        arm-x31)  echo armv7 ;;
        arm-x41)  echo armv7 ;;
    esac
}

echo "==> Ensuring QDK build toolkit is present..."
if [ ! -x "$TOOLKIT_DIR/bin/qbuild" ] || [ ! -x "$TOOLKIT_DIR/bin/qpkg_encrypt" ]; then
    tmp_qdk="$(mktemp -d)"
    trap 'rm -rf "$tmp_qdk"' EXIT
    git clone --depth 1 --branch "$QDK_REF" "$QDK_REPO" "$tmp_qdk"

    echo "==> Compiling qpkg_encrypt helper..."
    ( cd "$tmp_qdk/src" && make )

    rm -rf "$TOOLKIT_DIR"
    mkdir -p "$TOOLKIT_DIR"
    cp -r "$tmp_qdk/shared/." "$TOOLKIT_DIR/"
    cp "$tmp_qdk/src/bin/qpkg_encrypt" "$TOOLKIT_DIR/bin/"
fi

# qbuild locates its own root via a pwd/"QDK" string match unless qdk.conf
# says otherwise. Pin it explicitly so builds work regardless of cwd.
cat > "$TOOLKIT_DIR/qdk.conf" <<EOF
QDK_VERSION=2.5.3
QDK_PATH="$TOOLKIT_DIR"
EOF

echo "==> Resolving latest qbittorrent-nox-static release..."
release_json="$(curl -fsSL "https://api.github.com/repos/${NOX_REPO}/releases/latest")"
tag="$(printf '%s' "$release_json" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
qbt_version="$(printf '%s' "$tag" | sed -E 's/^release-([0-9.]+)_.*/\1/')"

if [ -z "$tag" ] || [ -z "$qbt_version" ]; then
    echo "Failed to resolve latest qbittorrent-nox-static release" >&2
    exit 1
fi
echo "    latest release: $tag (qBittorrent $qbt_version)"

package_version="${qbt_version}-${QPKG_REVISION}"
echo "    package version: $package_version"

qbuild_args=(--build-version "$package_version" --build-dir build)
for dir in "${ARCH_DIRS[@]}"; do
    asset="$(arch_asset "$dir")"
    echo "==> Downloading ${asset}-qbittorrent-nox for ${dir}..."
    mkdir -p "$ROOT_DIR/$dir"
    curl -fsSL -o "$ROOT_DIR/$dir/qbittorrent-nox" \
        "https://github.com/${NOX_REPO}/releases/download/${tag}/${asset}-qbittorrent-nox"
    chmod +x "$ROOT_DIR/$dir/qbittorrent-nox"
    qbuild_args+=(--build-arch "$dir")
done

QPKG_GPG_KEY="${QPKG_GPG_KEY:-}"
[ -n "$QPKG_GPG_KEY" ] && qbuild_args+=(--sign --gpg-name "$QPKG_GPG_KEY")

echo "==> Building QPKGs (version $package_version) for: ${ARCH_DIRS[*]}..."
rm -rf "$ROOT_DIR/build"
PATH="$TOOLKIT_DIR/bin:$PATH" "$TOOLKIT_DIR/bin/qbuild" "${qbuild_args[@]}"

if [ -n "$QPKG_GPG_KEY" ]; then
    for qpkg_file in "$ROOT_DIR"/build/*.qpkg; do
        echo "==> Verifying embedded QDK signature ($(basename "$qpkg_file"))..."
        PATH="$TOOLKIT_DIR/bin:$PATH" "$TOOLKIT_DIR/bin/qbuild" --verify "$qpkg_file"

        echo "==> Writing standalone detached signature ($(basename "$qpkg_file").asc)..."
        gpg --batch --yes --local-user "$QPKG_GPG_KEY" \
            --detach-sign --armor -o "${qpkg_file}.asc" "$qpkg_file"
    done
fi

echo "==> Done:"
ls -la "$ROOT_DIR/build"
