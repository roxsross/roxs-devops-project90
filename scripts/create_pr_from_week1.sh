#!/bin/bash

# Script para crear PR desde week-1 a master (manteniendo todas las ramas)
# Uso: ./create_pr_from_week1.sh

set -e

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 Creando PR para llevar cambios de week-1 a master${NC}"
echo

# Verificar que estamos en week-1
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "week-1" ]; then
    echo -e "${YELLOW}⚠️  Cambiando a rama week-1...${NC}"
    git checkout week-1
fi

# Mostrar resumen de cambios
echo -e "${BLUE}📋 Resumen de cambios que se llevarán a master:${NC}"
git log --oneline master..week-1
echo

echo -e "${BLUE}📁 Archivos modificados:${NC}"
git diff --name-only master..week-1 | head -10
TOTAL_FILES=$(git diff --name-only master..week-1 | wc -l)
if [ $TOTAL_FILES -gt 10 ]; then
    echo "... y $(($TOTAL_FILES - 10)) archivos más"
fi
echo

# Confirmar
read -p "¿Proceder con el PR desde week-1 a master? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Operación cancelada"
    exit 0
fi

# Asegurar que week-1 esté actualizada en remoto
echo -e "${BLUE}📤 Asegurando que week-1 esté actualizada en el remoto...${NC}"
git push origin week-1

# Obtener URL del repositorio
REPO_URL=$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')

echo
echo -e "${GREEN}✅ ¡Listo para crear el PR!${NC}"
echo
echo -e "${BLUE}🔗 Opciones para crear el PR:${NC}"
echo
echo "1. 🌐 URL directa:"
echo "   https://github.com/$REPO_URL/compare/master...week-1"
echo
echo "2. 📋 O copia esta información para el PR:"
echo "   • Base branch: master"
echo "   • Head branch: week-1"
echo "   • Título sugerido: 'Week 1 - Implementación completa'"
echo "   • Descripción sugerida:"
echo "     - Añadido soporte completo para Ansible"
echo "     - Configuración de desafío día 6"
echo "     - Implementación de rox-voting-app"
echo "     - Scripts de automatización"
echo "     - Configuraciones de Vagrant"
echo
echo -e "${YELLOW}📝 Nota importante:${NC}"
echo "• La rama 'week-1' se mantendrá intacta después del merge"
echo "• La rama 'master' se actualizará con todos los cambios"
echo "• No se eliminará ninguna rama automáticamente"
echo
echo -e "${GREEN}🎉 ¡Ve a GitHub y crea tu PR!${NC}"
