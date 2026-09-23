#!/usr/bin/env bash
# lib/hardware.sh — mide el hardware de la máquina actual.
#
# Rellena las variables globales HW_* leyendo únicamente fuentes locales de
# solo lectura (sysctl, /proc, sw_vers, lsb_release, df). No hace red, no lee
# credenciales, no toca ningún fichero de entorno.

detect_hardware() {
    HW_OS="$(detect_os)"
    HW_ARCH="$(uname -m)"

    if [[ "$HW_OS" == "macos" ]]; then
        HW_MODEL="$(sysctl -n hw.model 2>/dev/null || echo unknown)"
        HW_RAM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
        HW_CPU_CORES="$(sysctl -n hw.ncpu 2>/dev/null || echo 1)"
        HW_OS_NAME="macOS"
        HW_OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo 0.0)"
        # df -k da bloques de 1K; el disponible es la columna 4.
        HW_DISK_FREE_KB="$(df -k / 2>/dev/null | awk 'NR==2{print $4}')"
    elif [[ "$HW_OS" == "linux" ]]; then
        HW_MODEL="$( { cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo unknown; } | head -1)"
        HW_CPU_CORES="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)"
        if has_cmd free; then
            HW_RAM_BYTES="$(free -b 2>/dev/null | awk '/^Mem:/{print $2}')"
        else
            HW_RAM_BYTES=0
        fi
        HW_OS_NAME="Linux"
        if has_cmd lsb_release; then
            HW_OS_VERSION="$(lsb_release -ds 2>/dev/null | tr -d '"')"
        elif [[ -f /etc/os-release ]]; then
            # Plantilla, no un .env: /etc/os-release es metadata pública del SO.
            HW_OS_VERSION="$(. /etc/os-release; echo "${PRETTY_NAME:-desconocido}")"
        else
            HW_OS_VERSION="desconocido"
        fi
        HW_DISK_FREE_KB="$(df -k / 2>/dev/null | awk 'NR==2{print $4}')"
    fi

    HW_RAM_BYTES="${HW_RAM_BYTES:-0}"
    HW_CPU_CORES="${HW_CPU_CORES:-1}"
    HW_DISK_FREE_KB="${HW_DISK_FREE_KB:-0}"

    HW_RAM_GB=$(( HW_RAM_BYTES / 1024 / 1024 / 1024 ))
    HW_DISK_FREE_GB=$(( HW_DISK_FREE_KB / 1024 / 1024 ))

    # Versión mayor del SO como entero, para comparar (macOS 12 -> 12; "Ubuntu
    # 24.04.1 LTS" -> 24; si no se puede parsear, 0 para forzar el lado
    # conservador en las capacidades).
    HW_OS_MAJOR="$(printf '%s' "$HW_OS_VERSION" | grep -oE '[0-9]+' | head -1)"
    HW_OS_MAJOR="${HW_OS_MAJOR:-0}"
}

hardware_summary() {
    cat <<EOF
Hardware detectado:
  Modelo:        $HW_MODEL ($HW_ARCH)
  SO:            $HW_OS_NAME $HW_OS_VERSION
  CPU:           $HW_CPU_CORES núcleos
  RAM:           ${HW_RAM_GB} GB
  Disco libre:   ${HW_DISK_FREE_GB} GB
EOF
}

# hardware_json — construye a mano el JSON del perfil de hardware (sin jq,
# porque esto se ejecuta ANTES de garantizar que jq esté instalado). Todos
# los valores son metadatos de máquina, nunca credenciales.
hardware_json() {
    cat <<EOF
{
  "model": "$(json_escape "$HW_MODEL")",
  "arch": "$(json_escape "$HW_ARCH")",
  "os": "$(json_escape "$HW_OS")",
  "os_version": "$(json_escape "$HW_OS_VERSION")",
  "cpu_cores": $HW_CPU_CORES,
  "ram_gb": $HW_RAM_GB,
  "disk_free_gb": $HW_DISK_FREE_GB
}
EOF
}
