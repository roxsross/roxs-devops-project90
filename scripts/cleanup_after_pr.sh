#!/bin/bash

# Script para limpiar después de PR mergeado
# Uso: ./cleanup_after_pr.sh <nombre-rama>

set -e

BRANCH_NAME=$1

if [ -z "$BRANCH_NAME" ]; then
    echo "❌ Error: Especifica el nombre de la rama a limpiar"
    echo "Uso: $0 <nombre-rama>"
    echo ""
    echo "Ramas disponibles:"
    git branch | grep -v master | grep -v "^\*"
    exit 1
fi

echo "🧹 Limpiando después de PR mergeado para rama: $BRANCH_NAME"

# Verificar si la rama existe
if ! git show-ref --verify --quiet refs/heads/$BRANCH_NAME; then
    echo "❌ La rama $BRANCH_NAME no existe localmente"
    exit 1
fi

# Ir a master y actualizar
echo "📥 Actualizando master..."
git checkout master
git pull upstream master
git push origin master

# Eliminar rama local
echo "🗑️  Eliminando rama local $BRANCH_NAME..."
git branch -d $BRANCH_NAME

# Preguntar si eliminar rama remota
read -p "¿Eliminar también la rama remota? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Eliminando rama remota $BRANCH_NAME..."
    git push origin --delete $BRANCH_NAME
    echo "✅ Rama remota eliminada"
else
    echo "⚠️  Rama remota mantenida. Puedes eliminarla más tarde con:"
    echo "   git push origin --delete $BRANCH_NAME"
fi

echo "✅ Limpieza completada!"
echo "📊 Estado actual:"
git status --short
