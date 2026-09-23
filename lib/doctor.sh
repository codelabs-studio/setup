#!/usr/bin/env bash
# lib/doctor.sh — `codelabs-setup doctor`: qué está instalado y qué falta.
# Nunca muestra el VALOR de una credencial, solo si existe y sus permisos.

doctor_check_cmd() {
    local cmd="$1" note="${2:-}"
    if has_cmd "$cmd"; then
        ok "$cmd: $($cmd --version 2>/dev/null | head -1 || echo instalado) $note"
    else
        warn "$cmd: no encontrado $note"
    fi
}

run_doctor() {
    detect_hardware
    detect_capabilities

    echo "codelabs-setup doctor"
    echo "======================"
    hardware_summary
    echo
    capabilities_summary
    echo

    echo "Herramientas:"
    doctor_check_cmd tailscale
    doctor_check_cmd git
    doctor_check_cmd node
    doctor_check_cmd pnpm
    doctor_check_cmd python3
    doctor_check_cmd docker
    doctor_check_cmd jq
    doctor_check_cmd java "(para Maestro)"
    doctor_check_cmd maestro
    doctor_check_cmd claude
    echo

    echo "Claude Code:"
    if [[ -f "$HOME/.claude/settings.json" ]]; then
        if has_cmd jq; then
            local n
            n="$(jq -r '.enabledPlugins // {} | length' "$HOME/.claude/settings.json" 2>/dev/null || echo '?')"
            ok "settings.json presente ($n plugins habilitados)"
        else
            ok "settings.json presente"
        fi
    else
        warn "settings.json no encontrado en ~/.claude/"
    fi
    if [[ -f "$HOME/.claude/CLAUDE.md" ]]; then
        ok "CLAUDE.md presente"
    else
        warn "CLAUDE.md no encontrado en ~/.claude/"
    fi
    if [[ -x "$MEMORYFIRST_HOOKS_DIR/install.sh" ]]; then
        ok "hooks de MemoryFirst disponibles en $MEMORYFIRST_HOOKS_DIR"
    else
        warn "no encuentro los hooks de MemoryFirst en $MEMORYFIRST_HOOKS_DIR"
    fi
    echo

    echo "Flota (MemoryFirst):"
    # El valor nunca se lee ni se muestra aquí: solo se comprueba que el
    # ítem existe (macOS) o que el fichero está presente con los permisos
    # correctos (Linux) — igual que hace el propio instalador de hooks.
    if [[ "$HW_OS" == macos ]]; then
        if has_cmd security && security find-generic-password -s "$MACHINE_TOKEN_KC_SERVICE" -a "$MACHINE_TOKEN_KC_ACCOUNT" >/dev/null 2>&1; then
            ok "token de máquina presente en el Llavero ($MACHINE_TOKEN_KC_SERVICE); el valor nunca se muestra"
        else
            warn "sin token de máquina en el Llavero; ejecuta 'codelabs-setup enroll' o 'codelabs-setup register'"
        fi
    else
        if [[ -f "$MACHINE_TOKEN_ENV_FILE" ]]; then
            local perm
            perm="$(stat -c '%a' "$MACHINE_TOKEN_ENV_FILE" 2>/dev/null || echo '?')"
            if [[ "$perm" == "600" ]]; then
                ok "fichero de token de máquina presente (permisos 600; el valor nunca se muestra)"
            else
                warn "fichero de token de máquina presente pero con permisos $perm (debería ser 600) — corrígelo: chmod 600 '$MACHINE_TOKEN_ENV_FILE'"
            fi
        else
            warn "sin token de máquina; ejecuta 'codelabs-setup enroll' o 'codelabs-setup register'"
        fi
    fi
    if [[ -f "$MACHINE_PROFILE_FILE" ]]; then
        ok "perfil de máquina guardado en $MACHINE_PROFILE_FILE"
    else
        warn "sin perfil de máquina guardado todavía"
    fi
}
