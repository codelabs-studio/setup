# codelabs-setup

One-line bootstrap for a complete Claude Code development environment. Reproduces the codelabs.studio Claude Code setup on a new Mac (or Linux box) in minutes — including plugins, hooks, system dependencies (Caddy, mkcert, gh, jq), and a baseline `CLAUDE.md` with anti-sycophancy and autonomous-loop conventions.

## Why this exists

If you maintain more than one Mac (or onboard new teammates), replicating a custom Claude Code environment manually takes 2-4 hours and you forget half the steps. This script does it in 5-10 minutes, idempotently.

## Quick start

```bash
# Personal mode (full setup, prompts for personal credentials)
curl -fsSL https://codelabs.studio/setup | bash

# Team mode (plugins + hooks + baseline CLAUDE.md, no credentials prompts)
curl -fsSL https://codelabs.studio/setup | bash -s -- --team

# Or clone and run locally:
git clone https://github.com/codelabs-studio/setup.git
cd setup
./bootstrap.sh --team
```

## What it installs

### System dependencies (via Homebrew on macOS, apt on Linux)
- **caddy** — local HTTPS reverse proxy for dev domains
- **mkcert** — local TLS certificate authority
- **gh** — GitHub CLI
- **jq** — JSON manipulation in scripts
- **tmux** — multiplexed dev sessions

### Claude Code plugins (from the codelabs marketplace)
- `codelabs-cofounder` — virtual co-founder with project journal
- `codelabs-dev-servers` — deterministic ports + HTTPS dev domains via Caddy
- `codelabs-advisors` — pre-launch audits (SEO, security, perf, email)
- `codelabs-feature-port` — cross-project feature migration

### Configuration files
- `~/.claude/CLAUDE.md` — baseline conventions (anti-sycophancy, autonomous loop, branch lifecycle, security rules). Personal mode adds your name/email; team mode leaves placeholders.
- `~/.claude/hooks/anti-sycophancy.py` — Stop hook that flags overly agreeable responses.
- `~/.claude/hooks/sync-skills-cache.sh` — PostToolUse hook that keeps the plugin cache in sync with skill source files.

### Per-machine bootstrap of `~/.devproxy/`
The dev-servers plugin needs a local Caddy state directory. The bootstrap creates `~/.devproxy/{Caddyfile,certs/,config/routes.json}` with sensible defaults.

## Modes

### `--personal` (default)
Full setup. Prompts you to:
- Set your name and email (used in CLAUDE.md and git config if missing).
- Optionally configure `~/.config/codelabs/services.json` for credential management (services like Railway, Cloudflare, etc.).

This is what you'd run on your own laptop.

### `--team`
Lighter setup. No personal prompts. Installs:
- All plugins
- All hooks
- A team-flavored CLAUDE.md (placeholders for personal info, but workflow conventions intact)

This is what a new teammate runs to inherit your conventions without inheriting your identity.

### `--minimal`
Plugins only. No hooks, no CLAUDE.md changes. For when you want to inspect everything before committing.

## What it does NOT do

- Touch your existing `~/.claude/settings.json` permissions list (only adds plugins/hooks).
- Install Anthropic credentials. You log in to Claude Code separately (`claude login`).
- Sync personal data across machines. For that, use a private dotfiles repo (separate from this one).

## Idempotency

Safe to re-run. The bootstrap checks for each component before installing. Existing files are diffed and the user is prompted before overwrites (unless `--force` is passed).

## Verifying the setup

After bootstrap, run:

```bash
./bootstrap.sh --verify
```

This runs a health check across all components and reports anything missing.

## Files in this repo

```
codelabs-setup/
├── bootstrap.sh              # Main script (the one curl pipes to bash)
├── install/
│   ├── macos.sh              # macOS-specific installs
│   ├── linux.sh              # Linux-specific installs
│   └── dev-proxy.sh          # Bootstrap ~/.devproxy/
├── templates/
│   ├── CLAUDE.md.team        # Team-flavored CLAUDE.md
│   ├── CLAUDE.md.personal    # Personal-flavored (with placeholders)
│   ├── settings.json.snippet # Plugins + hooks block to merge into existing settings.json
│   └── hooks/
│       ├── anti-sycophancy.py
│       └── sync-skills-cache.sh
├── plugins.txt               # List of plugins to install (line-separated)
└── README.md
```

## License

MIT.

## Maintainers

[codelabs.studio](https://codelabs.studio)
