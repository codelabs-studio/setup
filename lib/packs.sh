#!/usr/bin/env bash
# lib/packs.sh — carga la definición de un pack (packs/<nombre>.pack.sh).

KNOWN_PACKS=(founder developer marketer learner worker)

is_known_pack() {
    local p="$1" k
    for k in "${KNOWN_PACKS[@]}"; do
        if [[ "$k" == "$p" ]]; then
            return 0
        fi
    done
    return 1
}

# load_pack <nombre> — hace source del fichero del pack y deja sus
# variables PACK_* en el entorno del proceso actual.
load_pack() {
    local name="$1"
    is_known_pack "$name" || die "Pack desconocido: '$name' (válidos: ${KNOWN_PACKS[*]})"
    local file="$SETUP_ROOT/packs/${name}.pack.sh"
    [[ -f "$file" ]] || die "No se encuentra la definición del pack: $file"
    # shellcheck disable=SC1090
    source "$file"
    PACK_NAME="$name"
}
