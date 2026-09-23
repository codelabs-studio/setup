#!/usr/bin/env bash
# packs/learner.pack.sh — aprendiz (p.ej. un menor, caso Álvaro 2026-09-23).
#
# NUNCA instala Claude Code: los términos de Anthropic exigen 18 años sin
# excepción por supervisión de los padres (leídos el 23-sep-2026, evento
# a39aa92b). Un aprendiz puede estar en AlmaOS con tareas asignadas y sin
# datos de clientes reales, pero eso lo gestiona AlmaOS, no este instalador.
# Mismos accesos directos que un marketer, más un repo de proyectos sencillos
# SI se indica explícitamente con --repos.

PACK_LABEL="Aprendiz"
PACK_INSTALLS_CLAUDE=false
PACK_CLAUDE_MD_FLAVOR=""
PACK_CLONES_CODE=true          # solo si se pasa --repos; ver step_clone_repos
PACK_WANTS_DOCKER=false
PACK_WANTS_MAESTRO=false
PACK_WANTS_DEV_TOOLING=false

PACK_PLUGINS=()
PACK_DEFAULT_REPOS=()

PACK_SHORTCUTS=(
    "Hub Codelabs:https://hub.codelabs.studio"
    "Partners:https://partners.codelabs.studio"
    "AlmaOS:https://almaos.ai"
)
