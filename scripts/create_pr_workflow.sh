#!/bin/bash

# Script para crear un Pull Request manteniendo la rama
# Uso: ./create_pr_workflow.sh <nombre-rama> <descripcion-commit>

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mostrar mensajes con color
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Verificar parámetros
if [ $# -lt 1 ]; then
    print_error "Uso: $0 <nombre-rama> [descripcion-commit]"
    print_error "Ejemplo: $0 feature/nueva-funcionalidad 'Agregar nueva funcionalidad'"
    exit 1
fi

BRANCH_NAME=$1
COMMIT_MESSAGE=${2:-"Actualización automática"}

print_message "Iniciando flujo de trabajo para crear PR..."
print_message "Rama: $BRANCH_NAME"
print_message "Mensaje de commit: $COMMIT_MESSAGE"

# Verificar si estamos en un repositorio git
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "No estás en un repositorio Git"
    exit 1
fi

# Paso 1: Guardar rama actual
CURRENT_BRANCH=$(git branch --show-current)
print_step "Rama actual: $CURRENT_BRANCH"

# Paso 2: Actualizar master desde upstream
print_step "Actualizando master desde upstream..."
git checkout master
git pull upstream master
git push origin master

# Paso 3: Crear o cambiar a la rama de trabajo
print_step "Preparando rama de trabajo: $BRANCH_NAME"
if git show-ref --verify --quiet refs/heads/$BRANCH_NAME; then
    print_warning "La rama $BRANCH_NAME ya existe. Cambiando a ella..."
    git checkout $BRANCH_NAME
    # Actualizar la rama con los últimos cambios de master
    print_step "Actualizando rama con cambios de master..."
    git merge master
else
    print_message "Creando nueva rama: $BRANCH_NAME"
    git checkout -b $BRANCH_NAME
fi

# Paso 4: Verificar si hay cambios para commitear
print_step "Verificando cambios..."
if git diff --quiet && git diff --staged --quiet; then
    print_warning "No hay cambios para commitear"
    read -p "¿Quieres continuar para hacer push de la rama actual? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "Operación cancelada"
        exit 0
    fi
else
    # Mostrar estado
    print_step "Estado actual:"
    git status --short
    
    # Confirmar cambios
    read -p "¿Quieres commitear estos cambios? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git add .
        git commit -m "$COMMIT_MESSAGE"
        print_message "Cambios commiteados"
    else
        print_warning "Cambios no commiteados. Continuando con push..."
    fi
fi

# Paso 5: Push de la rama
print_step "Haciendo push de la rama $BRANCH_NAME..."
git push origin $BRANCH_NAME

# Paso 6: Información para crear PR
print_message "¡Rama pusheada exitosamente!"
echo
print_step "Próximos pasos para crear el Pull Request:"
echo "1. Ve a tu repositorio en GitHub"
echo "2. Verás un banner para crear PR desde la rama '$BRANCH_NAME'"
echo "3. O ve a: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/compare/master...$BRANCH_NAME"
echo
print_message "La rama '$BRANCH_NAME' se mantendrá intacta después del merge del PR"
print_warning "Recuerda eliminar la rama manualmente cuando ya no la necesites:"
echo "   git branch -d $BRANCH_NAME (local)"
echo "   git push origin --delete $BRANCH_NAME (remota)"
echo

# Paso 7: Volver a la rama original si es diferente
if [ "$CURRENT_BRANCH" != "$BRANCH_NAME" ]; then
    print_step "Volviendo a la rama original: $CURRENT_BRANCH"
    git checkout $CURRENT_BRANCH
fi

print_message "¡Flujo de trabajo completado!"
