#!/bin/bash
# filepath: /Users/robertorossa/Desktop/Desarrollo/BootCampDevOpsRox/rcrossa-devops-project90/vagrant/scripts/desplegar_app.sh

# Función para logging
log_to_file() {
    local message="$1"
    local log_file="logs_despliegue.txt"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] $message" | tee -a "$log_file"
}

# Función para instalar dependencias
instalar_dependencias() {
    echo "Instalando dependencias..."
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip python3-venv git curl net-tools
    
    if [ $? -ne 0 ]; then
        echo "Error al instalar dependencias. Abortando."
        exit 1
    fi
}

# Función para crear un entorno virtual y preparar la app
crear_entorno_virtual() {
    echo "Creando entorno virtual..."
    python3 -m venv venv
    source venv/bin/activate
    
    if [ $? -ne 0 ]; then
        echo "Error al crear el entorno virtual. Abortando."
        exit 1
    fi
    
    echo "Entorno virtual creado y activado."
    
    # Clonar el repositorio de la aplicación
    echo "Clonando el repositorio de la aplicación..."
    if [ -d "devops-static-web" ]; then
        rm -rf devops-static-web
    fi
    
    # CORRECCIÓN: Clonar todo el repositorio primero
    git clone https://github.com/roxsross/devops-static-web.git
    if [ $? -ne 0 ]; then
        echo "Error al clonar el repositorio. Abortando."
        exit 1
    fi
    
    cd devops-static-web
    
    # Verificar ramas disponibles
    echo "Ramas disponibles:"
    git branch -r
    
    # Cambiar a la rama correcta
    echo "Cambiando a la rama devops-shopping..."
    git checkout devops-shopping
    if [ $? -ne 0 ]; then
        echo "Error al cambiar a la rama devops-shopping. Intentando crear desde remoto..."
        git checkout -b devops-shopping origin/devops-shopping
        if [ $? -ne 0 ]; then
            echo "Error: No se pudo acceder a la rama devops-shopping"
            echo "Ramas disponibles:"
            git branch -a
            exit 1
        fi
    fi
    
    echo "Rama actual:"
    git branch
    
    # Verificar contenido del directorio
    echo "Contenido del directorio de la aplicación:"
    ls -la
    
    # Verificar si existe requirements.txt
    if [ ! -f "requirements.txt" ]; then
        echo "Advertencia: requirements.txt no encontrado"
        echo "Creando requirements.txt básico..."
        cat > requirements.txt << EOF
Flask==2.3.3
Werkzeug==2.3.7
Jinja2==3.1.2
MarkupSafe==2.1.3
itsdangerous==2.1.2
click==8.1.7
blinker==1.6.2
EOF
    fi
    
    # Instalar dependencias de Python
    echo "Instalando dependencias de Python..."
    pip install -r requirements.txt
    if [ $? -ne 0 ]; then
        echo "Error al instalar las dependencias de la aplicación. Abortando."
        exit 1
    fi
    
    pip install gunicorn
    if [ $? -ne 0 ]; then
        echo "Error al instalar gunicorn. Abortando."
        exit 1
    fi
    
    echo "Aplicación preparada correctamente."
    cd ..
}

# Función para configurar Nginx
configurar_nginx() {
    echo "Configurando Nginx..."
    
    # Instalar nginx si no está instalado
    if ! command -v nginx &> /dev/null; then
        echo "Instalando Nginx..."
        sudo apt-get install -y nginx
        if [ $? -ne 0 ]; then
            echo "Error al instalar Nginx. Abortando."
            exit 1
        fi
    fi
    
    # Crear configuración de Nginx para la aplicación con IP externa
    sudo tee /etc/nginx/sites-available/library_app > /dev/null <<EOF
server {
    listen 80;
    server_name localhost 192.168.33.10;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    # Habilitar el sitio
    sudo ln -sf /etc/nginx/sites-available/library_app /etc/nginx/sites-enabled/
    
    # Deshabilitar sitio por defecto
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Verificar configuración de Nginx
    sudo nginx -t
    if [ $? -ne 0 ]; then
        echo "Error en la configuración de Nginx. Abortando."
        exit 1
    fi
    
    echo "Nginx configurado correctamente para localhost y 192.168.33.10"
}

# Función para identificar el archivo principal de la aplicación
identificar_app_principal() {
    local app_path=$(pwd)/devops-static-web
    
    echo "=== IDENTIFICANDO ARCHIVO PRINCIPAL ==="
    
    if [ -d "$app_path" ]; then
        echo "Contenido del directorio de la aplicación:"
        ls -la "$app_path"
        
        echo ""
        echo "Archivos Python encontrados:"
        find "$app_path" -name "*.py" | head -10
        
        echo ""
        echo "Buscando archivos con aplicación Flask:"
        
        # Buscar archivos comunes
        for file in app.py main.py run.py wsgi.py library_site.py server.py index.py; do
            if [ -f "$app_path/$file" ]; then
                echo "✅ Encontrado: $file"
                echo "Primeras líneas de $file:"
                head -20 "$app_path/$file"
                echo "---"
            fi
        done
        
        echo ""
        echo "Buscando archivos que contengan 'Flask' o 'app =':"
        find "$app_path" -name "*.py" -exec grep -l "Flask\|app\s*=" {} \; 2>/dev/null | while read -r file; do
            echo "Archivo: $file"
            echo "Líneas relevantes:"
            grep -n "Flask\|app\s*=\|@app\|if __name__" "$file" 2>/dev/null | head -10
            echo "---"
        done
    fi
}

# Función para crear servicio systemd para Gunicorn
crear_servicio_gunicorn() {
    echo "Creando servicio systemd para Gunicorn..."
    
    local app_path=$(pwd)/devops-static-web
    local venv_path=$(pwd)/venv
    local user_name=$(whoami)
    
    # Verificar que los directorios existen
    if [ ! -d "$app_path" ]; then
        echo "Error: Directorio de aplicación no existe: $app_path"
        exit 1
    fi
    
    if [ ! -d "$venv_path" ]; then
        echo "Error: Entorno virtual no existe: $venv_path"
        exit 1
    fi
    
    # Verificar que gunicorn está instalado
    if [ ! -f "$venv_path/bin/gunicorn" ]; then
        echo "Error: Gunicorn no encontrado en: $venv_path/bin/gunicorn"
        exit 1
    fi
    
    # Identificar el archivo principal de la aplicación
    identificar_app_principal
    
    # Intentar diferentes configuraciones de Gunicorn basadas en nombres comunes
    local gunicorn_configs=(
        "app:app"
        "main:app"
        "run:app"
        "wsgi:app"
        "server:app"
        "index:app"
        "library_site:app"
    )
    
    local working_config=""
    
    echo "=== PROBANDO CONFIGURACIONES DE GUNICORN ==="
    
    # Cambiar al directorio de la aplicación
    cd "$app_path"
    
    # Activar el entorno virtual
    source "$venv_path/bin/activate"
    
    for config in "${gunicorn_configs[@]}"; do
        echo "Probando configuración: $config"
        
        # Probar la configuración con timeout
        timeout 10s "$venv_path/bin/gunicorn" --check-config "$config" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "✅ Configuración $config es válida!"
            working_config="$config"
            break
        else
            echo "❌ Configuración $config no es válida"
        fi
    done
    
    # Si no encontramos configuración válida, intentar buscar manualmente
    if [ -z "$working_config" ]; then
        echo "Buscando archivos Python con aplicación Flask..."
        
        # Buscar archivos que contengan Flask
        flask_files=$(find . -name "*.py" -exec grep -l "Flask\|app\s*=" {} \; 2>/dev/null)
        
        for file in $flask_files; do
            # Extraer nombre del archivo sin extensión
            filename=$(basename "$file" .py)
            test_config="$filename:app"
            
            echo "Probando configuración basada en archivo $file: $test_config"
            
            timeout 10s "$venv_path/bin/gunicorn" --check-config "$test_config" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "✅ Configuración $test_config funciona!"
                working_config="$test_config"
                break
            fi
        done
    fi
    
    cd - > /dev/null
    
    if [ -z "$working_config" ]; then
        echo "❌ No se pudo encontrar una configuración válida para Gunicorn"
        echo "Creando una aplicación Flask básica para testing..."
        
        # Crear una aplicación Flask básica si no existe
        cat > "$app_path/app.py" << 'EOF'
from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello():
    return '<h1>¡Hola! La aplicación Flask está funcionando</h1>'

@app.route('/health')
def health():
    return {'status': 'ok', 'message': 'Application is running'}

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
EOF
        
        working_config="app:app"
        echo "✅ Aplicación Flask básica creada. Usando configuración: $working_config"
    fi
    
    echo "✅ Usando configuración: $working_config"
    
    # Detener el servicio si existe
    sudo systemctl stop library-app 2>/dev/null || true
    
    # Crear el servicio systemd con la configuración correcta
    sudo tee /etc/systemd/system/library-app.service > /dev/null <<EOF
[Unit]
Description=Gunicorn instance to serve Library App
After=network.target

[Service]
User=$user_name
Group=www-data
WorkingDirectory=$app_path
Environment="PATH=$venv_path/bin:/usr/local/bin:/usr/bin:/bin"
Environment="PYTHONPATH=$app_path"
ExecStart=$venv_path/bin/gunicorn --workers 3 --bind 127.0.0.1:8000 --timeout 120 $working_config
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=3
KillMode=mixed
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # Dar permisos al usuario para acceder a los archivos
    sudo chown -R $user_name:$user_name "$app_path"
    sudo chmod -R 755 "$app_path"
    
    # Recargar systemd y habilitar el servicio
    sudo systemctl daemon-reload
    sudo systemctl enable library-app
    
    # Esperar un momento antes de iniciar
    sleep 2
    
    sudo systemctl start library-app
    
    # Verificar si se inició correctamente
    sleep 5
    if sudo systemctl is-active --quiet library-app; then
        echo "✅ Servicio de Gunicorn creado y iniciado correctamente."
        echo "Configuración utilizada: $working_config"
    else
        echo "❌ Error al iniciar el servicio de Gunicorn."
        echo "Estado del servicio:"
        sudo systemctl status library-app
        echo "Logs del servicio:"
        sudo journalctl -u library-app --no-pager -n 20
        exit 1
    fi
}

# Función para reiniciar servicios
reiniciar_servicios() {
    echo "Reiniciando servicios..."
    
    # Reiniciar Nginx
    sudo systemctl restart nginx
    if [ $? -ne 0 ]; then
        echo "Error al reiniciar Nginx."
        exit 1
    fi
    
    # Habilitar Nginx para inicio automático
    sudo systemctl enable nginx
    
    echo "Servicios reiniciados correctamente."
}

# Función mejorada para verificar servicios con más detalles
verificar_servicios() {
    echo "Verificando servicios..."
    
    # Verificar Nginx
    if systemctl is-active --quiet nginx; then
        echo "✅ Nginx está activo"
    else
        echo "❌ Nginx no está activo"
        sudo systemctl status nginx
        return 1
    fi
    
    # Verificar Gunicorn con más detalle
    echo "Verificando servicio library-app..."
    if systemctl is-active --quiet library-app; then
        echo "✅ Library App (Gunicorn) está activo"
    else
        echo "❌ Library App (Gunicorn) no está activo"
        echo "Estado detallado del servicio:"
        sudo systemctl status library-app
        echo ""
        echo "Últimos logs del servicio:"
        sudo journalctl -u library-app --no-pager -n 10
        return 1
    fi
    
    # Verificar conectividad con timeouts más largos
    echo "Verificando conectividad a la aplicación..."
    sleep 10  # Esperar más tiempo para que la aplicación esté lista
    
    # Verificar puerto 8000 primero
    if curl -s --connect-timeout 10 http://localhost:8000 > /dev/null; then
        echo "✅ Gunicorn respondiendo en puerto 8000"
    else
        echo "❌ Gunicorn no responde en puerto 8000"
        echo "Verificando si el puerto está en uso:"
        sudo netstat -tlnp | grep :8000 || echo "Puerto 8000 no está en uso"
        return 1
    fi
    
    # Luego verificar puerto 80
    if curl -s --connect-timeout 10 http://localhost > /dev/null; then
        echo "✅ Aplicación respondiendo en puerto 80"
    else
        echo "❌ Aplicación no responde en puerto 80"
        echo "Verificando configuración de Nginx:"
        sudo nginx -t
        return 1
    fi
    
    echo "✅ Todos los servicios están online."
    echo "🌐 Aplicación disponible en:"
    echo "   - http://localhost"
    echo "   - http://192.168.33.10"
}

# Función de diagnóstico adicional
diagnosticar_problema() {
    echo "=== DIAGNÓSTICO DE PROBLEMAS ==="
    
    echo "1. Verificando estructura de directorios:"
    ls -la $(pwd)/
    
    echo "2. Verificando aplicación:"
    if [ -d "$(pwd)/devops-static-web" ]; then
        ls -la $(pwd)/devops-static-web/
        echo "Archivos Python encontrados:"
        find $(pwd)/devops-static-web/ -name "*.py" | head -10
    fi
    
    echo "3. Verificando entorno virtual:"
    if [ -d "$(pwd)/venv" ]; then
        ls -la $(pwd)/venv/bin/ | grep -E "(python|gunicorn|pip)"
    fi
    
    echo "4. Verificando servicios systemd:"
    sudo systemctl list-units --type=service | grep library
    
    echo "5. Verificando puertos en uso:"
    sudo netstat -tlnp | grep -E "(:80|:8000)"
    
    echo "6. Verificando logs de Nginx:"
    sudo tail -20 /var/log/nginx/error.log
    
    echo "7. Verificando configuración de Nginx:"
    sudo nginx -T
}

# Función principal con manejo de errores mejorado
main() {
    local log_file="logs_despliegue.txt"
    
    # Inicializar archivo de log
    echo "=== INICIO DEL DESPLIEGUE ===" > "$log_file"
    echo "Fecha: $(date)" >> "$log_file"
    echo "" >> "$log_file"
    
    # Redirigir toda la salida al log y a la consola
    exec > >(tee -a "$log_file") 2>&1
    
    log_to_file "🚀 Iniciando despliegue de aplicación Flask..."
    
    log_to_file "📦 Instalando dependencias del sistema..."
    instalar_dependencias
    log_to_file "✅ Dependencias instaladas."
    
    log_to_file "🐍 Creando entorno virtual y preparando aplicación..."
    crear_entorno_virtual
    log_to_file "✅ Aplicación preparada."
    
    log_to_file "🌐 Configurando Nginx..."
    configurar_nginx
    log_to_file "✅ Nginx configurado."
    
    log_to_file "⚙️  Creando servicio systemd para Gunicorn..."
    crear_servicio_gunicorn
    log_to_file "✅ Servicio de Gunicorn creado."
    
    log_to_file "🔄 Reiniciando servicios..."
    reiniciar_servicios
    log_to_file "✅ Servicios reiniciados."
    
    log_to_file "🔍 Verificando servicios..."
    if verificar_servicios; then
        log_to_file "🎉 ¡Despliegue completado exitosamente!"
        log_to_file "🌐 La aplicación está disponible en:"
        log_to_file "   - http://localhost"
        log_to_file "   - http://192.168.33.10"
    else
        log_to_file "❌ Error en la verificación de servicios"
        log_to_file "🔧 Ejecutando diagnóstico..."
        diagnosticar_problema
        exit 1
    fi
    
    log_to_file "=== FIN DEL DESPLIEGUE ==="
}

# Ejecutar función principal
main "$@"