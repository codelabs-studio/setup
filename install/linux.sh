#!/usr/bin/env bash
# Install Linux dependencies (Debian/Ubuntu via apt).
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
    echo "Non-apt Linux detected. Install caddy, mkcert, gh, jq, tmux manually." >&2
    exit 1
fi

# Caddy: needs the official repo
if ! command -v caddy >/dev/null 2>&1; then
    echo "Installing Caddy..."
    sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y caddy
fi

# Other packages
sudo apt-get install -y libnss3-tools jq tmux gh

# mkcert: precompiled binary
if ! command -v mkcert >/dev/null 2>&1; then
    echo "Installing mkcert..."
    MKCERT_VERSION="v1.4.4"
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64) MKCERT_ARCH="amd64" ;;
        aarch64|arm64) MKCERT_ARCH="arm64" ;;
        *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
    esac
    sudo curl -L "https://github.com/FiloSottile/mkcert/releases/download/${MKCERT_VERSION}/mkcert-${MKCERT_VERSION}-linux-${MKCERT_ARCH}" -o /usr/local/bin/mkcert
    sudo chmod +x /usr/local/bin/mkcert
    mkcert -install 2>/dev/null || true
fi

echo "✅ Linux deps ready"
