#!/usr/bin/env bash
# tests/test_hardware.sh — detección de hardware y capacidades.
# Uso: bash tests/test_hardware.sh
set -uo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SETUP_ROOT/lib/common.sh"
# shellcheck source=lib/hardware.sh
source "$SETUP_ROOT/lib/hardware.sh"
# shellcheck source=lib/capabilities.sh
source "$SETUP_ROOT/lib/capabilities.sh"

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

detect_hardware

assert "HW_OS es macos o linux" '[[ "$HW_OS" == macos || "$HW_OS" == linux ]]'
assert "HW_CPU_CORES es un entero positivo" '[[ "$HW_CPU_CORES" =~ ^[0-9]+$ ]] && (( HW_CPU_CORES >= 1 ))'
assert "HW_RAM_GB es un entero no negativo" '[[ "$HW_RAM_GB" =~ ^[0-9]+$ ]]'
assert "HW_RAM_GB es plausible (entre 1 y 1024 GB)" '(( HW_RAM_GB >= 1 && HW_RAM_GB <= 1024 ))'
assert "HW_DISK_FREE_GB es un entero no negativo" '[[ "$HW_DISK_FREE_GB" =~ ^[0-9]+$ ]]'
assert "HW_MODEL no está vacío" '[[ -n "$HW_MODEL" ]]'
assert "HW_OS_MAJOR es un entero" '[[ "$HW_OS_MAJOR" =~ ^[0-9]+$ ]]'
assert "hardware_json produce JSON parseable con jq (si hay jq)" \
    '! has_cmd jq || echo "$(hardware_json)" | jq empty >/dev/null 2>&1'

detect_capabilities

assert "CAP_DOCKER es true o false" '[[ "$CAP_DOCKER" == true || "$CAP_DOCKER" == false ]]'
assert "CAP_IOS_BUILD es true o false" '[[ "$CAP_IOS_BUILD" == true || "$CAP_IOS_BUILD" == false ]]'
assert "CAP_MAX_PARALLEL_AGENTS es un entero >= 1" '[[ "$CAP_MAX_PARALLEL_AGENTS" =~ ^[0-9]+$ ]] && (( CAP_MAX_PARALLEL_AGENTS >= 1 ))'
assert "docker=false trae un motivo" '[[ "$CAP_DOCKER" == true || -n "$CAP_DOCKER_REASON" ]]'
assert "ios_build=false trae un motivo" '[[ "$CAP_IOS_BUILD" == true || -n "$CAP_IOS_BUILD_REASON" ]]'
assert "en Linux, ios_build es siempre false" '[[ "$HW_OS" != linux || "$CAP_IOS_BUILD" == false ]]'

# --- Caso i7 2015 con macOS 12: simulado sobreescribiendo las variables tras
# medir esta máquina, para comprobar la regla de diseño "Docker: NO" del
# apartado 12.3 sin necesitar el portátil físico delante.
HW_OS="macos"; HW_OS_VERSION="12.6"; HW_OS_MAJOR=12; HW_RAM_GB=16; HW_CPU_CORES=8
detect_capabilities
assert "i7 2015 / macOS 12: docker capability es false" '[[ "$CAP_DOCKER" == false ]]'
assert "i7 2015 / macOS 12: el motivo menciona macOS" '[[ "$CAP_DOCKER_REASON" == *macOS* ]]'

echo
if (( FAILURES == 0 )); then
    echo "test_hardware: todo OK"
    exit 0
else
    echo "test_hardware: $FAILURES fallo(s)"
    exit 1
fi
