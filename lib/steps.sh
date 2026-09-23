#!/usr/bin/env bash
# lib/steps.sh — pasos de instalación, uno por herramienta. Todos son
# idempotentes (comprueban antes de actuar) y respetan DRY_RUN a través de
# run()/would() de lib/common.sh.
#
# REGLA DE DISEÑO (doc 63, apartado 2.6): ningún portátil guarda secretos de
# producción. Ningún paso de aquí copia un .env real, exporta un secreto en
# un dotfile (.zshrc/.bashrc/.profile) ni imprime el contenido de un fichero
# de credenciales. Lo único que se genera es un .env de DESARROLLO a partir
# de una plantilla (.env.example y similares), nunca a partir de un .env real.

CODE_ROOT="${CODE_ROOT:-$HOME/Dev/code}"
FORGEJO_HOST="${FORGEJO_HOST:-http://100.126.7.116:3300}"
FORGEJO_ORG="${FORGEJO_ORG:-jose}"
MEMORYFIRST_HOOKS_DIR="${MEMORYFIRST_HOOKS_DIR:-$CODE_ROOT/memoryfirst/packages/claude-hooks}"

ensure_jq() {
    if has_cmd jq; then
        return 0
    fi
    log "jq"
    if [[ "$HW_OS" == macos ]]; then
        require_cmd brew "Homebrew no está instalado; instálalo primero (https://brew.sh)"
        run brew install jq
    else
        run sudo apt-get install -y jq
    fi
}

# ---------------------------------------------------------------------------
# Base: tailscale, git, node, pnpm, python
# ---------------------------------------------------------------------------

step_tailscale() {
    log "Tailscale"
    if ! has_cmd tailscale; then
        if [[ "$HW_OS" == macos ]]; then
            require_cmd brew "Homebrew no está instalado; instálalo primero (https://brew.sh)"
            run brew install --cask tailscale
        else
            would "curl -fsSL https://tailscale.com/install.sh | sh"
            if [[ "$DRY_RUN" != true ]]; then
                curl -fsSL https://tailscale.com/install.sh | sh
            fi
        fi
    else
        ok "tailscale ya instalado"
    fi

    # Nunca con auth key en este script. Si hace falta, se abre el login
    # interactivo (navegador) para que la persona autorice desde su cuenta.
    if [[ "$DRY_RUN" == true ]]; then
        would "tailscale up   (login interactivo si no está conectado; SIN --auth-key)"
        return
    fi
    has_cmd tailscale || { warn "tailscale sigue sin estar disponible tras el intento de instalación"; return; }
    local state
    state="$(tailscale status --json 2>/dev/null | grep -o '"BackendState":"[A-Za-z]*"' | head -1 | cut -d'"' -f4)"
    if [[ "$state" == "Running" ]]; then
        ok "tailscale ya conectado"
    else
        log "Tailscale no está conectado: abriendo login interactivo (tailscale up)"
        sudo tailscale up || warn "tailscale up no se completó; repítelo a mano cuando puedas (nunca con --auth-key aquí)"
    fi
}

step_git() {
    log "git"
    if has_cmd git; then
        ok "git: $(git --version)"
        return
    fi
    if [[ "$HW_OS" == macos ]]; then
        run brew install git
    else
        run sudo apt-get install -y git
    fi
}

step_node() {
    log "Node.js LTS"
    if has_cmd node; then
        local major; major="$(node -v | sed 's/^v//' | cut -d. -f1)"
        if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 18 )); then
            ok "node: $(node -v) (ya instalado)"
            return
        fi
        warn "node $(node -v) es viejo; se instala una LTS al lado con el gestor del sistema"
    fi
    if [[ "$HW_OS" == macos ]]; then
        require_cmd brew "Homebrew no está instalado; instálalo primero (https://brew.sh)"
        run brew install node
    else
        would "curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -   &&   sudo apt-get install -y nodejs"
        if [[ "$DRY_RUN" != true ]]; then
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt-get install -y nodejs
        fi
    fi
    ok "node: $(node -v 2>/dev/null || echo 'pendiente de nueva shell')"
}

step_pnpm() {
    log "pnpm (via corepack)"
    if ! has_cmd corepack; then
        warn "corepack no está disponible (¿falló la instalación de node?); omito pnpm"
        return
    fi
    run corepack enable
    run corepack prepare pnpm@latest --activate
    ok "pnpm: $(pnpm --version 2>/dev/null || echo 'pendiente de nueva shell')"
}

step_python() {
    log "Python 3"
    if has_cmd python3; then
        ok "python3: $(python3 --version 2>&1)"
        return
    fi
    if [[ "$HW_OS" == macos ]]; then
        require_cmd brew "Homebrew no está instalado; instálalo primero (https://brew.sh)"
        run brew install python@3.12
    else
        run sudo apt-get install -y python3 python3-venv python3-pip
    fi
}

# ---------------------------------------------------------------------------
# Herramientas de desarrollo local (heredado de codelabs-setup v1)
# ---------------------------------------------------------------------------

step_system_packages() {
    log "Herramientas de desarrollo local (caddy, mkcert, gh, jq, tmux)"
    if [[ "$DRY_RUN" == true ]]; then
        would "bash $SETUP_ROOT/install/${HW_OS}.sh"
        return
    fi
    bash "$SETUP_ROOT/install/${HW_OS}.sh"
}

step_devproxy() {
    log "~/.devproxy/ (para el plugin codelabs-dev-servers)"
    if [[ "$DRY_RUN" == true ]]; then
        would "bash $SETUP_ROOT/install/dev-proxy.sh"
        return
    fi
    bash "$SETUP_ROOT/install/dev-proxy.sh"
}

# ---------------------------------------------------------------------------
# Docker (solo si el pack lo pide Y la máquina lo aguanta)
# ---------------------------------------------------------------------------

step_docker() {
    log "Docker"
    if [[ "$CAP_DOCKER" != true ]]; then
        warn "Docker NO se instala: $CAP_DOCKER_REASON"
        return
    fi
    if has_cmd docker; then
        ok "docker ya instalado"
        return
    fi
    if [[ "$HW_OS" == macos ]]; then
        require_cmd brew "Homebrew no está instalado; instálalo primero (https://brew.sh)"
        run brew install --cask docker
        warn "Docker Desktop instalado: ábrelo una vez a mano para completar el primer arranque"
    else
        would "curl -fsSL https://get.docker.com | sh"
        if [[ "$DRY_RUN" != true ]]; then
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker "$(id -un)" 2>/dev/null || true
            warn "Añadido al grupo docker: cierra sesión y vuelve a entrar para que aplique"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Maestro (solo pack developer, y solo si hay Java)
# ---------------------------------------------------------------------------

step_maestro() {
    log "Maestro (automatización iOS/Android)"
    if ! has_cmd java; then
        warn "Maestro NO se instala: no hay Java en esta máquina"
        return
    fi
    if has_cmd maestro; then
        ok "maestro ya instalado"
        return
    fi
    would "curl -fsSL 'https://get.maestro.mobile.dev' | bash"
    if [[ "$DRY_RUN" != true ]]; then
        curl -fsSL "https://get.maestro.mobile.dev" | bash
    fi
}

# ---------------------------------------------------------------------------
# Claude Code + plugins del pack + CLAUDE.md + settings.json
# ---------------------------------------------------------------------------

step_claude_and_plugins() {
    log "Claude Code"
    if ! has_cmd claude; then
        would "curl -fsSL https://claude.ai/install.sh | bash"
        [[ "$DRY_RUN" != true ]] && curl -fsSL https://claude.ai/install.sh | bash
    else
        ok "claude ya instalado: $(claude --version 2>/dev/null || echo '?')"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        would "claude plugin marketplace add codelabs https://codelabs.studio/plugins/marketplace.json"
        local p
        for p in "${PACK_PLUGINS[@]}"; do
            would "claude plugin install ${p}@codelabs"
        done
        return
    fi

    if ! has_cmd claude; then
        warn "claude sigue sin estar disponible; instálalo a mano y repite 'codelabs-setup enroll'"
        return
    fi

    claude plugin marketplace add codelabs https://codelabs.studio/plugins/marketplace.json || true
    local p
    for p in "${PACK_PLUGINS[@]}"; do
        log "Plugin: $p"
        claude plugin install "${p}@codelabs" || warn "Plugin $p falló (sigo con el resto)"
    done
}

step_claude_md() {
    local flavor="$1"
    if [[ -z "$flavor" ]]; then
        return 0
    fi
    log "CLAUDE.md ($flavor)"
    local claude_dir="$HOME/.claude"
    run mkdir -p "$claude_dir"
    if [[ -f "$claude_dir/CLAUDE.md" ]]; then
        info "CLAUDE.md ya existe en $claude_dir: no lo piso (podría llevar reglas personales)"
        return
    fi
    local template="$SETUP_ROOT/templates/CLAUDE.md.${flavor}"
    [[ -f "$template" ]] || { warn "Plantilla no encontrada: $template"; return; }

    if [[ "$DRY_RUN" == true ]]; then
        would "copiar $template -> $claude_dir/CLAUDE.md"
        if [[ "$flavor" == personal ]]; then
            would "sustituir {{USER_NAME}}/{{USER_EMAIL}} a partir de --person ($MACHINE_PERSON)"
        fi
        return 0
    fi

    cp "$template" "$claude_dir/CLAUDE.md"
    if [[ "$flavor" == personal ]]; then
        local display="${MACHINE_PERSON%%@*}"
        display="${display//./ }"
        local esc_display esc_email
        esc_display="$(printf '%s' "$display" | sed 's/[&/\]/\\&/g')"
        esc_email="$(printf '%s' "$MACHINE_PERSON" | sed 's/[&/\]/\\&/g')"
        sed -i.bak "s/{{USER_NAME}}/${esc_display}/g; s/{{USER_EMAIL}}/${esc_email}/g" "$claude_dir/CLAUDE.md"
        rm -f "$claude_dir/CLAUDE.md.bak"
    fi
    ok "CLAUDE.md instalado ($flavor)"
}

# Fusión segura (vía jq) de hooks y enabledPlugins en settings.json. Nunca
# toca permissions, mcpServers ni cualquier otra clave existente; sigue el
# mismo patrón de merge quirúrgico del instalador de hooks de MemoryFirst.
step_settings_merge() {
    if [[ ${#PACK_PLUGINS[@]} -eq 0 ]]; then
        return 0
    fi
    log "settings.json: hooks y plugins del pack"
    ensure_jq
    local claude_dir="$HOME/.claude"
    local settings="$claude_dir/settings.json"

    if [[ "$DRY_RUN" == true ]]; then
        would "instalar $SETUP_ROOT/templates/hooks/{anti-sycophancy.py,sync-skills-cache.sh} en $claude_dir/hooks/"
        would "fusionar (jq) hooks.Stop / hooks.PostToolUse y enabledPlugins en $settings, sin tocar el resto"
        return
    fi

    run mkdir -p "$claude_dir/hooks"
    cp "$SETUP_ROOT/templates/hooks/anti-sycophancy.py" "$claude_dir/hooks/"
    cp "$SETUP_ROOT/templates/hooks/sync-skills-cache.sh" "$claude_dir/hooks/"
    chmod +x "$claude_dir/hooks/anti-sycophancy.py" "$claude_dir/hooks/sync-skills-cache.sh"

    [[ -f "$settings" ]] || echo '{}' > "$settings"
    if ! jq empty "$settings" 2>/dev/null; then
        warn "$settings no es JSON válido; no lo toco (arréglalo a mano y repite)"
        return
    fi
    cp "$settings" "$settings.bak.codelabs-setup"

    local antisyc="$claude_dir/hooks/anti-sycophancy.py"
    local sync="$claude_dir/hooks/sync-skills-cache.sh"
    local tmp; tmp="$(mktemp)"
    if jq \
        --arg antisyc "$antisyc" \
        --arg sync "$sync" \
        '
        .hooks = (.hooks // {})
        | .hooks.Stop = ((.hooks.Stop // [])
            | if any(.[]; (.hooks // []) | any(.command? == $antisyc))
              then . else . + [{hooks: [{type: "command", command: $antisyc}]}] end)
        | .hooks.PostToolUse = ((.hooks.PostToolUse // [])
            | if any(.[]; (.hooks // []) | any(.command? == $sync))
              then .
              elif any(.[]; .matcher? == "Write|Edit")
              then map(if .matcher? == "Write|Edit"
                       then .hooks = ((.hooks // []) + [{type: "command", command: $sync}])
                       else . end)
              else . + [{matcher: "Write|Edit", hooks: [{type: "command", command: $sync}]}]
              end)
        ' "$settings" > "$tmp" && jq empty "$tmp" 2>/dev/null
    then
        mv "$tmp" "$settings"
    else
        rm -f "$tmp"
        warn "fusión de hooks falló; settings.json no se tocó"
    fi

    local plugins_json="{" first=true p
    for p in "${PACK_PLUGINS[@]}"; do
        $first || plugins_json+=","
        plugins_json+="\"${p}@codelabs\":true"
        first=false
    done
    plugins_json+="}"
    tmp="$(mktemp)"
    if jq --argjson plugins "$plugins_json" \
        '.enabledPlugins = ((.enabledPlugins // {}) + $plugins)' \
        "$settings" > "$tmp" && jq empty "$tmp" 2>/dev/null
    then
        mv "$tmp" "$settings"
    else
        rm -f "$tmp"
        warn "fusión de enabledPlugins falló"
    fi

    ok "settings.json actualizado (copia previa: $settings.bak.codelabs-setup)"
}

# ---------------------------------------------------------------------------
# Hooks de MemoryFirst
# ---------------------------------------------------------------------------

step_memoryfirst_hooks() {
    log "Hooks de MemoryFirst (Claude Code <-> brain)"
    if [[ ! -x "$MEMORYFIRST_HOOKS_DIR/install.sh" ]]; then
        warn "No encuentro $MEMORYFIRST_HOOKS_DIR/install.sh en esta máquina; omito (clona memoryfirst si esta también es una máquina de desarrollo del repo)"
        return
    fi
    if [[ "$DRY_RUN" == true ]]; then
        would "bash $MEMORYFIRST_HOOKS_DIR/install.sh"
        return
    fi
    ensure_jq
    bash "$MEMORYFIRST_HOOKS_DIR/install.sh"
    info "Credenciales de MemoryFirst: ejecuta aparte '$MEMORYFIRST_HOOKS_DIR/install.sh --credentials' cuando quieras darlas de alta (nunca se piden ni se imprimen aquí)."
}

# ---------------------------------------------------------------------------
# Clonar SOLO los repos del pack, y generar .env de desarrollo desde plantilla
# ---------------------------------------------------------------------------

step_clone_repos() {
    local repos=("$@")
    if [[ ${#repos[@]} -eq 0 ]]; then
        info "Sin repos que clonar para este pack"
        return
    fi
    log "Clonando repos (Forgejo, requiere Tailscale conectado)"
    run mkdir -p "$CODE_ROOT"
    local repo dest
    for repo in "${repos[@]}"; do
        repo="$(printf '%s' "$repo" | tr -d '[:space:]')"
        [[ -z "$repo" ]] && continue
        dest="$CODE_ROOT/$repo"
        if [[ -d "$dest/.git" ]]; then
            ok "repo ya clonado: $repo"
            continue
        fi
        log "  $repo"
        run git clone "${FORGEJO_HOST}/${FORGEJO_ORG}/${repo}.git" "$dest"
    done
}

# Genera un .env de DESARROLLO a partir de .env.example/.sample/.template/.dist.
# Nunca lee ni copia un .env real. Las claves sin valor de desarrollo quedan
# marcadas con CHANGEME_DEV_<CLAVE> y se avisa al final, nunca se inventa un
# valor plausible.
step_env_templates() {
    local repos=("$@")
    if [[ ${#repos[@]} -eq 0 ]]; then
        return 0
    fi
    log "Generando .env de desarrollo desde plantilla (si el repo la trae)"
    local repo dir template dest
    for repo in "${repos[@]}"; do
        repo="$(printf '%s' "$repo" | tr -d '[:space:]')"
        dir="$CODE_ROOT/$repo"
        [[ -d "$dir" ]] || continue
        for template in "$dir"/.env.example "$dir"/.env.sample "$dir"/.env.template "$dir"/.env.dist; do
            [[ -f "$template" ]] || continue
            dest="$dir/.env"
            if [[ -f "$dest" ]]; then
                info "$repo: .env ya existe, no lo toco"
                continue
            fi
            if [[ "$DRY_RUN" == true ]]; then
                would "$repo: generar .env de desarrollo desde $(basename "$template") (marcador CHANGEME_DEV_<CLAVE> en lo que falte)"
                continue
            fi
            log "  $repo: .env <- $(basename "$template")"
            : > "$dest"
            local missing=()
            local line key val
            while IFS= read -r line || [[ -n "$line" ]]; do
                if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                    key="${line%%=*}"
                    val="${line#*=}"
                    case "$val" in
                        ""|changeme*|CHANGEME*|your-*|YOUR_*|xxx*|XXX*)
                            printf '%s=CHANGEME_DEV_%s\n' "$key" "$key" >> "$dest"
                            missing+=("$key")
                            ;;
                        *)
                            printf '%s\n' "$line" >> "$dest"
                            ;;
                    esac
                else
                    printf '%s\n' "$line" >> "$dest"
                fi
            done < "$template"
            chmod 600 "$dest"
            if [[ ${#missing[@]} -gt 0 ]]; then
                warn "$repo/.env: rellena a mano con valores de DESARROLLO (nunca de producción): ${missing[*]}"
            fi
        done
    done
}

# ---------------------------------------------------------------------------
# Accesos directos (marketer / learner): sin código, solo enlaces al hub,
# a partners y a AlmaOS.
# ---------------------------------------------------------------------------

step_shortcuts() {
    if [[ ${#PACK_SHORTCUTS[@]} -eq 0 ]]; then
        return 0
    fi
    local dest_dir="$HOME/Codelabs Links"
    log "Accesos directos"
    run mkdir -p "$dest_dir"
    local entry name url file
    for entry in "${PACK_SHORTCUTS[@]}"; do
        name="${entry%%:*}"
        url="${entry#*:}"
        if [[ "$HW_OS" == macos ]]; then
            file="$dest_dir/$name.webloc"
            if [[ "$DRY_RUN" == true ]]; then
                would "crear '$file' -> $url"
                continue
            fi
            cat > "$file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>URL</key><string>${url}</string></dict></plist>
EOF
        else
            file="$dest_dir/$name.desktop"
            if [[ "$DRY_RUN" == true ]]; then
                would "crear '$file' -> $url"
                continue
            fi
            cat > "$file" <<EOF
[Desktop Entry]
Type=Link
Name=${name}
URL=${url}
Icon=text-html
EOF
            chmod +x "$file"
        fi
        ok "acceso directo: $name -> $url"
    done
}
