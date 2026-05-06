#!/usr/bin/env bash
# codelabs-setup bootstrap.
# Reproduces the codelabs.studio Claude Code environment on a new machine.
#
# Usage:
#   curl -fsSL https://codelabs.studio/setup | bash                    # personal
#   curl -fsSL https://codelabs.studio/setup | bash -s -- --team       # team
#   ./bootstrap.sh [--personal|--team|--minimal] [--verify] [--force]

set -euo pipefail

MODE="personal"
FORCE=false
VERIFY_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --personal) MODE="personal"; shift ;;
        --team) MODE="team"; shift ;;
        --minimal) MODE="minimal"; shift ;;
        --force) FORCE=true; shift ;;
        --verify) VERIFY_ONLY=true; shift ;;
        -h|--help)
            sed -n '2,7p' "$0"; exit 0 ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

# Detect script location (works whether sourced via curl or run locally)
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    # Likely curl|bash: clone to a temp dir
    REPO_DIR="$(mktemp -d)"
    echo "==> Cloning setup repo to $REPO_DIR"
    git clone --depth 1 https://github.com/codelabs-studio/setup.git "$REPO_DIR"
fi

OS="$(uname -s)"
case "$OS" in
    Darwin) PLATFORM="macos" ;;
    Linux)  PLATFORM="linux" ;;
    *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
esac

CLAUDE_DIR="${HOME}/.claude"
mkdir -p "$CLAUDE_DIR/hooks"

# ---------- helpers ----------

log()  { printf "==> %s\n" "$*"; }
warn() { printf "⚠️  %s\n" "$*" >&2; }
ok()   { printf "✅ %s\n" "$*"; }

confirm() {
    if [[ "$FORCE" == true ]]; then return 0; fi
    read -r -p "$1 [y/N] " ans
    [[ "$ans" =~ ^[yY]$ ]]
}

# ---------- verify-only path ----------

if [[ "$VERIFY_ONLY" == true ]]; then
    log "Verifying setup"
    for cmd in caddy mkcert gh jq tmux; do
        if command -v "$cmd" >/dev/null 2>&1; then
            ok "$cmd: $($cmd --version 2>/dev/null | head -1 || echo installed)"
        else
            warn "$cmd: missing"
        fi
    done
    test -d "${HOME}/.devproxy" && ok "~/.devproxy/: present" || warn "~/.devproxy/: missing"
    test -f "$CLAUDE_DIR/CLAUDE.md" && ok "CLAUDE.md: present" || warn "CLAUDE.md: missing"
    test -f "$CLAUDE_DIR/hooks/anti-sycophancy.py" && ok "anti-sycophancy hook: present" || warn "anti-sycophancy hook: missing"
    exit 0
fi

# ---------- step 1: system dependencies ----------

log "Mode: $MODE"
log "Platform: $PLATFORM"

if [[ "$MODE" != "minimal" ]]; then
    log "Installing system dependencies"
    bash "$REPO_DIR/install/${PLATFORM}.sh"
fi

# ---------- step 2: Claude Code plugins ----------

log "Adding codelabs marketplace"
if command -v claude >/dev/null 2>&1; then
    claude plugin marketplace add codelabs https://codelabs.studio/plugins/marketplace.json || true
    while read -r plugin; do
        [[ -z "$plugin" || "$plugin" == \#* ]] && continue
        log "Installing plugin: $plugin"
        claude plugin install "${plugin}@codelabs" || warn "Plugin $plugin failed (continue anyway)"
    done < "$REPO_DIR/plugins.txt"
else
    warn "Claude CLI not found. Install Claude Code first: https://claude.com/claude-code"
fi

# ---------- step 3: hooks ----------

if [[ "$MODE" != "minimal" ]]; then
    log "Installing hooks"
    cp "$REPO_DIR/templates/hooks/anti-sycophancy.py" "$CLAUDE_DIR/hooks/"
    cp "$REPO_DIR/templates/hooks/sync-skills-cache.sh" "$CLAUDE_DIR/hooks/"
    chmod +x "$CLAUDE_DIR/hooks/"*.{py,sh} 2>/dev/null || true
fi

# ---------- step 4: CLAUDE.md ----------

if [[ "$MODE" != "minimal" ]]; then
    if [[ -f "$CLAUDE_DIR/CLAUDE.md" ]]; then
        if [[ "$FORCE" == false ]]; then
            warn "CLAUDE.md already exists at $CLAUDE_DIR/CLAUDE.md"
            confirm "Overwrite?" || log "Skipping CLAUDE.md"
        fi
    fi

    if [[ ! -f "$CLAUDE_DIR/CLAUDE.md" || "$FORCE" == true ]]; then
        log "Installing CLAUDE.md ($MODE flavor)"
        if [[ "$MODE" == "team" ]]; then
            cp "$REPO_DIR/templates/CLAUDE.md.team" "$CLAUDE_DIR/CLAUDE.md"
        else
            cp "$REPO_DIR/templates/CLAUDE.md.personal" "$CLAUDE_DIR/CLAUDE.md"

            # Personal: prompt for name + email
            read -r -p "Your name: " USER_NAME
            read -r -p "Your email: " USER_EMAIL
            sed -i.bak "s/{{USER_NAME}}/$USER_NAME/g; s/{{USER_EMAIL}}/$USER_EMAIL/g" "$CLAUDE_DIR/CLAUDE.md"
            rm -f "$CLAUDE_DIR/CLAUDE.md.bak"
        fi
    fi
fi

# ---------- step 5: ~/.devproxy/ ----------

if [[ "$MODE" != "minimal" ]]; then
    bash "$REPO_DIR/install/dev-proxy.sh"
fi

# ---------- step 6: settings.json snippet ----------

if [[ "$MODE" != "minimal" ]]; then
    log "Settings snippet to merge into ~/.claude/settings.json:"
    echo ""
    cat "$REPO_DIR/templates/settings.json.snippet"
    echo ""
    log "Merge the 'hooks' and 'enabledPlugins' blocks above into your settings.json manually (we don't auto-merge to avoid clobbering your custom permissions/MCP servers)."
fi

# ---------- summary ----------

echo ""
ok "Setup complete."
echo ""
log "Next steps:"
echo "  1. Restart Claude Code (or run 'claude' in a fresh terminal)."
echo "  2. Run /dev-servers init in any project to bootstrap dev-proxy."
echo "  3. Verify with: $0 --verify"
echo ""
