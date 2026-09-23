#!/usr/bin/env bash
# lib/capabilities.sh — deduce qué puede hacer esta máquina a partir del
# hardware medido (lib/hardware.sh). Requiere haber llamado a
# detect_hardware antes.

# Xcode mínimo para que xcodebuild compile las apps iOS actuales del
# portfolio (Alma, etc.). Es un umbral operativo, se sube si algún proyecto
# eleva su deployment target y necesita un Xcode más nuevo.
MIN_XCODE_MAJOR=15

# RAM mínima (GB) para que Docker Desktop / dockerd vaya fino sin robarle
# memoria al resto de la máquina.
MIN_DOCKER_RAM_GB=8

detect_capabilities() {
    : "${HW_OS:?llama a detect_hardware antes de detect_capabilities}"

    # ---- docker ----
    CAP_DOCKER=false
    CAP_DOCKER_REASON=""
    if [[ "$HW_OS" == "macos" ]]; then
        if (( HW_OS_MAJOR < 13 )); then
            CAP_DOCKER_REASON="macOS ${HW_OS_VERSION} (<13) no tiene soporte completo de Docker Desktop moderno"
        elif (( HW_RAM_GB < MIN_DOCKER_RAM_GB )); then
            CAP_DOCKER_REASON="RAM insuficiente (${HW_RAM_GB} GB < ${MIN_DOCKER_RAM_GB} GB) para Docker Desktop"
        else
            CAP_DOCKER=true
        fi
    elif [[ "$HW_OS" == "linux" ]]; then
        if (( HW_RAM_GB < 4 )); then
            CAP_DOCKER_REASON="RAM insuficiente (${HW_RAM_GB} GB < 4 GB) para un daemon Docker estable"
        else
            CAP_DOCKER=true
        fi
    fi

    # ---- ios_build ----
    CAP_IOS_BUILD=false
    CAP_IOS_BUILD_REASON=""
    if [[ "$HW_OS" != "macos" ]]; then
        CAP_IOS_BUILD_REASON="no es macOS"
    elif ! has_cmd xcodebuild; then
        CAP_IOS_BUILD_REASON="Xcode no está instalado"
    else
        local xcode_version xcode_major
        xcode_version="$(xcodebuild -version 2>/dev/null | awk 'NR==1{print $2}')"
        xcode_major="${xcode_version%%.*}"
        xcode_major="${xcode_major:-0}"
        if [[ "$xcode_major" =~ ^[0-9]+$ ]] && (( xcode_major >= MIN_XCODE_MAJOR )); then
            CAP_IOS_BUILD=true
        else
            CAP_IOS_BUILD_REASON="Xcode ${xcode_version:-desconocido} (<${MIN_XCODE_MAJOR}) no compila las apps iOS actuales"
        fi
    fi

    # ---- max_parallel_agents ----
    # Fórmula deliberadamente simple y documentada: ni la RAM ni la CPU solas
    # bastan (un agente Claude Code vivo pesa en RAM del propio proceso Node
    # y en llamadas de red/CPU al compilar o correr tests). Se toma el más
    # restrictivo de los dos límites, con un mínimo de 1.
    #   límite por RAM: 1 agente cada 4 GB
    #   límite por CPU: 1 agente cada 2 núcleos
    local by_ram=$(( HW_RAM_GB / 4 ))
    local by_cpu=$(( HW_CPU_CORES / 2 ))
    (( by_ram < 1 )) && by_ram=1
    (( by_cpu < 1 )) && by_cpu=1
    if (( by_ram < by_cpu )); then
        CAP_MAX_PARALLEL_AGENTS=$by_ram
    else
        CAP_MAX_PARALLEL_AGENTS=$by_cpu
    fi
}

capabilities_summary() {
    local docker_line ios_line
    if [[ "$CAP_DOCKER" == true ]]; then
        docker_line="sí"
    else
        docker_line="no ($CAP_DOCKER_REASON)"
    fi
    if [[ "$CAP_IOS_BUILD" == true ]]; then
        ios_line="sí"
    else
        ios_line="no ($CAP_IOS_BUILD_REASON)"
    fi
    cat <<EOF
Capacidades deducidas:
  docker:               $docker_line
  ios_build:             $ios_line
  max_parallel_agents:   $CAP_MAX_PARALLEL_AGENTS
EOF
}

capabilities_json() {
    cat <<EOF
{
  "docker": $CAP_DOCKER,
  "docker_reason": "$(json_escape "$CAP_DOCKER_REASON")",
  "ios_build": $CAP_IOS_BUILD,
  "ios_build_reason": "$(json_escape "$CAP_IOS_BUILD_REASON")",
  "max_parallel_agents": $CAP_MAX_PARALLEL_AGENTS
}
EOF
}
