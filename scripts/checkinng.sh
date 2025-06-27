#!/bin/bash
# filepath: /Users/robertorossa/Desktop/Desarrollo/BootCampDevOpsRox/rcrossa-devops-project90/vagrant/scripts/checkinng.sh

# Script de verificación del sistema con notificaciones Slack
# Autor: DevOps Team
# Fecha: $(date +%Y-%m-%d)

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables globales para Slack
SLACK_RESULTS=""
TOTAL_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0
SUCCESS_CHECKS=0

# Configuración de directorios
BASE_DIR="/home/vagrant/scripts"
CONFIG_DIR="$BASE_DIR/config"
LOG_DIR="$BASE_DIR/logs"
REPORTS_DIR="$BASE_DIR/reports"
TEMP_DIR="$BASE_DIR/temp"

# Archivos de configuración y logs
CONFIG_FILE="$CONFIG_DIR/system-check.conf"
LOG_FILE="$LOG_DIR/daily/system-check-$(date +%Y%m%d-%H%M%S).log"
HTML_REPORT="$REPORTS_DIR/html/system-check-$(date +%Y%m%d-%H%M%S).html"
JSON_REPORT="$REPORTS_DIR/json/system-check-$(date +%Y%m%d-%H%M%S).json"
SUMMARY_LOG="$LOG_DIR/summary.log"

# Crear estructura de directorios
create_directory_structure() {
    echo "Creando estructura de directorios..."
    
    mkdir -p "$CONFIG_DIR" "$LOG_DIR/daily" "$LOG_DIR/weekly" "$LOG_DIR/errors" 2>/dev/null
    mkdir -p "$REPORTS_DIR/html" "$REPORTS_DIR/json" "$CONFIG_DIR/templates" "$TEMP_DIR" 2>/dev/null
    
    echo "✓ Estructura de directorios creada en $BASE_DIR"
}

# Crear archivo de configuración por defecto con tu webhook
create_default_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
# Configuración del sistema de verificación
# Archivo creado: $(date)

# Configuración de Slack
SLACK_ENABLED=true
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/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"
SLACK_CHANNEL="#general"
SLACK_USERNAME="System Monitor"
SLACK_ICON_EMOJI=":robot_face:"
SLACK_NOTIFY_ON_SUCCESS=true
SLACK_NOTIFY_ON_WARNING=true
SLACK_NOTIFY_ON_ERROR=true

# Configuración de verificaciones
CHECK_UPDATES=true
CHECK_SECURITY=true
CHECK_DISK_SPACE=true
CHECK_MEMORY=true
CHECK_SERVICES=true
CHECK_LOGS=true
CHECK_FIREWALL=true
CHECK_VERSIONS=true
CHECK_VULNERABILITIES=true

# Umbrales de alerta
DISK_WARNING_THRESHOLD=80
DISK_CRITICAL_THRESHOLD=90
MEMORY_WARNING_THRESHOLD=85
MEMORY_CRITICAL_THRESHOLD=95

# Servicios críticos a verificar
CRITICAL_SERVICES="ssh nginx apache2 mysql postgresql docker"

# Configuración de versiones (días para considerar desactualizada)
VERSION_CHECK_DAYS=30
NGINX_MIN_VERSION="1.18.0"
DOCKER_MIN_VERSION="20.10.0"

# URLs para verificar vulnerabilidades
CVE_CHECK_ENABLED=true
VULNERABILITY_DB_URL="https://services.nvd.nist.gov/rest/json/cves/1.0"

# Retención de logs (días)
LOG_RETENTION_DAYS=30
REPORT_RETENTION_DAYS=90
EOF
        echo "✓ Archivo de configuración creado: $CONFIG_FILE"
    fi
}

# Cargar configuración con debug
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo "✓ Configuración cargada desde $CONFIG_FILE"
        echo "🔧 Debug - SLACK_ENABLED: $SLACK_ENABLED"
        echo "🔧 Debug - SLACK_WEBHOOK_URL: ${SLACK_WEBHOOK_URL:0:50}..."
    else
        echo "⚠ Usando configuración por defecto"
        # Valores por defecto
        SLACK_ENABLED=false
        CHECK_UPDATES=true
        CHECK_DISK_SPACE=true
        CHECK_VERSIONS=true
        CHECK_VULNERABILITIES=true
        DISK_WARNING_THRESHOLD=80
        DISK_CRITICAL_THRESHOLD=90
        CRITICAL_SERVICES="ssh nginx apache2 mysql postgresql docker"
        NGINX_MIN_VERSION="1.18.0"
        DOCKER_MIN_VERSION="20.10.0"
    fi
}

# Función para logging
log_message() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    if [ "$level" = "ERROR" ] || [ "$level" = "WARNING" ]; then
        echo "[$timestamp] [$level] $message" >> "$SUMMARY_LOG"
    fi
    
    case $level in
        "ERROR")
            echo -e "${RED}[$level] $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}[$level] $message${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[$level] $message${NC}"
            ;;
        *)
            echo -e "${BLUE}[$level] $message${NC}"
            ;;
    esac
}

# Función para mostrar headers
print_header() {
    local header="========================================"
    local title="$1"
    log_message "$header" "INFO"
    log_message "$title" "INFO"
    log_message "$header" "INFO"
}

# Función para agregar resultado a Slack
add_slack_result() {
    local check_name="$1"
    local status="$2"
    local message="$3"
    local emoji=""
    
    case $status in
        "success")
            emoji="✅"
            SUCCESS_CHECKS=$((SUCCESS_CHECKS + 1))
            ;;
        "warning")
            emoji="⚠️"
            WARNING_CHECKS=$((WARNING_CHECKS + 1))
            ;;
        "error")
            emoji="❌"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            ;;
        *)
            emoji="ℹ️"
            ;;
    esac
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    SLACK_RESULTS="${SLACK_RESULTS}${emoji} *${check_name}*: ${message}\n"
}

# Función para comparar versiones
version_compare() {
    local version1="$1"
    local version2="$2"
    
    # Convertir versiones a números comparables
    local v1=$(echo "$version1" | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }')
    local v2=$(echo "$version2" | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }')
    
    if [ "$v1" -lt "$v2" ]; then
        return 1  # version1 < version2
    else
        return 0  # version1 >= version2
    fi
}

# Verificar versiones de nginx
check_nginx_version() {
    if ! command -v nginx >/dev/null 2>&1; then
        log_message "Nginx no está instalado" "INFO"
        return 0
    fi
    
    local current_version=$(nginx -v 2>&1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
    local status="success"
    local output=""
    
    if [ -n "$current_version" ]; then
        log_message "Versión actual de Nginx: $current_version" "INFO"
        
        if version_compare "$current_version" "$NGINX_MIN_VERSION"; then
            output="Nginx desactualizado: v$current_version (mínima: v$NGINX_MIN_VERSION)"
            status="warning"
            log_message "$output" "WARNING"
        else
            output="Nginx actualizado: v$current_version"
            status="success"
            log_message "$output" "SUCCESS"
        fi
        
        # Verificar si hay actualizaciones disponibles
        case $DISTRO in
            ubuntu|debian)
                local available_version=$(apt list nginx 2>/dev/null | grep -v "WARNING" | grep nginx | awk -F' ' '{print $2}' | cut -d':' -f2 | cut -d'-' -f1)
                if [ -n "$available_version" ] && [ "$available_version" != "$current_version" ]; then
                    output="$output (disponible: v$available_version)"
                    status="warning"
                fi
                ;;
        esac
    else
        output="No se pudo determinar la versión de Nginx"
        status="error"
        log_message "$output" "ERROR"
    fi
    
    add_slack_result "Versión Nginx" "$status" "$output"
}

# Verificar versiones de Docker
check_docker_version() {
    if ! command -v docker >/dev/null 2>&1; then
        log_message "Docker no está instalado" "INFO"
        return 0
    fi
    
    local current_version=$(docker --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    local status="success"
    local output=""
    
    if [ -n "$current_version" ]; then
        log_message "Versión actual de Docker: $current_version" "INFO"
        
        if version_compare "$current_version" "$DOCKER_MIN_VERSION"; then
            output="Docker desactualizado: v$current_version (mínima: v$DOCKER_MIN_VERSION)"
            status="warning"
            log_message "$output" "WARNING"
        else
            output="Docker actualizado: v$current_version"
            status="success"
            log_message "$output" "SUCCESS"
        fi
        
        # Verificar si Docker está corriendo
        if ! systemctl is-active --quiet docker 2>/dev/null; then
            output="$output (SERVICIO INACTIVO)"
            status="error"
        fi
    else
        output="No se pudo determinar la versión de Docker"
        status="error"
        log_message "$output" "ERROR"
    fi
    
    add_slack_result "Versión Docker" "$status" "$output"
}

# Verificar vulnerabilidades del sistema
check_vulnerabilities() {
    if [ "$CHECK_VULNERABILITIES" != "true" ]; then
        return 0
    fi
    
    print_header "VERIFICANDO VULNERABILIDADES DE SEGURIDAD"
    local status="success"
    local output=""
    local vuln_count=0
    
    # Verificar actualizaciones de seguridad
    case $DISTRO in
        ubuntu|debian)
            # Verificar actualizaciones de seguridad específicas
            local security_updates=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l)
            if [ $security_updates -gt 0 ]; then
                vuln_count=$((vuln_count + security_updates))
                output="$security_updates actualizaciones de seguridad disponibles"
                status="error"
                log_message "$output" "ERROR"
                
                # Listar algunas actualizaciones críticas
                local critical_updates=$(apt list --upgradable 2>/dev/null | grep -i security | head -3 | awk -F'/' '{print $1}' | tr '\n' ', ')
                if [ -n "$critical_updates" ]; then
                    log_message "Paquetes críticos: ${critical_updates%,}" "ERROR"
                fi
            fi
            ;;
        centos|rhel|fedora)
            # Verificar actualizaciones de seguridad en RHEL/CentOS
            if command -v yum >/dev/null 2>&1; then
                local security_updates=$(yum --security check-update 2>/dev/null | grep -c "updates" || echo "0")
                if [ $security_updates -gt 0 ]; then
                    vuln_count=$((vuln_count + security_updates))
                    output="$security_updates actualizaciones de seguridad disponibles"
                    status="error"
                    log_message "$output" "ERROR"
                fi
            fi
            ;;
    esac
    
    # Verificar puertos abiertos sospechosos
    local suspicious_ports=$(netstat -tlnp 2>/dev/null | grep LISTEN | awk '{print $4}' | cut -d: -f2 | sort -nu | grep -E '^(23|135|445|139|1433|3389|5432)$' | wc -l)
    if [ $suspicious_ports -gt 0 ]; then
        vuln_count=$((vuln_count + suspicious_ports))
        output="$output; $suspicious_ports puertos potencialmente peligrosos abiertos"
        status="warning"
        log_message "Puertos sospechosos detectados" "WARNING"
    fi
    
    # Verificar procesos sospechosos con alto CPU
    local high_cpu_processes=$(ps aux --sort=-%cpu | head -6 | tail -5 | awk '$3 > 80 {print $11}' | wc -l)
    if [ $high_cpu_processes -gt 0 ]; then
        log_message "$high_cpu_processes procesos con CPU >80%" "WARNING"
        if [ "$status" != "error" ]; then
            status="warning"
        fi
    fi
    
    # Verificar intentos de login fallidos
    local failed_logins=0
    if [ -f /var/log/auth.log ]; then
        failed_logins=$(grep "authentication failure" /var/log/auth.log | tail -50 | wc -l)
    elif [ -f /var/log/secure ]; then
        failed_logins=$(grep "authentication failure" /var/log/secure | tail -50 | wc -l)
    fi
    
    if [ $failed_logins -gt 10 ]; then
        log_message "ALERTA: $failed_logins intentos de login fallidos recientes" "WARNING"
        if [ "$status" = "success" ]; then
            status="warning"
        fi
    fi
    
    # Resultado final
    if [ $vuln_count -eq 0 ] && [ "$status" = "success" ]; then
        output="No se detectaron vulnerabilidades críticas"
        log_message "$output" "SUCCESS"
    elif [ -z "$output" ]; then
        output="Sistema revisado, algunas advertencias menores"
        status="warning"
    fi
    
    add_slack_result "Vulnerabilidades" "$status" "$output"
}

# Verificar configuración de seguridad del sistema
check_security_config() {
    print_header "VERIFICANDO CONFIGURACIÓN DE SEGURIDAD"
    local status="success"
    local issues=""
    
    # Verificar si root puede hacer login por SSH
    if grep -q "PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
        issues="Login root por SSH habilitado; "
        status="warning"
        log_message "ADVERTENCIA: Login root por SSH está habilitado" "WARNING"
    fi
    
    # Verificar autenticación por contraseña
    if grep -q "PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
        issues="${issues}Autenticación por contraseña habilitada; "
        if [ "$status" != "error" ]; then
            status="warning"
        fi
        log_message "ADVERTENCIA: Autenticación por contraseña SSH habilitada" "WARNING"
    fi
    
    # Verificar firewall
    local firewall_active=false
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            firewall_active=true
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            firewall_active=true
        fi
    fi
    
    if [ "$firewall_active" = false ]; then
        issues="${issues}Firewall inactivo; "
        status="error"
        log_message "ERROR: Firewall no está activo" "ERROR"
    fi
    
    # Verificar permisos de archivos críticos
    if [ -f /etc/passwd ] && [ "$(stat -c %a /etc/passwd)" != "644" ]; then
        issues="${issues}Permisos incorrectos en /etc/passwd; "
        status="warning"
    fi
    
    local output=""
    if [ -n "$issues" ]; then
        output="Problemas detectados: ${issues%%; }"
    else
        output="Configuración de seguridad correcta"
        log_message "$output" "SUCCESS"
    fi
    
    add_slack_result "Configuración Seguridad" "$status" "$output"
}

# Función para enviar notificación a Slack (simplificada y corregida)
send_slack_notification() {
    echo "🔧 Debug - Iniciando envío a Slack..."
    echo "🔧 Debug - SLACK_ENABLED: '$SLACK_ENABLED'"
    echo "🔧 Debug - SLACK_WEBHOOK_URL: '${SLACK_WEBHOOK_URL:0:50}...'"
    
    if [ "$SLACK_ENABLED" != "true" ]; then
        log_message "Slack no está habilitado (SLACK_ENABLED=$SLACK_ENABLED)" "INFO"
        return 0
    fi
    
    if [ -z "$SLACK_WEBHOOK_URL" ]; then
        log_message "No hay webhook configurado (SLACK_WEBHOOK_URL está vacío)" "ERROR"
        return 1
    fi
    
    # Determinar el color del mensaje basado en los resultados
    local color="good"  # verde
    local overall_status="✅ SISTEMA SEGURO"
    
    if [ $FAILED_CHECKS -gt 0 ]; then
        color="danger"  # rojo
        overall_status="🚨 VULNERABILIDADES DETECTADAS"
    elif [ $WARNING_CHECKS -gt 0 ]; then
        color="warning"  # amarillo
        overall_status="⚠️ REQUIERE ATENCIÓN"
    fi
    
    # Crear mensaje simple primero
    local hostname=$(hostname)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local summary="Resumen: $SUCCESS_CHECKS OK, $WARNING_CHECKS advertencias, $FAILED_CHECKS críticos"
    
    # Mensaje completo para Slack
    local full_message="🖥️ *Auditoría de Seguridad - $hostname*\n\n"
    full_message+="📅 *Fecha:* $timestamp\n"
    full_message+="🛡️ *$overall_status*\n\n"
    full_message+="*Resultados de Verificación:*\n$SLACK_RESULTS\n"
    full_message+="📊 *$summary*"
    
    # Crear payload JSON más simple
    local payload=$(cat << EOF
{
    "text": "$full_message",
    "username": "Security Monitor",
    "icon_emoji": ":shield:"
}
EOF
)
    
    echo "🔧 Debug - Enviando payload..."
    
    # Enviar a Slack con debug
    local response=$(curl -s -w "HTTP_CODE:%{http_code}" -X POST \
                         -H 'Content-type: application/json' \
                         --data "$payload" \
                         "$SLACK_WEBHOOK_URL")
    
    local http_code=$(echo "$response" | grep -o 'HTTP_CODE:[0-9]*' | cut -d: -f2)
    local body=$(echo "$response" | sed 's/HTTP_CODE:[0-9]*$//')
    
    echo "🔧 Debug - HTTP Code: $http_code"
    echo "🔧 Debug - Response: $body"
    
    if [ "$http_code" = "200" ] && [ "$body" = "ok" ]; then
        log_message "✅ Notificación enviada exitosamente a Slack" "SUCCESS"
        return 0
    else
        log_message "❌ Error enviando notificación a Slack. HTTP: $http_code, Respuesta: $body" "ERROR"
        return 1
    fi
}

# Función para enviar mensaje simple a Slack
send_simple_slack_message() {
    local message="$1"
    
    if [ "$SLACK_ENABLED" != "true" ] || [ -z "$SLACK_WEBHOOK_URL" ]; then
        return 0
    fi
    
    local payload="{\"text\":\"$message\"}"
    
    curl -s -X POST -H 'Content-type: application/json' \
         --data "$payload" \
         "$SLACK_WEBHOOK_URL" > /dev/null
}

# Detectar distribución de Linux
detect_distro() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        DISTRO=$ID
    elif command -v lsb_release >/dev/null 2>&1; then
        DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    else
        DISTRO="unknown"
    fi
    log_message "Distribución detectada: $DISTRO" "INFO"
}

# Verificar actualizaciones disponibles
check_updates() {
    if [ "$CHECK_UPDATES" != "true" ]; then
        return 0
    fi
    
    print_header "VERIFICANDO ACTUALIZACIONES DISPONIBLES"
    local output=""
    local status="success"
    local updates_count=0
    
    case $DISTRO in
        ubuntu|debian)
            # Actualizar lista de paquetes
            apt update > "$TEMP_DIR/apt_update.log" 2>&1
            updates_count=$(apt list --upgradable 2>/dev/null | grep -c upgradable)
            
            if [ $updates_count -gt 0 ]; then
                output="$updates_count actualizaciones disponibles"
                log_message "$output" "WARNING"
                status="warning"
            else
                output="Sistema actualizado"
                log_message "$output" "SUCCESS"
                status="success"
            fi
            ;;
        centos|rhel|fedora)
            updates_count=$(yum check-update 2>/dev/null | grep -c "\..*updates" || echo "0")
            if [ $updates_count -gt 0 ]; then
                output="$updates_count actualizaciones disponibles"
                log_message "$output" "WARNING"
                status="warning"
            else
                output="Sistema actualizado"
                log_message "$output" "SUCCESS"
                status="success"
            fi
            ;;
        *)
            output="Distribución no soportada"
            log_message "$output" "WARNING"
            status="warning"
            ;;
    esac
    
    add_slack_result "Actualizaciones" "$status" "$output"
}

# Verificar espacio en disco
check_disk_space() {
    if [ "$CHECK_DISK_SPACE" != "true" ]; then
        return 0
    fi
    
    print_header "VERIFICANDO ESPACIO EN DISCO"
    local output=""
    local status="success"
    local critical_disks=""
    
    # Analizar uso de disco
    while IFS= read -r line; do
        if [[ $line =~ ^/dev/ ]] || [[ $line =~ ^/ ]]; then
            local usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')
            local mount_point=$(echo "$line" | awk '{print $6}')
            
            if [[ $usage =~ ^[0-9]+$ ]]; then
                if [ $usage -gt $DISK_CRITICAL_THRESHOLD ]; then
                    critical_disks+="$mount_point($usage%) "
                    status="error"
                elif [ $usage -gt $DISK_WARNING_THRESHOLD ]; then
                    critical_disks+="$mount_point($usage%) "
                    if [ "$status" != "error" ]; then
                        status="warning"
                    fi
                fi
            fi
        fi
    done <<< "$(df -h)"
    
    if [ -n "$critical_disks" ]; then
        output="Discos con alto uso: $critical_disks"
        log_message "$output" "WARNING"
    else
        output="Todos los discos OK"
        log_message "$output" "SUCCESS"
    fi
    
    add_slack_result "Espacio en Disco" "$status" "$output"
}

# Verificar memoria
check_memory() {
    if [ "$CHECK_MEMORY" != "true" ]; then
        return 0
    fi
    
    print_header "VERIFICANDO MEMORIA"
    local status="success"
    local output=""
    
    # Obtener información de memoria
    local mem_info=$(free | grep '^Mem:')
    local total=$(echo $mem_info | awk '{print $2}')
    local used=$(echo $mem_info | awk '{print $3}')
    local mem_usage_percent=$(awk "BEGIN {printf \"%.2f\", $used * 100 / $total}")
    
    # Evaluar uso de memoria
    if (( $(awk "BEGIN {print ($mem_usage_percent > $MEMORY_CRITICAL_THRESHOLD)}") )); then
        output="CRÍTICO: Memoria al ${mem_usage_percent}%"
        status="error"
        log_message "$output" "ERROR"
    elif (( $(awk "BEGIN {print ($mem_usage_percent > $MEMORY_WARNING_THRESHOLD)}") )); then
        output="ADVERTENCIA: Memoria al ${mem_usage_percent}%"
        status="warning"
        log_message "$output" "WARNING"
    else
        output="Memoria OK: ${mem_usage_percent}% usado"
        status="success"
        log_message "$output" "SUCCESS"
    fi
    
    add_slack_result "Uso de Memoria" "$status" "$output"
}

# Verificar servicios críticos
check_services() {
    if [ "$CHECK_SERVICES" != "true" ]; then
        return 0
    fi
    
    print_header "VERIFICANDO SERVICIOS CRÍTICOS"
    local status="success"
    local inactive_services=""
    local active_services=""
    
    # Convertir la cadena de servicios en array
    IFS=' ' read -ra services_array <<< "$CRITICAL_SERVICES"
    
    for service in "${services_array[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            active_services+="$service "
        elif systemctl list-unit-files --type=service | grep -q "^$service.service"; then
            inactive_services+="$service "
            status="warning"
        fi
    done
    
    # Crear mensaje de salida
    local output=""
    if [ -n "$inactive_services" ]; then
        output="Servicios inactivos: $inactive_services"
        log_message "$output" "WARNING"
    else
        output="Todos los servicios críticos activos"
        log_message "$output" "SUCCESS"
    fi
    
    if [ -n "$active_services" ]; then
        log_message "Servicios activos: $active_services" "INFO"
    fi
    
    add_slack_result "Servicios Críticos" "$status" "$output"
}

# Verificar versiones de software
check_software_versions() {
    if [ "$CHECK_VERSIONS" != "true" ]; then
        return 0
    fi
    
    print_header "VERIFICANDO VERSIONES DE SOFTWARE"
    
    check_nginx_version
    check_docker_version
}

# Función principal
main() {
    local start_time=$(date +%s)
    
    # Crear estructura y configuración
    create_directory_structure
    create_default_config
    load_config
    
    # Enviar notificación de inicio si está habilitado
    if [ "$SLACK_ENABLED" = "true" ] && [ -n "$SLACK_WEBHOOK_URL" ]; then
        send_simple_slack_message "🔒 Iniciando auditoría de seguridad en $(hostname)"
    fi
    
    log_message "=== INICIANDO AUDITORÍA DE SEGURIDAD DEL SISTEMA ===" "INFO"
    log_message "Hostname: $(hostname)" "INFO"
    log_message "Slack habilitado: $SLACK_ENABLED" "INFO"
    
    # Detectar distribución
    detect_distro
    
    # Ejecutar verificaciones
    check_updates
    check_disk_space
    check_memory
    check_services
    check_software_versions
    check_vulnerabilities
    check_security_config
    
    # Enviar notificación final a Slack
    echo "🔧 Debug - Preparando notificación final..."
    echo "🔧 Debug - Total checks: $TOTAL_CHECKS"
    echo "🔧 Debug - Failed: $FAILED_CHECKS, Warning: $WARNING_CHECKS, Success: $SUCCESS_CHECKS"
    
    if [ "$SLACK_ENABLED" = "true" ] && [ -n "$SLACK_WEBHOOK_URL" ]; then
        send_slack_notification
    else
        log_message "Slack no configurado correctamente para envío final" "INFO"
    fi
    
    # Resumen final
    print_header "AUDITORÍA COMPLETADA"
    log_message "Verificaciones completadas: $TOTAL_CHECKS" "SUCCESS"
    log_message "✅ Exitosas: $SUCCESS_CHECKS" "SUCCESS"
    log_message "⚠️ Advertencias: $WARNING_CHECKS" "WARNING"
    log_message "❌ Errores: $FAILED_CHECKS" "ERROR"
    
    echo ""
    echo "📁 Archivos generados:"
    echo "   📄 Log: $LOG_FILE"
    echo "   📊 HTML: $HTML_REPORT" 
    echo "   📋 JSON: $JSON_REPORT"
    
    # Mostrar recomendaciones si hay problemas
    if [ $FAILED_CHECKS -gt 0 ] || [ $WARNING_CHECKS -gt 0 ]; then
        echo ""
        echo "🔧 Recomendaciones de seguridad:"
        echo "   • Actualizar paquetes con vulnerabilidades"
        echo "   • Revisar configuración de servicios"
        echo "   • Verificar logs de seguridad"
        echo "   • Considerar implementar fail2ban"
    fi
}

# Verificar parámetros
case "$1" in
    --help|-h)
        echo "Script de Auditoría de Seguridad con Slack"
        echo "=========================================="
        echo ""
        echo "Uso: $0 [opción]"
        echo ""
        echo "Opciones:"
        echo "  --help           Mostrar esta ayuda"
        echo "  --test-slack     Enviar mensaje de prueba a Slack"
        echo "  --versions       Solo verificar versiones de software"
        echo "  --security       Solo verificar vulnerabilidades"
        echo ""
        echo "Verificaciones incluidas:"
        echo "  ✓ Actualizaciones del sistema"
        echo "  ✓ Espacio en disco y memoria"
        echo "  ✓ Estado de servicios críticos"
        echo "  ✓ Versiones de Nginx y Docker"
        echo "  ✓ Vulnerabilidades de seguridad"
        echo "  ✓ Configuración de seguridad SSH/Firewall"
        echo ""
        exit 0
        ;;
    --test-slack)
        create_directory_structure
        create_default_config
        load_config
        if [ "$SLACK_ENABLED" = "true" ] && [ -n "$SLACK_WEBHOOK_URL" ]; then
            send_simple_slack_message "🧪 Prueba del sistema de auditoría de seguridad desde $(hostname)"
            echo "✅ Mensaje de prueba enviado a Slack"
        else
            echo "❌ Slack no está habilitado o no hay webhook configurado"
            echo "   SLACK_ENABLED: $SLACK_ENABLED"
            echo "   SLACK_WEBHOOK_URL: ${SLACK_WEBHOOK_URL:0:50}..."
        fi
        exit 0
        ;;
    --versions)
        create_directory_structure
        create_default_config
        load_config
        detect_distro
        check_software_versions
        exit 0
        ;;
    --security)
        create_directory_structure
        create_default_config
        load_config
        detect_distro
        check_vulnerabilities
        check_security_config
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac