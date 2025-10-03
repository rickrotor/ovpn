#!/bin/bash
set -e

# --- Настройки ---
CONTAINER_NAME="openvpn-server"
DATA_DIR="$PWD/ovpn-data"
SERVER_PORT=1194
VPN_SUBNET="10.8.0.0/24"

# 👉 Укажи свой статический IP здесь:
SERVER_IP="104.238.24.172"
SERVER_URL="udp://$SERVER_IP"

CLIENT_NAME="client1"

# --- Проверка Docker ---
if ! command -v docker &> /dev/null
then
    echo "Docker не найден. Устанавливаем..."
    apt update
    apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io
    echo "Docker установлен."
else
    echo "Docker уже установлен."
fi

# --- Проверка Docker Compose ---
if ! command -v docker-compose &> /dev/null
then
    echo "Docker Compose не найден. Устанавливаем..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo "Docker Compose установлен."
else
    echo "Docker Compose уже установлен."
fi

# --- Создаём директорию для конфигов ---
mkdir -p "$DATA_DIR"

# --- Генерация конфигурации OpenVPN ---
if [ ! -f "$DATA_DIR/pki/ca.crt" ]; then
    echo "Генерируем конфигурацию OpenVPN для $SERVER_URL ..."
    docker run -v "$DATA_DIR:/etc/openvpn" --rm kylemanna/openvpn ovpn_genconfig -u "$SERVER_URL"
    docker run -v "$DATA_DIR:/etc/openvpn" --rm -it kylemanna/openvpn ovpn_initpki nopass
else
    echo "Конфигурация OpenVPN уже существует."
fi

# --- Исправляем конфигурацию (убираем comp-lzo) ---
CONF_FILE="$DATA_DIR/openvpn.conf"
if [ -f "$CONF_FILE" ]; then
    echo "Правим openvpn.conf для отключения comp-lzo..."
    # Убираем все упоминания comp-lzo и compress
    sed -i '/comp-lzo/d' "$CONF_FILE"
    sed -i '/compress/d' "$CONF_FILE"
    sed -i '/push "compress/d' "$CONF_FILE"

    # Добавляем безопасный режим (stub-v2)
    echo 'compress stub-v2' >> "$CONF_FILE"
    echo 'push "compress stub-v2"' >> "$CONF_FILE"
else
    echo "⚠️ Файл $CONF_FILE не найден. Возможно конфиг ещё не сгенерирован."
fi

# --- Запуск контейнера ---
if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
    echo "Контейнер OpenVPN уже запущен."
else
    echo "Запускаем контейнер OpenVPN..."
    docker run -v "$DATA_DIR:/etc/openvpn" \
        -d --name $CONTAINER_NAME \
        -p $SERVER_PORT:1194/udp \
        --cap-add=NET_ADMIN \
        kylemanna/openvpn
fi

# --- Настройка NAT и форвардинга ---
echo "Включаем IP forwarding и NAT..."
docker exec -it $CONTAINER_NAME bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
docker exec -it $CONTAINER_NAME bash -c "iptables -t nat -A POSTROUTING -s $VPN_SUBNET -o eth0 -j MASQUERADE"

# --- Генерация клиентского профиля ---
if [ ! -f "$CLIENT_NAME.ovpn" ]; then
    echo "Создаём клиентский профиль $CLIENT_NAME.ovpn..."
    docker run -v "$DATA_DIR:/etc/openvpn" --rm -it kylemanna/openvpn easyrsa build-client-full $CLIENT_NAME nopass
    docker run -v "$DATA_DIR:/etc/openvpn" --rm kylemanna/openvpn ovpn_getclient $CLIENT_NAME > "$CLIENT_NAME.ovpn"
    echo "Готово! Клиентский файл: $CLIENT_NAME.ovpn"
else
    echo "Клиентский профиль уже существует: $CLIENT_NAME.ovpn"
fi
