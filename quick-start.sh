#!/bin/bash

# OpenVPN Docker Quick Start
# Быстрый запуск для тестирования на локальной машине

set -e

echo "🚀 OpenVPN Docker Quick Start"
echo "=============================="
echo ""

# Проверка Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker не установлен. Установите Docker сначала."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Docker не запущен. Запустите Docker сначала."
    exit 1
fi

echo "✅ Docker готов к работе"

# Определение IP
SERVER_IP=${1:-"localhost"}
echo "🌐 Используемый IP: $SERVER_IP"

# Создание временной директории
WORK_DIR=$(mktemp -d)
echo "📁 Рабочая директория: $WORK_DIR"

cd "$WORK_DIR"

# Копирование файлов
cp "$(dirname "$0")/Dockerfile" .
cp "$(dirname "$0")/docker-compose.yml" .
cp "$(dirname "$0")/entrypoint.sh" .

# Настройка IP в docker-compose.yml
sed -i.bak "s/\${OPENVPN_SERVER_IP:-localhost}/$SERVER_IP/g" docker-compose.yml

echo "🔨 Сборка Docker образа..."
docker build -t openvpn-server-test .

echo "🚀 Запуск контейнера..."
docker run -d \
    --name openvpn-test \
    --cap-add=NET_ADMIN \
    --device=/dev/net/tun \
    -p 1194:1194/udp \
    -e OPENVPN_SERVER_IP="$SERVER_IP" \
    openvpn-server-test

echo "⏳ Ожидание инициализации (30 секунд)..."
sleep 30

echo "📋 Проверка статуса..."
if docker ps | grep -q openvpn-test; then
    echo "✅ Контейнер запущен успешно!"

    echo "📱 Получение конфигурации клиента..."
    docker cp openvpn-test:/client-configs/client1.ovpn ./client1.ovpn

    echo ""
    echo "🎉 Готово! Тестовый сервер запущен"
    echo "📄 Конфигурация клиента: $WORK_DIR/client1.ovpn"
    echo ""
    echo "🔧 Управление:"
    echo "  • Логи:      docker logs -f openvpn-test"
    echo "  • Остановка: docker stop openvpn-test"
    echo "  • Удаление:  docker rm -f openvpn-test && docker rmi openvpn-server-test"
    echo ""
    echo "🚪 Подключение: openvpn --config $WORK_DIR/client1.ovpn"

else
    echo "❌ Ошибка запуска контейнера"
    echo "Логи:"
    docker logs openvpn-test
    exit 1
fi