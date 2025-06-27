#!/bin/bash
# filepath: /Users/robertorossa/Desktop/Desarrollo/BootCampDevOpsRox/rcrossa-devops-project90/vagrant/scripts/service_status.sh

# Función para logging (necesaria para print_header)
log_message() {
    local message="$1"
    local level="${2:-INFO}"
    echo "[$level] $message"
}

# Función para mostrar headers
print_header() {
    local header="========================================"
    local title="$1"
    log_message "$header" "INFO"
    log_message "$title" "INFO"
    log_message "$header" "INFO"
}

check_service_list() {
    print_header "VERIFICANDO SERVICIOS"
    
    local services=("nginx" "mysql" "docker")
    local active_count=0
    local inactive_count=0

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "✅ $service: activo"
            active_count=$((active_count + 1))
        else 
            echo "❌ $service: inactivo"
            inactive_count=$((inactive_count + 1))
        fi
    done
    echo ""
    echo "📊 Resumen $active_count activos, $inactive_count inactivos."
}

# Versión alternativa más robusta usando códigos de salida
check_service_robust() {
    print_header "VERIFICANDO SERVICIOS"
    
    # Usar --quiet para verificar solo el código de salida
    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo "servicio nginx activo"
    else 
        echo "servicio nginx inactivo"
    fi
}

main() {
    check_service
    echo ""
    echo "--- Versión robusta ---"
    check_service_robust
}

# Ejecutar función principal
main "$@"