#!/usr/bin/env bash
# Install macOS dependencies via Homebrew.
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

PACKAGES=(caddy mkcert nss gh jq tmux)
TO_INSTALL=()

for pkg in "${PACKAGES[@]}"; do
    if brew list --formula | grep -q "^${pkg}\$"; then
        echo "  $pkg: already installed"
    else
        TO_INSTALL+=("$pkg")
    fi
done

if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
    echo "Installing: ${TO_INSTALL[*]}"
    brew install "${TO_INSTALL[@]}"
fi

# Install local CA (idempotent)
mkcert -install 2>/dev/null || true

echo "✅ macOS deps ready"
