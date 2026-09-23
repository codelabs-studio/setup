#!/usr/bin/env bash
# lib/common.sh — helpers compartidos por todo codelabs-setup.
#
# REGLA DE SEGURIDAD (léela antes de tocar este fichero): ningún secreto pasa
# por aquí. Nada de imprimir tokens, contraseñas ni contenido de .env. Un
# token de máquina se guarda en un fichero 0600 y se referencia por ruta,
# nunca por valor en stdout ni en un dotfile (.zshrc/.bashrc/.profile).

# Evita cargar dos veces si un script hace `source` de varias libs que a su
# vez cargan common.sh.
if [[ -n "${__CODELABS_SETUP_COMMON_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
__CODELABS_SETUP_COMMON_LOADED=1

DRY_RUN="${DRY_RUN:-false}"

log()  { printf '==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
ok()   { printf 'OK  %s\n' "$*"; }
err()  { printf 'ERR %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# run <cmd...> — ejecuta el comando, o solo lo anuncia si DRY_RUN=true.
# Úsalo para CUALQUIER acción que mute el sistema (instalar, clonar, escribir
# fuera de un fichero temporal). Las comprobaciones de solo lectura (command
# -v, test -f...) se llaman directamente, nunca a través de run().
run() {
    if [[ "$DRY_RUN" == true ]]; then
        printf '[dry-run] %s\n' "$*"
        return 0
    fi
    "$@"
}

# would <mensaje> — anuncia una acción compuesta (varios comandos) en modo
# dry-run; en modo real no hace nada por sí sola, el step sigue ejecutando.
would() {
    if [[ "$DRY_RUN" == true ]]; then
        printf '[dry-run] %s\n' "$*"
    fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

confirm() {
    local prompt="${1:-¿Continuar?}"
    if [[ "$DRY_RUN" == true ]]; then
        printf '[dry-run] (confirmación asumida: %s)\n' "$prompt"
        return 0
    fi
    read -r -p "$prompt [y/N] " ans
    [[ "$ans" =~ ^[yY]$ ]]
}

# json_escape <str> — escapa comillas y barras invertidas para incrustar en
# un JSON escrito a mano. Sirve para valores ya conocidos y no sensibles
# (nombre de máquina, modelo, SO); nunca para secretos.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

# require_cmd <cmd> <mensaje-si-falta> — corta la ejecución si falta un
# binario imprescindible para seguir (no usar para capacidades opcionales).
require_cmd() {
    has_cmd "$1" || die "$2"
}

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        *) die "Sistema operativo no soportado: $(uname -s)" ;;
    esac
}
