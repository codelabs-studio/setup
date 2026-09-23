#!/usr/bin/env bash
# packs/worker.pack.sh — máquina trabajadora sin pantalla (p.ej. el
# "trabajador de lanzamiento" del EPYC, doc 63 apartado 12.3).
#
# Sin Docker (va enjaulado, sin socket de Docker por diseño) y sin Maestro
# (no maneja simuladores). Clona solo los repos de la cola que le asigne su
# dueño. Instala Claude Code porque ejecuta `claude -p` sin pantalla con un
# setup-token, no un login interactivo.

PACK_LABEL="Máquina trabajadora"
PACK_INSTALLS_CLAUDE=true
PACK_CLAUDE_MD_FLAVOR="team"
PACK_CLONES_CODE=true
PACK_WANTS_DOCKER=false
PACK_WANTS_MAESTRO=false
PACK_WANTS_DEV_TOOLING=false

PACK_PLUGINS=(
    codelabs-dev-servers
    codelabs-advisors
)

PACK_DEFAULT_REPOS=()

PACK_SHORTCUTS=()
