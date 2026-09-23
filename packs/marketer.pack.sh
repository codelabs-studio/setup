#!/usr/bin/env bash
# packs/marketer.pack.sh — marketer o partner comercial.
#
# No clona código. No instala Claude Code (no lo necesita para su trabajo, y
# así no hay ninguna cuenta ni asiento que gestionar para este rol). Solo
# deja accesos directos al escaparate del portfolio.

PACK_LABEL="Marketer / partner"
PACK_INSTALLS_CLAUDE=false
PACK_CLAUDE_MD_FLAVOR=""
PACK_CLONES_CODE=false
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
