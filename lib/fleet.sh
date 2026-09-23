#!/usr/bin/env bash
# lib/fleet.sh — registro de la máquina en la flota de MemoryFirst.
#
# POST /v1/fleet/machines/enroll (https://api.memoryfirst.ai) con el perfil
# de hardware y capacidades (nada sensible: modelo, RAM, CPU, SO,
# capacidades deducidas). Solo lo puede llamar el owner (contrato:
# memoryfirst/apps/api/README.md, y el esquema real en
# memoryfirst/apps/api/src/routes/work.ts EnrollSchema: name, personId?,
# tags?, hw?, capabilities?, tailscaleNode? — de ahí que el payload use "hw"
# y "personId", no "hardware" ni "person"). La llamada exige
# `Authorization: Bearer <clave de owner>`; el token que la API devuelve se
# muestra UNA vez y volver a enrolar la misma máquina revoca el anterior.
#
# La clave de owner (mf_live_…) se lee exactamente de donde la guarda
# packages/claude-hooks/install.sh (--credentials): Keychain en macOS
# (servicio codelabs/memoryfirst/internal_api_key, cuenta memoryfirst) o
# MEMORYFIRST_API_KEY en ~/.config/memoryfirst/hooks.env en Linux. Se lee a
# una variable DENTRO de una función y nunca se imprime; viaja a curl en un
# fichero de cabecera 0600 (`-H "@fichero"`, ver man curl), nunca por argv
# (quedaría entero en `ps`) ni por stdin de un heredoc compartido con otra
# cosa.
#
# El token de máquina que devuelve el enroll se guarda EXACTAMENTE donde lo
# leen los hooks de MemoryFirst (packages/claude-hooks/install.sh
# --machine-token): Keychain en macOS (servicio
# codelabs/memoryfirst/machine_token, cuenta memoryfirst) o un fichero 0600
# en Linux (~/.config/memoryfirst/hooks.env). NUNCA pasa por argv de un
# proceso ajeno: en macOS se alimenta a `security -i` por stdin (un
# heredoc), nunca como `security ... -w "$token"` en la línea de comandos —
# eso queda entero en `ps` para cualquiera en la máquina. Y su salida se
# silencia (`>/dev/null 2>&1`): si `security -i` no entiende la línea la
# repite en pantalla, secreto incluido, así que solo cuenta el código de
# salida (mismo arreglo que memoryfirst/packages/claude-hooks/install.sh,
# función keychain_set, commit 2d67eea).

FLEET_API_URL="${FLEET_API_URL:-https://api.memoryfirst.ai}"
MACHINE_CONFIG_DIR="${MACHINE_CONFIG_DIR:-$HOME/.config/codelabs}"
MACHINE_PROFILE_FILE="$MACHINE_CONFIG_DIR/machine.json"

# Mismos nombres que usa memoryfirst/packages/claude-hooks/install.sh, para
# que los hooks encuentren el token sin configuración adicional.
MACHINE_TOKEN_KC_SERVICE="${MACHINE_TOKEN_KC_SERVICE:-codelabs/memoryfirst/machine_token}"
MACHINE_TOKEN_KC_ACCOUNT="${MACHINE_TOKEN_KC_ACCOUNT:-memoryfirst}"
MACHINE_TOKEN_ENV_FILE="${MACHINE_TOKEN_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/memoryfirst/hooks.env}"
# Ruta de un llavero EXPLÍCITO para el add-generic-password del token de
# máquina. Vacío (por defecto, uso normal): security usa el llavero por
# defecto del usuario, igual que siempre. Los tests la fijan a un llavero de
# usar-y-tirar creado con `security create-keychain`, para no tocar nunca el
# llavero real ni abrir un diálogo del sistema si el proceso no tiene sesión
# de llavero (2026-09-23: un test sin esto disparó el diálogo "Llavero no
# encontrado" en la sesión real de Jose).
MACHINE_TOKEN_KEYCHAIN="${MACHINE_TOKEN_KEYCHAIN:-}"

# Prefijo/cuenta del Llavero y fichero de hooks: igual que
# packages/claude-hooks/install.sh (KC_PREFIX/KC_ACCOUNT/ENV_FILE), para leer
# la clave de owner (internal_api_key) que ya usan los hooks de Claude Code.
MF_KEYCHAIN_PREFIX="${MEMORYFIRST_KEYCHAIN_PREFIX:-codelabs/memoryfirst}"
MF_KEYCHAIN_ACCOUNT="${MEMORYFIRST_KEYCHAIN_ACCOUNT:-memoryfirst}"
MF_HOOKS_ENV_FILE="${MEMORYFIRST_HOOKS_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/memoryfirst/hooks.env}"
# Mismo mecanismo que MACHINE_TOKEN_KEYCHAIN, pero para el find-generic-password
# de resolve_owner_api_key. Vacío = llavero por defecto (uso normal).
MF_KEYCHAIN_FILE="${MF_KEYCHAIN_FILE:-}"

build_enroll_payload() {
    cat <<EOF
{
  "name": "$(json_escape "$MACHINE_NAME")",
  "personId": "$(json_escape "$MACHINE_PERSON")",
  "tags": ["$(json_escape "pack:${PACK_NAME}")"],
  "hw": $(hardware_json),
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

# resolve_owner_api_key — deja la clave de owner (mf_live_…) en la variable
# global OWNER_API_KEY, leída del Llavero (macOS) o del fichero de hooks de
# MemoryFirst (Linux/CI), en ese orden — igual que hacen los hooks de
# claude-hooks (memoryfirst-session-start.sh y compañía). Nunca la imprime:
# el fichero de hooks se fuente dentro de un subshell y solo su valor sale
# por `printf` a la sustitución de comandos que la captura en la variable.
#
# OJO set -e: bin/codelabs-setup corre con `set -euo pipefail`. Un "cmd &&
# cmd" o "cmd || cmd" como ÚLTIMA sentencia de una función se evalúa bien por
# dentro, pero dado que ese es también el código de salida de la FUNCIÓN, y
# esta se invoca como sentencia suelta ("resolve_owner_api_key", sin
# envolver en if/&&/||), un resultado "falso" ahí aborta el script entero SIN
# ningún mensaje (así se depuró este mismo fichero: la clave se leía bien del
# Llavero, pero la función terminaba en un "[[ -z ... ]] && …" que daba
# falso — clave ya resuelta — y esa vuelta con estado 1 mataba el script justo
# después de "Registro de la máquina…", con el cuerpo de la respuesta y el
# token que hubiera devuelto la API perdidos en un fichero temporal huérfano).
# Por eso aquí todo es if/fi explícito y se cierra con un "return 0" literal.
resolve_owner_api_key() {
    OWNER_API_KEY=""
    if has_cmd security; then
        # Llavero explícito solo si MF_KEYCHAIN_FILE lo fija (tests); en uso
        # normal, array vacío = security usa el llavero por defecto de
        # siempre, sin cambio de comportamiento.
        local -a kc_file=()
        if [[ -n "$MF_KEYCHAIN_FILE" ]]; then
            kc_file=("$MF_KEYCHAIN_FILE")
        fi
        OWNER_API_KEY="$(security find-generic-password -s "${MF_KEYCHAIN_PREFIX}/internal_api_key" -a "${MF_KEYCHAIN_ACCOUNT}" -w "${kc_file[@]}" 2>/dev/null || true)"
    fi
    if [[ -z "$OWNER_API_KEY" ]]; then
        OWNER_API_KEY="$(
            if [[ -r "$MF_HOOKS_ENV_FILE" ]]; then
                . "$MF_HOOKS_ENV_FILE"
            fi
            printf '%s' "${MEMORYFIRST_API_KEY:-}"
        )"
    fi
    if [[ -z "$OWNER_API_KEY" ]]; then
        OWNER_API_KEY="${MEMORYFIRST_API_KEY:-}"
    fi
    return 0
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
        # El llavero destino es un argumento posicional más de la línea que
        # entiende `security -i`; se añade solo si MACHINE_TOKEN_KEYCHAIN lo
        # fija (tests, con un llavero de usar-y-tirar), nunca el llavero real.
        local sec_cmd="add-generic-password -U -s \"${MACHINE_TOKEN_KC_SERVICE}\" -a \"${MACHINE_TOKEN_KC_ACCOUNT}\" -w \"${esc}\""
        if [[ -n "$MACHINE_TOKEN_KEYCHAIN" ]]; then
            sec_cmd+=" \"${MACHINE_TOKEN_KEYCHAIN}\""
        fi
        # Salida silenciada: si `security -i` no entiende la línea la repite
        # en pantalla, secreto incluido. Solo cuenta el código de salida
        # (mismo arreglo que memoryfirst/packages/claude-hooks/install.sh,
        # función keychain_set, commit 2d67eea). El comando viaja por un pipe
        # (no por argv), igual de seguro que el heredoc que sustituye.
        if printf '%s\n' "$sec_cmd" | security -i >/dev/null 2>&1; then
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

# post_enroll <payload> <api_key> <resp_body_file> — hace el POST autenticado
# y devuelve por stdout el código HTTP. Escribe el cuerpo de la respuesta en
# <resp_body_file>, que crea y limpia el LLAMADOR (nunca una variable global
# puesta desde aquí: post_enroll se invoca como "$(post_enroll …)", eso corre
# en un subshell, y una asignación global hecha ahí dentro no sobrevive a la
# vuelta — bajo `set -u` el primer acceso posterior revienta el script con
# "unbound variable", cosa que en el fondo dejaba huérfano en /tmp el propio
# fichero con el token en claro). La clave viaja a curl en un fichero de
# cabecera 0600 (-H "@fichero", ver "man curl"), nunca por argv ni por
# stdin: un fichero temporal por llamada, borrado con un trap de retorno de
# la función aunque curl falle.
post_enroll() {
    local payload="$1" api_key="${2:-}" resp_body_file="$3"
    local header_file=""
    if [[ -n "$api_key" ]]; then
        header_file="$(mktemp)"
        chmod 600 "$header_file"
        printf 'Authorization: Bearer %s\n' "$api_key" > "$header_file"
    fi
    # shellcheck disable=SC2064
    trap "[[ -n '${header_file}' ]] && rm -f '${header_file}'" RETURN

    local -a auth_args=()
    if [[ -n "$header_file" ]]; then
        auth_args=(-H "@${header_file}")
    fi

    curl -sS -o "$resp_body_file" -w '%{http_code}' -X POST \
        -H 'Content-Type: application/json' \
        "${auth_args[@]}" \
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
        would "se autenticaría con Authorization: Bearer <clave de owner>, leída del Llavero ($MF_KEYCHAIN_PREFIX/internal_api_key) o de $MF_HOOKS_ENV_FILE, sin imprimirla; sin esa clave no se llega a llamar a la API"
        would "si 404: guardar el perfil en $MACHINE_PROFILE_FILE y dejar 'codelabs-setup register' para reintentar"
        if [[ "$HW_OS" == macos ]]; then
            would "si la respuesta trae token: guardarlo en el Llavero ($MACHINE_TOKEN_KC_SERVICE / $MACHINE_TOKEN_KC_ACCOUNT) vía 'security -i' por stdin, con su salida silenciada, nunca por argv ni impreso"
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

    resolve_owner_api_key
    if [[ -z "$OWNER_API_KEY" ]]; then
        warn "No se encontró la clave de owner de MemoryFirst (Llavero $MF_KEYCHAIN_PREFIX/internal_api_key, o MEMORYFIRST_API_KEY en $MF_HOOKS_ENV_FILE): el alta de flota es solo para el owner y no se puede autenticar. Guardo el perfil para reintentar con 'codelabs-setup register' cuando la clave esté disponible."
        save_local_profile "$payload"
        return
    fi

    local resp_body_file; resp_body_file="$(mktemp)"
    local http_code
    http_code="$(post_enroll "$payload" "$OWNER_API_KEY" "$resp_body_file")"

    case "$http_code" in
        2??)
            local token; token="$(extract_token "$resp_body_file")"
            if [[ -n "$token" && "$token" != "null" ]]; then
                store_machine_token "$token"
            fi
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
            warn "La API de flota rechazó el registro (HTTP $http_code): la clave usada no es de owner, o no es válida. Guardo el perfil para reintentar con 'codelabs-setup register' con una clave de owner correcta."
            save_local_profile "$payload"
            ;;
        *)
            warn "Registro de flota falló (HTTP $http_code) — guardo el perfil para reintentar."
            save_local_profile "$payload"
            ;;
    esac
    rm -f "$resp_body_file"
}

retry_register() {
    [[ -f "$MACHINE_PROFILE_FILE" ]] || die "No hay perfil guardado en $MACHINE_PROFILE_FILE. Ejecuta primero 'codelabs-setup enroll' o 'codelabs-setup register --name … --person … --pack …'."
    require_cmd curl "curl no está disponible; no se puede reintentar el registro"

    resolve_owner_api_key
    if [[ -z "$OWNER_API_KEY" ]]; then
        warn "No se encontró la clave de owner de MemoryFirst (Llavero $MF_KEYCHAIN_PREFIX/internal_api_key, o MEMORYFIRST_API_KEY en $MF_HOOKS_ENV_FILE): el alta de flota es solo para el owner y no se puede autenticar. Repite cuando la clave esté disponible."
        return
    fi

    log "Reintentando registro de flota con el perfil guardado ($MACHINE_PROFILE_FILE)"
    local payload; payload="$(cat "$MACHINE_PROFILE_FILE")"
    local resp_body_file; resp_body_file="$(mktemp)"
    local http_code
    http_code="$(post_enroll "$payload" "$OWNER_API_KEY" "$resp_body_file")"
    case "$http_code" in
        2??)
            local token; token="$(extract_token "$resp_body_file")"
            if [[ -n "$token" && "$token" != "null" ]]; then
                store_machine_token "$token"
            fi
            ok "Máquina registrada (HTTP $http_code). El token solo se muestra una vez; un nuevo enroll de esta máquina revocaría este."
            ;;
        404) warn "Sigue en 404: la API de flota no responde en esa ruta todavía." ;;
        000) warn "Sin conectividad con ${FLEET_API_URL}." ;;
        401|403) warn "La API rechazó el reintento (HTTP $http_code): la clave usada no es de owner, o no es válida." ;;
        *) warn "Sigue fallando (HTTP $http_code)." ;;
    esac
    rm -f "$resp_body_file"
}
