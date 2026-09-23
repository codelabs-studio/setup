#!/usr/bin/env bash
# tests/test_fleet.sh — flota de MemoryFirst (lib/fleet.sh): registro con
# autenticación de owner y guardado silencioso del token de máquina.
# Uso: bash tests/test_fleet.sh
set -uo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$SETUP_ROOT/bin/codelabs-setup"

FAILURES=0
assert() {
    local desc="$1" cond="$2"
    if eval "$cond"; then
        printf 'PASS %s\n' "$desc"
    else
        printf 'FAIL %s   (condición: %s)\n' "$desc" "$cond"
        FAILURES=$((FAILURES + 1))
    fi
}

# ── 1. dry-run: register muestra que SE AUTENTICARÍA, sin tener la clave ──
fake_home="$(mktemp -d)"
OUT="$(HOME="$fake_home" MEMORYFIRST_API_KEY= "$BIN" register \
    --name test-fleet --person 00000000-0000-0000-0000-000000000000 \
    --pack founder --dry-run 2>&1)"
RC=$?
LEFTOVER="$(find "$fake_home" -mindepth 1 2>/dev/null)"
rm -rf "$fake_home"

assert "register --dry-run sale con éxito" '[[ $RC -eq 0 ]]'
assert "register --dry-run no crea nada en el HOME temporal" '[[ -z "$LEFTOVER" ]]'
assert "register --dry-run anuncia el POST de enroll" '[[ "$OUT" == *"fleet/machines/enroll"* ]]'
assert "register --dry-run dice que se autenticaría con Authorization: Bearer" \
    '[[ "$OUT" == *"Authorization: Bearer"* ]]'
assert "register --dry-run nombra la clave de OWNER, no la de máquina" \
    '[[ "$OUT" == *"clave de owner"* ]]'
assert "register --dry-run menciona dónde se lee la clave (Llavero/hooks.env)" \
    '[[ "$OUT" == *"internal_api_key"* && "$OUT" == *"hooks.env"* ]]'
assert "register --dry-run nunca imprime una clave real (no había ninguna configurada)" \
    '[[ "$OUT" != *"mf_live_"* ]]'

# ── 2. register sin --name/--person/--pack y sin perfil guardado: falla ──
# limpio, sin llamar a la red (retry_register exige el perfil).
fake_home2="$(mktemp -d)"
OUT2="$(HOME="$fake_home2" "$BIN" register 2>&1)"
RC2=$?
rm -rf "$fake_home2"
assert "register sin argumentos y sin perfil previo falla con mensaje claro" \
    '[[ $RC2 -ne 0 && "$OUT2" == *"No hay perfil guardado"* ]]'

# ── 3. store_machine_token: la salida de un `security -i` que no entiende ──
# el comando (y por tanto lo repite con el secreto) queda silenciada.
# Se simula con un `security` falso en PATH que hace eco del secreto que
# recibe por stdin y sale con distintos códigos.
FAKE_BIN="$(mktemp -d)"
SECRET_MARKER="marcador-super-secreto-9f3a"

cat > "$FAKE_BIN/security" <<'FAKESEC'
#!/usr/bin/env bash
# `security` falso: si le pasan -i, imita el comportamiento real de mala
# gana: cuando el comando de stdin no le gusta, lo REPITE en stdout/stderr
# (secreto incluido). Controlado por SECURITY_FAKE_EXIT.
if [[ "${1:-}" == "-i" ]]; then
    input="$(cat)"
    printf '%s\n' "$input"       # lo que security -i repite si no lo entiende
    printf 'security: command not recognized\n' >&2
    exit "${SECURITY_FAKE_EXIT:-1}"
fi
exit 0
FAKESEC
chmod +x "$FAKE_BIN/security"

source "$SETUP_ROOT/lib/common.sh"
source "$SETUP_ROOT/lib/hardware.sh"
source "$SETUP_ROOT/lib/capabilities.sh"
source "$SETUP_ROOT/lib/fleet.sh"

# 3a. el `security` falso "falla" (simulando que no entendió la línea): la
# función debe silenciar su salida y solo avisar por el código de salida.
CAPTURED="$(PATH="$FAKE_BIN:$PATH" SECURITY_FAKE_EXIT=1 store_machine_token "$SECRET_MARKER" 2>&1)"
assert "store_machine_token: el secreto NUNCA sale por stdout/stderr aunque 'security -i' falle" \
    '[[ "$CAPTURED" != *"$SECRET_MARKER"* ]]'
assert "store_machine_token: sí avisa (sin secreto) de que no pudo guardar el token" \
    '[[ "$CAPTURED" == *"No se pudo guardar el token"* ]]'

# 3b. el `security` falso "funciona" (exit 0): tampoco debe imprimir el
# secreto, y confirma el guardado.
CAPTURED_OK="$(PATH="$FAKE_BIN:$PATH" SECURITY_FAKE_EXIT=0 store_machine_token "$SECRET_MARKER" 2>&1)"
assert "store_machine_token: tampoco imprime el secreto cuando 'security -i' sí lo entiende" \
    '[[ "$CAPTURED_OK" != *"$SECRET_MARKER"* ]]'
assert "store_machine_token: confirma el guardado en el Llavero" \
    '[[ "$CAPTURED_OK" == *"Token de máquina guardado en el Llavero"* ]]'

rm -rf "$FAKE_BIN"

# ── 4. build_enroll_payload: nombres de campo del contrato real de la API ──
# (memoryfirst/apps/api/src/routes/work.ts EnrollSchema): personId y hw, no
# person ni hardware; pack va en tags porque el esquema no tiene campo pack.
MACHINE_NAME="m2max-16-jose"
MACHINE_PERSON="11111111-1111-1111-1111-111111111111"
detect_hardware
detect_capabilities
PACK_NAME="founder"
PAYLOAD="$(build_enroll_payload)"

if has_cmd jq; then
    assert "build_enroll_payload: JSON válido" 'echo "$PAYLOAD" | jq empty >/dev/null 2>&1'
    assert "build_enroll_payload: usa 'personId' (no 'person')" \
        '[[ "$(echo "$PAYLOAD" | jq -r ".personId")" == "$MACHINE_PERSON" ]]'
    assert "build_enroll_payload: NO manda un campo 'person' suelto" \
        '[[ "$(echo "$PAYLOAD" | jq "has(\"person\")")" == "false" ]]'
    assert "build_enroll_payload: usa 'hw' (no 'hardware') y trae el modelo" \
        '[[ "$(echo "$PAYLOAD" | jq -r ".hw.model")" == "$HW_MODEL" ]]'
    assert "build_enroll_payload: NO manda un campo 'hardware' suelto" \
        '[[ "$(echo "$PAYLOAD" | jq "has(\"hardware\")")" == "false" ]]'
    assert "build_enroll_payload: el pack va en tags (el esquema no tiene campo pack)" \
        '[[ "$(echo "$PAYLOAD" | jq -r ".tags[0]")" == "pack:founder" ]]'
else
    warn "jq no disponible: se omiten los asserts de forma del payload"
fi

echo
if (( FAILURES == 0 )); then
    echo "test_fleet: todo OK"
    exit 0
else
    echo "test_fleet: $FAILURES fallo(s)"
    exit 1
fi
