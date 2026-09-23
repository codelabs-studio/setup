#!/usr/bin/env bash
# lib/fleet.sh — registro de la máquina en la flota de MemoryFirst.
#
# POST /v1/fleet/machines/enroll (https://api.memoryfirst.ai) con el perfil
# de hardware y capacidades (nada sensible: modelo, RAM, CPU, SO,
# capacidades deducidas). Solo lo puede llamar el owner; el token que
# devuelve se muestra UNA vez y volver a enrolar la misma máquina revoca el
# anterior (contrato: memoryfirst/apps/api/README.md).
#
# El token se guarda EXACTAMENTE donde lo leen los hooks de MemoryFirst
# (packages/claude-hooks/install.sh --machine-token): Keychain en macOS
# (servicio codelabs/memoryfirst/machine_token, cuenta memoryfirst) o un
# fichero 0600 en Linux (~/.config/memoryfirst/hooks.env). NUNCA pasa por
# argv de un proceso ajeno: en macOS se alimenta a `security -i` por stdin
# (un heredoc), nunca como `security ... -w "$token"` en la línea de
# comandos — eso queda entero en `ps` para cualquiera en la máquina.

FLEET_API_URL="${FLEET_API_URL:-https://api.memoryfirst.ai}"
MACHINE_CONFIG_DIR="${MACHINE_CONFIG_DIR:-$HOME/.config/codelabs}"
MACHINE_PROFILE_FILE="$MACHINE_CONFIG_DIR/machine.json"

# Mismos nombres que usa memoryfirst/packages/claude-hooks/install.sh, para
# que los hooks encuentren el token sin configuración adicional.
MACHINE_TOKEN_KC_SERVICE="${MACHINE_TOKEN_KC_SERVICE:-codelabs/memoryfirst/machine_token}"
MACHINE_TOKEN_KC_ACCOUNT="${MACHINE_TOKEN_KC_ACCOUNT:-memoryfirst}"
MACHINE_TOKEN_ENV_FILE="${MACHINE_TOKEN_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/memoryfirst/hooks.env}"

build_enroll_payload() {
    cat <<EOF
{
  "name": "$(json_escape "$MACHINE_NAME")",
  "person": "$(json_escape "$MACHINE_PERSON")",
  "pack": "$(json_escape "$PACK_NAME")",
  "hardware": $(hardware_json),
  "capabilities": $(capabilities_json)
}
EOF
}

save_local_profile() {
    local payload="$1"
    mkdir -p "$MACHINE_CONFIG_DIR"
    chmod 700 "$MACHINE_CONFIG_DIR" 2>/dev/null || true
    printf '%s' "$payload" > "$MACHINE_PROFILE_FILE"
    chmod 600 "$MACHINE_PROFILE_FILE"
    info "Perfil guardado en $MACHINE_PROFILE_FILE"
}

# store_machine_token <token> — nunca lo imprime, nunca lo pasa por argv.
store_machine_token() {
    local token="$1"
    [[ -n "$token" ]] || return 0
    if has_cmd security; then
        # security -i lee comandos por stdin (modo "interactivo"/batch): el
        # token viaja en el heredoc, no como argumento del proceso `security`.
        # Ojo: el parser de `security -i` no admite comillas simples como
        # cita (las deja literales y rompe el parseo); se cita con comillas
        # dobles, escapando \ y " dentro del valor.
        local esc="${token//\\/\\\\}"
        esc="${esc//\"/\\\"}"
        if security -i <<SEC
add-generic-password -U -s "${MACHINE_TOKEN_KC_SERVICE}" -a "${MACHINE_TOKEN_KC_ACCOUNT}" -w "${esc}"
SEC
        then
            ok "Token de máquina guardado en el Llavero ($MACHINE_TOKEN_KC_SERVICE / $MACHINE_TOKEN_KC_ACCOUNT). No se imprime."
        else
            warn "No se pudo guardar el token en el Llavero; repite 'codelabs-setup register' o guárdalo a mano con los hooks de MemoryFirst (--machine-token)."
        fi
    else
        mkdir -p "$(dirname "$MACHINE_TOKEN_ENV_FILE")"
        chmod 700 "$(dirname "$MACHINE_TOKEN_ENV_FILE")" 2>/dev/null || true
        (
            umask 177
            touch "$MACHINE_TOKEN_ENV_FILE"
            # Sustituye una línea previa sin imprimir nunca el valor.
            grep -v '^MEMORYFIRST_MACHINE_TOKEN=' "$MACHINE_TOKEN_ENV_FILE" > "$MACHINE_TOKEN_ENV_FILE.tmp" 2>/dev/null || true
            printf 'MEMORYFIRST_MACHINE_TOKEN=%s\n' "$token" >> "$MACHINE_TOKEN_ENV_FILE.tmp"
            mv "$MACHINE_TOKEN_ENV_FILE.tmp" "$MACHINE_TOKEN_ENV_FILE"
            chmod 600 "$MACHINE_TOKEN_ENV_FILE"
        )
        ok "Token de máquina guardado en $MACHINE_TOKEN_ENV_FILE (0600). No se imprime."
    fi
}

# post_enroll <payload> — hace el POST y devuelve por stdout el código HTTP.
# El cuerpo de la respuesta queda en $RESP_BODY_FILE (global, la limpia el
# llamador).
post_enroll() {
    local payload="$1"
    RESP_BODY_FILE="$(mktemp)"
    curl -sS -o "$RESP_BODY_FILE" -w '%{http_code}' -X POST \
        -H 'Content-Type: application/json' \
        --max-time 15 \
        -d "$payload" \
        "${FLEET_API_URL}/v1/fleet/machines/enroll" 2>/dev/null || echo "000"
}

extract_token() {
    local body_file="$1"
    has_cmd jq || return 0
    jq -r '.token // .machine_token // empty' "$body_file" 2>/dev/null || true
}

register_machine() {
    log "Registro de la máquina en MemoryFirst (flota)"

    if [[ "$DRY_RUN" == true ]]; then
        would "POST ${FLEET_API_URL}/v1/fleet/machines/enroll  (perfil de hardware y capacidades, sin secretos; solo el owner puede llamarla)"
        would "si 404: guardar el perfil en $MACHINE_PROFILE_FILE y dejar 'codelabs-setup register' para reintentar"
        if [[ "$HW_OS" == macos ]]; then
            would "si la respuesta trae token: guardarlo en el Llavero ($MACHINE_TOKEN_KC_SERVICE / $MACHINE_TOKEN_KC_ACCOUNT) vía 'security -i' por stdin, nunca por argv ni impreso"
        else
            would "si la respuesta trae token: guardarlo 0600 en $MACHINE_TOKEN_ENV_FILE (MEMORYFIRST_MACHINE_TOKEN=…), nunca impreso"
        fi
        would "re-enrolar esta misma máquina revoca el token anterior (contrato de la API)"
        return
    fi

    local payload; payload="$(build_enroll_payload)"

    if ! has_cmd curl; then
        warn "curl no está disponible; guardo el perfil para registrar luego"
        save_local_profile "$payload"
        return
    fi

    local http_code
    http_code="$(post_enroll "$payload")"

    case "$http_code" in
        2??)
            local token; token="$(extract_token "$RESP_BODY_FILE")"
            [[ -n "$token" && "$token" != "null" ]] && store_machine_token "$token"
            save_local_profile "$payload"
            ok "Máquina registrada en la flota (HTTP $http_code). El token solo se muestra una vez: si vuelves a enrolar esta máquina, el anterior queda revocado."
            ;;
        404)
            warn "${FLEET_API_URL}/v1/fleet/machines/enroll dio 404 — puede que la API de flota aún no esté desplegada en esta red."
            save_local_profile "$payload"
            info "Cuando esté disponible: codelabs-setup register"
            ;;
        000)
            warn "No hay conectividad con ${FLEET_API_URL} (¿Tailscale/red?) — guardo el perfil para reintentar."
            save_local_profile "$payload"
            ;;
        401|403)
            warn "La API de flota rechazó el registro (HTTP $http_code): el enroll es solo para el owner. Pide a Jose que lo ejecute o que te dé una vía autorizada."
            save_local_profile "$payload"
            ;;
        *)
            warn "Registro de flota falló (HTTP $http_code) — guardo el perfil para reintentar."
            save_local_profile "$payload"
            ;;
    esac
    rm -f "$RESP_BODY_FILE"
}

retry_register() {
    [[ -f "$MACHINE_PROFILE_FILE" ]] || die "No hay perfil guardado en $MACHINE_PROFILE_FILE. Ejecuta primero 'codelabs-setup enroll'."
    require_cmd curl "curl no está disponible; no se puede reintentar el registro"
    log "Reintentando registro de flota con el perfil guardado ($MACHINE_PROFILE_FILE)"
    local payload; payload="$(cat "$MACHINE_PROFILE_FILE")"
    local http_code
    http_code="$(post_enroll "$payload")"
    case "$http_code" in
        2??)
            local token; token="$(extract_token "$RESP_BODY_FILE")"
            [[ -n "$token" && "$token" != "null" ]] && store_machine_token "$token"
            ok "Máquina registrada (HTTP $http_code). El token solo se muestra una vez; un nuevo enroll de esta máquina revocaría este."
            ;;
        404) warn "Sigue en 404: la API de flota no responde en esa ruta todavía." ;;
        000) warn "Sin conectividad con ${FLEET_API_URL}." ;;
        401|403) warn "La API rechazó el reintento (HTTP $http_code): el enroll es solo para el owner." ;;
        *) warn "Sigue fallando (HTTP $http_code)." ;;
    esac
    rm -f "$RESP_BODY_FILE"
}
