#!/bin/bash

# Скрипт проверки всех файлов OpenVPN Docker установки

echo "🔍 Проверка файлов OpenVPN Docker"
echo "=================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Список обязательных файлов
REQUIRED_FILES=(
    "install.sh"
    "Dockerfile"
    "docker-compose.yml"
    "entrypoint.sh"
    "client-manager.sh"
    "README-DOCKER.md"
    ".env.example"
    "quick-start.sh"
)

# Проверка существования файлов
echo "📁 Проверка файлов:"
missing_files=0

for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        echo "  ✅ $file"
    else
        echo "  ❌ $file (отсутствует)"
        ((missing_files++))
    fi
done

echo ""

# Проверка прав доступа
echo "🔐 Проверка прав доступа:"
EXECUTABLE_FILES=(
    "install.sh"
    "entrypoint.sh"
    "client-manager.sh"
    "quick-start.sh"
)

for file in "${EXECUTABLE_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        if [[ -x "$file" ]]; then
            echo "  ✅ $file (исполняемый)"
        else
            echo "  ⚠️  $file (не исполняемый)"
            chmod +x "$file"
            echo "      ↳ Права исправлены"
        fi
    fi
done

echo ""

# Проверка синтаксиса bash скриптов
echo "🧪 Проверка синтаксиса bash скриптов:"
BASH_FILES=(
    "install.sh"
    "entrypoint.sh"
    "client-manager.sh"
    "quick-start.sh"
)

syntax_errors=0

for file in "${BASH_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        if bash -n "$file" 2>/dev/null; then
            echo "  ✅ $file (синтаксис OK)"
        else
            echo "  ❌ $file (ошибка синтаксиса)"
            ((syntax_errors++))
        fi
    fi
done

echo ""

# Проверка Docker файлов
echo "🐳 Проверка Docker файлов:"

# Dockerfile
if [[ -f "Dockerfile" ]]; then
    if grep -q "FROM ubuntu" Dockerfile && grep -q "ENTRYPOINT" Dockerfile; then
        echo "  ✅ Dockerfile (структура OK)"
    else
        echo "  ⚠️  Dockerfile (может быть неполным)"
    fi
fi

# docker-compose.yml
if [[ -f "docker-compose.yml" ]]; then
    if grep -q "version:" docker-compose.yml && grep -q "services:" docker-compose.yml; then
        echo "  ✅ docker-compose.yml (структура OK)"
    else
        echo "  ⚠️  docker-compose.yml (может быть неполным)"
    fi
fi

echo ""

# Размеры файлов
echo "📊 Размеры файлов:"
for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        size=$(wc -c < "$file")
        if [[ $size -gt 100 ]]; then
            echo "  ✅ $file (${size} байт)"
        else
            echo "  ⚠️  $file (${size} байт - возможно пустой)"
        fi
    fi
done

echo ""

# Финальный отчет
echo "📋 Итоговый отчет:"
if [[ $missing_files -eq 0 && $syntax_errors -eq 0 ]]; then
    echo "  🎉 Все файлы готовы к использованию!"
    echo ""
    echo "🚀 Быстрый старт:"
    echo "  1. Скопируйте все файлы на Ubuntu сервер"
    echo "  2. Запустите: sudo ./install.sh"
    echo "  3. Или для тестирования: ./quick-start.sh"
    echo ""
    echo "📚 Документация: README-DOCKER.md"
else
    echo "  ⚠️  Обнаружены проблемы:"
    [[ $missing_files -gt 0 ]] && echo "    - Отсутствуют $missing_files файл(ов)"
    [[ $syntax_errors -gt 0 ]] && echo "    - Ошибки синтаксиса в $syntax_errors файл(ах)"
    echo ""
    echo "  Исправьте проблемы перед использованием."
fi

echo ""
echo "💡 Для получения помощи:"
echo "  • Прочитайте README-DOCKER.md"
echo "  • Запустите: ./install.sh без параметров"
echo "  • Проверьте логи: journalctl -f"