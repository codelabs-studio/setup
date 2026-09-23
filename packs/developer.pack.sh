#!/usr/bin/env bash
# packs/developer.pack.sh — colaborador o empleado con acceso a código.
#
# Solo los repos que se le concedan (--repos), nunca "todos". Secretos: solo
# desarrollo, en su propia colección de Vaultwarden (fuera del alcance de
# este script: eso lo gestiona config-expert / Vaultwarden, no un .env
# copiado a mano).

PACK_LABEL="Desarrollador"
PACK_INSTALLS_CLAUDE=true
PACK_CLAUDE_MD_FLAVOR="team"
PACK_CLONES_CODE=true
PACK_WANTS_DOCKER=true
PACK_WANTS_MAESTRO=true
PACK_WANTS_DEV_TOOLING=true

PACK_PLUGINS=(
    codelabs-dev-servers
    codelabs-advisors
    codelabs-feature-port
)

# Sin default: un developer SIEMPRE declara sus repos con --repos. Si no los
# da, el pack no clona nada (mejor pedir explícito que adivinar acceso).
PACK_DEFAULT_REPOS=()

PACK_SHORTCUTS=()
