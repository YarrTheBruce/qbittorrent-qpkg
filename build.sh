#!/usr/bin/env bash
# Builds the qBittorrent QPKG for QNAP x86_64 NAS models.
#
# What this does:
#   1. Fetches QNAP's official QDK build tool (qnap-dev/QDK on GitHub) into
#      .qdk-toolkit/ if it isn't already there. This is a build dependency,
#      not part of the package, so it's git-ignored rather than vendored.
#   2. Downloads the latest static qbittorrent-nox binary for x86_64 from
#      userdocs/qbittorrent-nox-static.
#   3. Runs qbuild to produce build/qbittorrent_<version>_x86_64.qpkg.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

QDK_REPO="https://github.com/qnap-dev/QDK.git"
QDK_REF="${QDK_REF:-master}"
TOOLKIT_DIR="$ROOT_DIR/.qdk-toolkit"
NOX_REPO="userdocs/qbittorrent-nox-static"

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
bin_url="https://github.com/${NOX_REPO}/releases/download/${tag}/x86_64-qbittorrent-nox"

if [ -z "$tag" ] || [ -z "$qbt_version" ]; then
    echo "Failed to resolve latest qbittorrent-nox-static release" >&2
    exit 1
fi
echo "    latest release: $tag (qBittorrent $qbt_version)"

echo "==> Downloading x86_64-qbittorrent-nox..."
mkdir -p "$ROOT_DIR/x86_64"
curl -fsSL -o "$ROOT_DIR/x86_64/qbittorrent-nox" "$bin_url"
chmod +x "$ROOT_DIR/x86_64/qbittorrent-nox"

echo "==> Building QPKG (version $qbt_version)..."
rm -rf "$ROOT_DIR/build"
PATH="$TOOLKIT_DIR/bin:$PATH" "$TOOLKIT_DIR/bin/qbuild" \
    --build-arch x86_64 \
    --build-version "$qbt_version" \
    --build-dir build

echo "==> Done:"
ls -la "$ROOT_DIR/build"
