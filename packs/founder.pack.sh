#!/usr/bin/env bash
# packs/founder.pack.sh — perfil del fundador (Jose).
#
# Todos los repos concedidos, todas las herramientas. La producción sigue
# viviendo solo en el EPYC: este pack no copia ningún secreto real, solo deja
# el entorno de desarrollo listo (regla de diseño 2026-09-23).

PACK_LABEL="Fundador"
PACK_INSTALLS_CLAUDE=true
PACK_CLAUDE_MD_FLAVOR="personal"
PACK_CLONES_CODE=true
PACK_WANTS_DOCKER=true
PACK_WANTS_MAESTRO=true
PACK_WANTS_DEV_TOOLING=true

PACK_PLUGINS=(
    codelabs-cofounder
    codelabs-dev-servers
    codelabs-advisors
    codelabs-feature-port
    codelabs-role-empathy
)

# Sin --repos explícito, el fundador no clona "todos" a ciegas (sería confiar
# en un listado de Forgejo que este script no debe pedir sin credenciales):
# clona el núcleo del portfolio y avisa de cómo pedir el resto.
PACK_DEFAULT_REPOS=(
    codelabs-brain
    codelabs-core
    codelabs-setup
)

PACK_SHORTCUTS=()
