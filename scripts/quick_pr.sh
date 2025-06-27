#!/bin/bash

# Script rápido para crear PR - versión simple
# Uso: ./quick_pr.sh <nombre-rama>

BRANCH_NAME=${1:-"feature/update-$(date +%Y%m%d-%H%M)"}

echo "🚀 Creando rama para PR: $BRANCH_NAME"

# Actualizar master
echo "📥 Actualizando master..."
git checkout master
git pull upstream master
git push origin master

# Crear rama
echo "🌿 Creando rama de trabajo..."
git checkout -b $BRANCH_NAME

# Información
echo "✅ Rama '$BRANCH_NAME' creada y lista para cambios"
echo ""
echo "📋 Próximos pasos:"
echo "1. Haz tus cambios"
echo "2. git add ."
echo "3. git commit -m 'Tu mensaje'"
echo "4. git push origin $BRANCH_NAME"
echo "5. Crear PR en GitHub"
echo ""
echo "🔗 URL para PR: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/compare/master...$BRANCH_NAME"
