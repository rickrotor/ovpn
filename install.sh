#!/bin/bash

# OpenVPN Docker автоматический установщик
# Полная автоматическая установка OpenVPN сервера в Docker на чистом Ubuntu сервере
# Поддерживает Ubuntu 18.04, 20.04, 22.04

set -e

# === КОНФИГУРАЦИЯ ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/openvpn-docker"
CONTAINER_NAME="openvpn-server"
IMAGE_NAME="openvpn-server"
NETWORK_NAME="openvpn-net"
CLIENT_CONFIG_DIR="$INSTALL_DIR/client-configs"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# === ЛОГИРОВАНИЕ ===
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# === ПРОВЕРКИ ===
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен запускаться от имени root (sudo)"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        error "Не удалось определить операционную систему"
        exit 1
    fi

    . /etc/os-release

    if [[ "$ID" != "ubuntu" ]]; then
        error "Поддерживается только Ubuntu. Обнаружена: $ID"
        exit 1
    fi

    local version_id=${VERSION_ID%.*}
    if [[ "$version_id" -lt 18 ]]; then
        error "Поддерживается Ubuntu 18.04 и новее. Обнаружена: $VERSION_ID"
        exit 1
    fi

    log "Обнаружена совместимая ОС: Ubuntu $VERSION_ID"
}

get_public_ip() {
    local ip
    # Пробуем несколько сервисов для получения внешнего IP
    for service in "ifconfig.me" "icanhazip.com" "ipinfo.io/ip" "api.ipify.org"; do
        ip=$(curl -4 -s --max-time 10 "$service" 2>/dev/null | tr -d '\n\r ')
        if [[ -n "$ip" && "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$ip"
            return 0
        fi
    done

    # Fallback: локальный IP
    ip=$(ip route get 8.8.8.8 | grep -oP 'src \K\S+' 2>/dev/null)
    if [[ -n "$ip" ]]; then
        warning "Не удалось получить внешний IP, используем локальный: $ip"
        echo "$ip"
        return 0
    fi

    return 1
}

get_network_interface() {
    ip route | grep default | grep -o 'dev [^ ]*' | cut -d' ' -f2 | head -n1
}

wait_for_dpkg() {
    local timeout=300
    local count=0

    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
        if [ $count -ge $timeout ]; then
            error "Таймаут ожидания освобождения блокировки пакетного менеджера"
            return 1
        fi
        echo "Ожидание освобождения блокировки пакетного менеджера... ($count/$timeout)"
        sleep 2
        ((count+=2))
    done
    return 0
}

# === УСТАНОВКА ЗАВИСИМОСТЕЙ ===
update_system() {
    log "Обновление системы..."
    wait_for_dpkg

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y \
        curl \
        wget \
        gnupg \
        lsb-release \
        ca-certificates \
        software-properties-common \
        apt-transport-https \
        iptables-persistent \
        ufw

    log "Система обновлена"
}

install_docker() {
    if command -v docker &> /dev/null && command -v docker-compose &> /dev/null; then
        log "Docker уже установлен: $(docker --version)"
        return 0
    fi

    log "Установка Docker..."

    # Удаляем старые версии Docker
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Добавляем официальный GPG ключ Docker
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Добавляем репозиторий Docker
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Обновляем индекс пакетов и устанавливаем Docker
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Запускаем и включаем Docker
    systemctl start docker
    systemctl enable docker

    # Проверяем установку
    if ! docker --version; then
        error "Не удалось установить Docker"
        exit 1
    fi

    log "Docker успешно установлен: $(docker --version)"
}

# === НАСТРОЙКА СЕТИ ===
configure_firewall() {
    log "Настройка брандмауэра..."

    local interface=$(get_network_interface)

    # Настраиваем UFW (базовые правила)
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    # Разрешаем SSH
    ufw allow ssh

    # Разрешаем OpenVPN
    ufw allow 1194/udp

    # Настраиваем правила для Docker и OpenVPN
    # Добавляем правила в iptables для NAT
    iptables -t nat -A POSTROUTING -s 10.8.0.0/8 -o "$interface" -j MASQUERADE
    iptables -A INPUT -i tun+ -j ACCEPT
    iptables -A FORWARD -i tun+ -j ACCEPT
    iptables -A FORWARD -i tun+ -o "$interface" -j ACCEPT
    iptables -A FORWARD -i "$interface" -o tun+ -j ACCEPT
    iptables -A FORWARD -i docker0 -o "$interface" -j ACCEPT
    iptables -A FORWARD -i "$interface" -o docker0 -j ACCEPT

    # Сохраняем правила iptables
    netfilter-persistent save

    # Включаем IP forwarding
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
    sysctl -p

    # Включаем UFW
    ufw --force enable

    log "Брандмауэр настроен для интерфейса: $interface"
}

# === СОЗДАНИЕ ФАЙЛОВ DOCKER ===
create_project_structure() {
    log "Создание структуры проекта..."

    # Создаем основные директории
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CLIENT_CONFIG_DIR"
    mkdir -p "$INSTALL_DIR/scripts"
    mkdir -p "$INSTALL_DIR/config"

    # Копируем файлы из текущей директории если они есть
    if [[ -f "$SCRIPT_DIR/Dockerfile" ]]; then
        cp "$SCRIPT_DIR/Dockerfile" "$INSTALL_DIR/"
    fi

    if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
        cp "$SCRIPT_DIR/docker-compose.yml" "$INSTALL_DIR/"
    fi

    if [[ -f "$SCRIPT_DIR/entrypoint.sh" ]]; then
        cp "$SCRIPT_DIR/entrypoint.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/entrypoint.sh"
    fi

    if [[ -f "$SCRIPT_DIR/client-manager.sh" ]]; then
        cp "$SCRIPT_DIR/client-manager.sh" "$INSTALL_DIR/scripts/"
        chmod +x "$INSTALL_DIR/scripts/client-manager.sh"
    fi

    log "Структура проекта создана в $INSTALL_DIR"
}

generate_docker_files() {
    log "Генерация файлов Docker..."

    # Создаем Dockerfile если его нет
    if [[ ! -f "$INSTALL_DIR/Dockerfile" ]]; then
        create_dockerfile
    fi

    # Создаем docker-compose.yml если его нет
    if [[ ! -f "$INSTALL_DIR/docker-compose.yml" ]]; then
        create_docker_compose
    fi

    # Создаем entrypoint.sh если его нет
    if [[ ! -f "$INSTALL_DIR/entrypoint.sh" ]]; then
        create_entrypoint
    fi

    # Создаем скрипт управления клиентами если его нет
    if [[ ! -f "$INSTALL_DIR/scripts/client-manager.sh" ]]; then
        create_client_manager
    fi
}

create_dockerfile() {
    cat > "$INSTALL_DIR/Dockerfile" << 'EOF'
FROM ubuntu:22.04

# Установка часового пояса и локали
ENV TZ=UTC
ENV DEBIAN_FRONTEND=noninteractive

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Установка пакетов
RUN apt-get update && apt-get install -y \
    openvpn \
    easy-rsa \
    iptables \
    curl \
    wget \
    dnsutils \
    net-tools \
    procps \
    iputils-ping \
    nano \
    && rm -rf /var/lib/apt/lists/*

# Создание директорий
RUN mkdir -p /etc/openvpn/server \
    /etc/openvpn/client \
    /etc/openvpn/easy-rsa \
    /var/log/openvpn \
    /dev/net

# Создание устройства tun
RUN mkdir -p /dev/net && \
    mknod /dev/net/tun c 10 200 && \
    chmod 600 /dev/net/tun

# Копирование entrypoint скрипта
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Открытие портов
EXPOSE 1194/udp

# Volumes для постоянного хранения
VOLUME ["/etc/openvpn", "/var/log/openvpn"]

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
EOF

    log "Dockerfile создан"
}

create_docker_compose() {
    local public_ip="$1"

    cat > "$INSTALL_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  openvpn:
    container_name: $CONTAINER_NAME
    build: .
    restart: unless-stopped
    ports:
      - "1194:1194/udp"
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - openvpn_data:/etc/openvpn
      - openvpn_logs:/var/log/openvpn
      - ./client-configs:/client-configs
    environment:
      - OPENVPN_SERVER_IP=${public_ip}
      - OPENVPN_PORT=1194
      - OPENVPN_PROTOCOL=udp
      - OPENVPN_NETWORK=10.8.0.0
      - OPENVPN_NETMASK=255.255.255.0
      - OPENVPN_DNS1=1.1.1.1
      - OPENVPN_DNS2=1.0.0.1
    networks:
      - openvpn_network
    sysctls:
      - net.ipv4.ip_forward=1

volumes:
  openvpn_data:
    driver: local
  openvpn_logs:
    driver: local

networks:
  openvpn_network:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.20.0.0/16
EOF

    log "docker-compose.yml создан с IP: $public_ip"
}

create_entrypoint() {
    cat > "$INSTALL_DIR/entrypoint.sh" << 'EOF'
#!/bin/bash
set -e

echo "[INFO] Запуск OpenVPN сервера..."

# Переменные окружения с значениями по умолчанию
OPENVPN_SERVER_IP=${OPENVPN_SERVER_IP:-"localhost"}
OPENVPN_PORT=${OPENVPN_PORT:-1194}
OPENVPN_PROTOCOL=${OPENVPN_PROTOCOL:-"udp"}
OPENVPN_NETWORK=${OPENVPN_NETWORK:-"10.8.0.0"}
OPENVPN_NETMASK=${OPENVPN_NETMASK:-"255.255.255.0"}
OPENVPN_DNS1=${OPENVPN_DNS1:-"1.1.1.1"}
OPENVPN_DNS2=${OPENVPN_DNS2:-"1.0.0.1"}

# Директории
OPENVPN_DIR="/etc/openvpn"
SERVER_DIR="$OPENVPN_DIR/server"
CLIENT_DIR="$OPENVPN_DIR/client"
EASYRSA_DIR="$OPENVPN_DIR/easy-rsa"

# Инициализация PKI если не существует
if [[ ! -f "$SERVER_DIR/ca.crt" ]]; then
    echo "[INFO] Инициализация PKI..."

    # Настройка Easy-RSA
    ln -sf /usr/share/easy-rsa/* "$EASYRSA_DIR/"
    cd "$EASYRSA_DIR"

    # Создание конфигурации Easy-RSA
    cat > vars << 'VARS_EOF'
set_var EASYRSA_ALGO ec
set_var EASYRSA_DIGEST sha512
set_var EASYRSA_REQ_COUNTRY "RU"
set_var EASYRSA_REQ_PROVINCE "Moscow"
set_var EASYRSA_REQ_CITY "Moscow"
set_var EASYRSA_REQ_ORG "OpenVPN"
set_var EASYRSA_REQ_EMAIL "admin@example.com"
set_var EASYRSA_REQ_OU "IT Department"
set_var EASYRSA_KEY_SIZE 2048
set_var EASYRSA_CA_EXPIRE 3650
set_var EASYRSA_CERT_EXPIRE 3650
VARS_EOF

    # Инициализация PKI
    ./easyrsa init-pki

    # Создание CA
    echo "OpenVPN CA" | ./easyrsa build-ca nopass

    # Создание сертификата сервера
    echo "OpenVPN Server" | ./easyrsa gen-req server nopass
    echo "yes" | ./easyrsa sign-req server server

    # Создание DH параметров
    ./easyrsa gen-dh

    # Создание TLS-crypt ключа
    openvpn --genkey secret pki/ta.key

    # Создание CRL
    ./easyrsa gen-crl

    # Копирование файлов в директорию сервера
    cp pki/ca.crt "$SERVER_DIR/"
    cp pki/issued/server.crt "$SERVER_DIR/"
    cp pki/private/server.key "$SERVER_DIR/"
    cp pki/dh.pem "$SERVER_DIR/"
    cp pki/ta.key "$SERVER_DIR/"
    cp pki/crl.pem "$SERVER_DIR/"

    echo "[INFO] PKI инициализирован"
fi

# Создание конфигурации сервера
if [[ ! -f "$SERVER_DIR/server.conf" ]]; then
    echo "[INFO] Создание конфигурации сервера..."

    cat > "$SERVER_DIR/server.conf" << SERVER_CONF
# Базовая конфигурация
port $OPENVPN_PORT
proto $OPENVPN_PROTOCOL
dev tun

# SSL/TLS
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-crypt ta.key

# Сеть
topology subnet
server $OPENVPN_NETWORK $OPENVPN_NETMASK
ifconfig-pool-persist /var/log/openvpn/ipp.txt

# Маршрутизация
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS $OPENVPN_DNS1"
push "dhcp-option DNS $OPENVPN_DNS2"

# Безопасность
cipher AES-256-GCM
auth SHA256
keepalive 10 120
max-clients 100
user nobody
group nogroup

# Логирование
status /var/log/openvpn/status.log
log-append /var/log/openvpn/server.log
verb 3
mute 20

# Дополнительные опции
persist-key
persist-tun
crl-verify crl.pem
explicit-exit-notify 1
SERVER_CONF

    echo "[INFO] Конфигурация сервера создана"
fi

# Создание первого клиента
if [[ ! -f "$CLIENT_DIR/client1.ovpn" ]]; then
    echo "[INFO] Создание первого клиента 'client1'..."
    cd "$EASYRSA_DIR"

    # Генерация ключа и сертификата клиента
    echo "client1" | ./easyrsa gen-req client1 nopass
    echo "yes" | ./easyrsa sign-req client client1

    # Создание .ovpn файла
    mkdir -p "$CLIENT_DIR"

    cat > "$CLIENT_DIR/client1.ovpn" << CLIENT_CONF
client
dev tun
proto $OPENVPN_PROTOCOL
remote $OPENVPN_SERVER_IP $OPENVPN_PORT
resolv-retry infinite
nobind
user nobody
group nogroup
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
key-direction 1
verb 3

<ca>
$(cat $SERVER_DIR/ca.crt)
</ca>

<cert>
$(cat pki/issued/client1.crt)
</cert>

<key>
$(cat pki/private/client1.key)
</key>

<tls-crypt>
$(cat $SERVER_DIR/ta.key)
</tls-crypt>
CLIENT_CONF

    # Копируем в директорию для экспорта
    cp "$CLIENT_DIR/client1.ovpn" "/client-configs/" 2>/dev/null || true

    echo "[INFO] Клиент 'client1' создан"
fi

# Включение IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Запуск OpenVPN сервера
echo "[INFO] Запуск OpenVPN сервера..."
cd "$SERVER_DIR"
exec openvpn --config server.conf
EOF

    chmod +x "$INSTALL_DIR/entrypoint.sh"
    log "entrypoint.sh создан"
}

create_client_manager() {
    cat > "$INSTALL_DIR/scripts/client-manager.sh" << 'EOF'
#!/bin/bash

# Скрипт управления клиентами OpenVPN
CONTAINER_NAME="openvpn-server"
CLIENT_CONFIG_DIR="/opt/openvpn-docker/client-configs"

usage() {
    echo "Использование: $0 {add|remove|list} [client_name]"
    echo ""
    echo "Команды:"
    echo "  add <name>    - Добавить нового клиента"
    echo "  remove <name> - Удалить клиента"
    echo "  list          - Показать список клиентов"
    echo ""
    echo "Примеры:"
    echo "  $0 add john"
    echo "  $0 remove john"
    echo "  $0 list"
}

add_client() {
    local client_name="$1"

    if [[ -z "$client_name" ]]; then
        echo "Ошибка: Не указано имя клиента"
        usage
        exit 1
    fi

    echo "Добавление клиента: $client_name"

    # Проверяем, что контейнер запущен
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        echo "Ошибка: Контейнер $CONTAINER_NAME не запущен"
        exit 1
    fi

    # Выполняем создание клиента в контейнере
    docker exec "$CONTAINER_NAME" bash -c "
        cd /etc/openvpn/easy-rsa

        # Генерируем ключ и сертификат
        echo '$client_name' | ./easyrsa gen-req '$client_name' nopass
        echo 'yes' | ./easyrsa sign-req client '$client_name'

        # Получаем переменные окружения
        SERVER_IP=\${OPENVPN_SERVER_IP:-localhost}
        PORT=\${OPENVPN_PORT:-1194}
        PROTOCOL=\${OPENVPN_PROTOCOL:-udp}

        # Создаем .ovpn файл
        cat > /etc/openvpn/client/$client_name.ovpn << CLIENT_EOF
client
dev tun
proto \$PROTOCOL
remote \$SERVER_IP \$PORT
resolv-retry infinite
nobind
user nobody
group nogroup
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
key-direction 1
verb 3

<ca>
\$(cat /etc/openvpn/server/ca.crt)
</ca>

<cert>
\$(cat pki/issued/$client_name.crt)
</cert>

<key>
\$(cat pki/private/$client_name.key)
</key>

<tls-crypt>
\$(cat /etc/openvpn/server/ta.key)
</tls-crypt>
CLIENT_EOF

        # Копируем в директорию экспорта
        cp /etc/openvpn/client/$client_name.ovpn /client-configs/
    "

    # Копируем конфигурацию на хост
    docker cp "$CONTAINER_NAME:/client-configs/$client_name.ovpn" "$CLIENT_CONFIG_DIR/"

    echo "Клиент '$client_name' успешно создан"
    echo "Конфигурация сохранена: $CLIENT_CONFIG_DIR/$client_name.ovpn"
}

remove_client() {
    local client_name="$1"

    if [[ -z "$client_name" ]]; then
        echo "Ошибка: Не указано имя клиента"
        usage
        exit 1
    fi

    echo "Удаление клиента: $client_name"

    # Проверяем, что контейнер запущен
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        echo "Ошибка: Контейнер $CONTAINER_NAME не запущен"
        exit 1
    fi

    # Отзываем сертификат в контейнере
    docker exec "$CONTAINER_NAME" bash -c "
        cd /etc/openvpn/easy-rsa
        echo 'yes' | ./easyrsa revoke '$client_name'
        ./easyrsa gen-crl
        cp pki/crl.pem /etc/openvpn/server/
    "

    # Удаляем локальные файлы
    rm -f "$CLIENT_CONFIG_DIR/$client_name.ovpn"

    echo "Клиент '$client_name' успешно удален"
}

list_clients() {
    echo "Список клиентов OpenVPN:"
    echo "========================"

    if [[ ! -d "$CLIENT_CONFIG_DIR" ]]; then
        echo "Директория с конфигурациями клиентов не найдена"
        return
    fi

    local count=0
    for ovpn_file in "$CLIENT_CONFIG_DIR"/*.ovpn; do
        if [[ -f "$ovpn_file" ]]; then
            local client_name=$(basename "$ovpn_file" .ovpn)
            echo "  - $client_name"
            ((count++))
        fi
    done

    if [[ $count -eq 0 ]]; then
        echo "  Клиенты не найдены"
    else
        echo ""
        echo "Всего клиентов: $count"
    fi
}

# Основная логика
case "${1:-}" in
    add)
        add_client "$2"
        ;;
    remove)
        remove_client "$2"
        ;;
    list)
        list_clients
        ;;
    *)
        usage
        exit 1
        ;;
esac
EOF

    chmod +x "$INSTALL_DIR/scripts/client-manager.sh"
    log "client-manager.sh создан"
}

# === РАЗВЕРТЫВАНИЕ ===
deploy_openvpn() {
    log "Развертывание OpenVPN сервера..."

    cd "$INSTALL_DIR"

    # Сборка образа
    log "Сборка Docker образа..."
    docker build -t "$IMAGE_NAME" .

    # Запуск сервисов
    log "Запуск OpenVPN контейнера..."
    docker compose up -d

    # Ожидание запуска
    log "Ожидание запуска сервиса..."
    sleep 15

    # Проверка статуса
    if docker ps | grep -q "$CONTAINER_NAME"; then
        log "OpenVPN сервер успешно запущен"

        # Копируем клиентские конфигурации
        log "Копирование клиентских конфигураций..."
        docker cp "$CONTAINER_NAME:/client-configs/." "$CLIENT_CONFIG_DIR/" 2>/dev/null || true

        return 0
    else
        error "Не удалось запустить OpenVPN сервер"
        log "Логи контейнера:"
        docker logs "$CONTAINER_NAME"
        return 1
    fi
}

create_management_scripts() {
    log "Создание скриптов управления..."

    # Создаем основной скрипт управления
    cat > "/usr/local/bin/openvpn-manager" << EOF
#!/bin/bash
# OpenVPN Docker Manager

INSTALL_DIR="$INSTALL_DIR"
CONTAINER_NAME="$CONTAINER_NAME"

case "\${1:-}" in
    start)
        echo "Запуск OpenVPN сервера..."
        cd "\$INSTALL_DIR"
        docker compose up -d
        ;;
    stop)
        echo "Остановка OpenVPN сервера..."
        cd "\$INSTALL_DIR"
        docker compose down
        ;;
    restart)
        echo "Перезапуск OpenVPN сервера..."
        cd "\$INSTALL_DIR"
        docker compose restart
        ;;
    status)
        echo "Статус OpenVPN сервера:"
        docker ps --filter "name=\$CONTAINER_NAME" --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}"
        ;;
    logs)
        echo "Логи OpenVPN сервера:"
        docker logs -f "\$CONTAINER_NAME"
        ;;
    client)
        shift
        "\$INSTALL_DIR/scripts/client-manager.sh" "\$@"
        ;;
    *)
        echo "OpenVPN Docker Manager"
        echo ""
        echo "Использование: \$0 {start|stop|restart|status|logs|client}"
        echo ""
        echo "Команды сервера:"
        echo "  start    - Запустить OpenVPN сервер"
        echo "  stop     - Остановить OpenVPN сервер"
        echo "  restart  - Перезапустить OpenVPN сервер"
        echo "  status   - Показать статус сервера"
        echo "  logs     - Показать логи сервера"
        echo ""
        echo "Управление клиентами:"
        echo "  client add <name>     - Добавить клиента"
        echo "  client remove <name>  - Удалить клиента"
        echo "  client list           - Список клиентов"
        echo ""
        echo "Примеры:"
        echo "  \$0 start"
        echo "  \$0 client add john"
        echo "  \$0 client list"
        ;;
esac
EOF

    chmod +x "/usr/local/bin/openvpn-manager"
    log "Скрипт управления создан: /usr/local/bin/openvpn-manager"
}

# === ОСНОВНАЯ ФУНКЦИЯ ===
main() {
    local public_ip="$1"

    log "=== Начало установки OpenVPN Docker сервера ==="

    # Проверки
    check_root
    check_os

    # Получение IP адреса
    if [[ -z "$public_ip" ]]; then
        public_ip=$(get_public_ip)
        if [[ -z "$public_ip" ]]; then
            error "Не удалось определить внешний IP адрес"
            echo "Попробуйте указать IP вручную: $0 <IP_ADDRESS>"
            exit 1
        fi
    fi

    log "Внешний IP адрес: $public_ip"

    # Установка зависимостей
    update_system
    install_docker

    # Настройка сети
    configure_firewall

    # Создание проекта
    create_project_structure
    generate_docker_files

    # Обновляем docker-compose.yml с правильным IP
    create_docker_compose "$public_ip"

    # Развертывание
    if deploy_openvpn; then
        create_management_scripts

        log "=== Установка завершена успешно ==="
        log ""
        log "🎉 OpenVPN сервер установлен и запущен!"
        log ""
        log "📍 Установочная директория: $INSTALL_DIR"
        log "📁 Клиентские конфигурации: $CLIENT_CONFIG_DIR"
        log "🔧 Скрипт управления: openvpn-manager"
        log ""
        log "🚀 Быстрый старт:"
        log "  • Проверить статус:    openvpn-manager status"
        log "  • Просмотр логов:      openvpn-manager logs"
        log "  • Добавить клиента:    openvpn-manager client add <name>"
        log "  • Список клиентов:     openvpn-manager client list"
        log ""
        log "📱 Первый клиент 'client1' уже создан:"
        log "     $CLIENT_CONFIG_DIR/client1.ovpn"
        log ""
        log "🌐 Подключение к серверу: $public_ip:1194 (UDP)"

    else
        error "Установка завершилась с ошибками"
        exit 1
    fi
}

# Запуск установки
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi