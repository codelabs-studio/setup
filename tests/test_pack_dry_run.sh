#!/usr/bin/env bash
# tests/test_pack_dry_run.sh — mapeo de cada pack a sus pasos, vía --dry-run.
#
# Corre los cinco packs con --dry-run en un $HOME temporal (aislado del
# entorno real) y comprueba: (1) sale con éxito, (2) el árbol de pasos que
# imprime coincide con lo que ese pack debería tocar, (3) --dry-run no crea
# NINGÚN fichero ni directorio real. Uso: bash tests/test_pack_dry_run.sh
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

# run_pack_dry_run <pack> [flags...] — deja el resultado en las variables
# globales PACK_OUT, PACK_RC y PACK_LEFTOVER. Sin subshell (nada de asserts
# dentro de un $(...): perderían sus incrementos de FAILURES al salir).
run_pack_dry_run() {
    local pack="$1"; shift
    local fake_home; fake_home="$(mktemp -d)"
    PACK_OUT="$(HOME="$fake_home" "$BIN" enroll --name "test-$pack" --person test@codelabs.studio --pack "$pack" "$@" --dry-run 2>&1)"
    PACK_RC=$?
    PACK_LEFTOVER="$(find "$fake_home" -mindepth 1 2>/dev/null)"
    printf '%s\n' "$PACK_OUT" > "/tmp/codelabs-setup-test-${pack}.out"
    rm -rf "$fake_home"
}

assert_common() {
    local pack="$1"
    assert "$pack: enroll --dry-run sale con éxito" '[[ $PACK_RC -eq 0 ]]'
    assert "$pack: avisa que es dry-run" '[[ "$PACK_OUT" == *"MODO DRY-RUN"* ]]'
    assert "$pack: --dry-run no crea nada en el HOME temporal" '[[ -z "$PACK_LEFTOVER" ]]'
}

# ---- founder: todo lo de un desarrollador + cofounder, clona el núcleo ----
run_pack_dry_run founder
assert_common founder
out="$PACK_OUT"
assert "founder: instala Claude Code" '[[ "$out" == *"Claude Code"* ]]'
assert "founder: incluye el plugin codelabs-cofounder" '[[ "$out" == *"codelabs-cofounder@codelabs"* ]]'
assert "founder: el paso Docker aparece (el pack lo pide; que la máquina lo aguante ya es otra comprobación)" '[[ "$out" == *"==> Docker"* ]]'
assert "founder: clona el núcleo sin --repos" '[[ "$out" == *"clonando el núcleo"* ]]'
assert "founder: usa la plantilla CLAUDE.md personal" '[[ "$out" == *"CLAUDE.md (personal)"* ]]'
assert "founder: registra la máquina en la flota" '[[ "$out" == *"fleet/machines/enroll"* ]]'

# ---- developer: sin --repos no clona nada ----
run_pack_dry_run developer
assert_common developer
out="$PACK_OUT"
assert "developer sin --repos: avisa de que no clona nada" '[[ "$out" == *"no se clona ningún código"* ]]'
assert "developer sin --repos: no llega a 'Clonando repos'" '[[ "$out" != *"Clonando repos"* ]]'

run_pack_dry_run developer --repos codelabs-brain,codelabs-core
assert_common developer-con-repos
out="$PACK_OUT"
assert "developer con --repos: sí clona lo pedido" '[[ "$out" == *"Clonando repos"* ]]'
assert "developer: NO incluye el plugin codelabs-cofounder (solo el fundador lo lleva)" '[[ "$out" != *"codelabs-cofounder@codelabs"* ]]'
assert "developer: usa la plantilla CLAUDE.md team" '[[ "$out" == *"CLAUDE.md (team)"* ]]'

# ---- marketer: nada de código ni Claude Code, solo accesos directos ----
run_pack_dry_run marketer
assert_common marketer
out="$PACK_OUT"
assert "marketer: NO instala Claude Code" '[[ "$out" == *"no instala Claude Code"* ]]'
assert "marketer: NO clona repos" '[[ "$out" != *"Clonando repos"* ]]'
assert "marketer: deja accesos directos" '[[ "$out" == *"Accesos directos"* ]]'
assert "marketer: incluye el enlace al hub" '[[ "$out" == *"hub.codelabs.studio"* ]]'
assert "marketer: incluye el enlace a partners" '[[ "$out" == *"partners.codelabs.studio"* ]]'
assert "marketer: incluye el enlace a AlmaOS" '[[ "$out" == *"almaos.ai"* ]]'

# ---- learner: como marketer, y NUNCA instala Claude Code (términos de Anthropic) ----
run_pack_dry_run learner
assert_common learner
out="$PACK_OUT"
assert "learner: NO instala Claude Code" '[[ "$out" == *"no instala Claude Code"* ]]'
assert "learner sin --repos: no clona nada" '[[ "$out" != *"Clonando repos"* ]]'
assert "learner: deja los mismos accesos directos que marketer" '[[ "$out" == *"hub.codelabs.studio"* && "$out" == *"almaos.ai"* ]]'

run_pack_dry_run learner --repos proyectos-sencillos
assert_common learner-con-repo
out="$PACK_OUT"
assert "learner con --repos: sí clona el repo indicado" '[[ "$out" == *"Clonando repos"* ]]'
assert "learner con --repos: sigue sin instalar Claude Code" '[[ "$out" == *"no instala Claude Code"* ]]'

# ---- worker: sin Docker, sin Maestro, sin herramientas de desarrollo local ----
run_pack_dry_run worker --repos codelabs-brain
assert_common worker
out="$PACK_OUT"
assert "worker: instala Claude Code (corre claude -p sin pantalla)" '[[ "$out" == *"Claude Code"* ]]'
assert "worker: NO instala Docker (va enjaulado, sin socket de Docker)" '[[ "$out" != *"==> Docker"* ]]'
assert "worker: NO instala Maestro (no maneja simuladores)" '[[ "$out" != *"Maestro"* ]]'
assert "worker: NO instala caddy/mkcert/devproxy (no es una máquina de dev local)" '[[ "$out" != *"devproxy"* && "$out" != *"Herramientas de desarrollo local"* ]]'
assert "worker: sí clona el repo que se le asigne" '[[ "$out" == *"Clonando repos"* ]]'

echo
if (( FAILURES == 0 )); then
    echo "test_pack_dry_run: todo OK"
    exit 0
else
    echo "test_pack_dry_run: $FAILURES fallo(s) (salidas completas en /tmp/codelabs-setup-test-*.out)"
    exit 1
fi
