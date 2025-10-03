#!/bin/bash

# OpenVPN Client Manager
# Скрипт для управления клиентами OpenVPN в Docker контейнере

set -e

# Конфигурация
CONTAINER_NAME="openvpn-server"
INSTALL_DIR="/opt/openvpn-docker"
CLIENT_CONFIG_DIR="$INSTALL_DIR/client-configs"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функции логирования
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
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

# Проверка, что контейнер запущен
check_container() {
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        error "Контейнер '$CONTAINER_NAME' не запущен"
        echo "Запустите сервер командой: openvpn-manager start"
        exit 1
    fi
}

# Проверка существования клиента
client_exists() {
    local client_name="$1"
    docker exec "$CONTAINER_NAME" test -f "/etc/openvpn/easy-rsa/pki/issued/$client_name.crt"
}

# Валидация имени клиента
validate_client_name() {
    local client_name="$1"

    if [[ -z "$client_name" ]]; then
        error "Не указано имя клиента"
        return 1
    fi

    # Проверка на допустимые символы (только буквы, цифры, дефис, подчеркивание)
    if [[ ! "$client_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Недопустимое имя клиента: '$client_name'"
        echo "Имя должно содержать только буквы, цифры, дефис и подчеркивание"
        return 1
    fi

    # Проверка длины
    if [[ ${#client_name} -lt 2 || ${#client_name} -gt 32 ]]; then
        error "Имя клиента должно быть от 2 до 32 символов"
        return 1
    fi

    return 0
}

# Добавление нового клиента
add_client() {
    local client_name="$1"

    # Валидация
    if ! validate_client_name "$client_name"; then
        return 1
    fi

    # Проверка контейнера
    check_container

    # Проверка, что клиент не существует
    if client_exists "$client_name"; then
        warning "Клиент '$client_name' уже существует"
        return 1
    fi

    log "Создание клиента '$client_name'..."

    # Создание клиента в контейнере
    docker exec "$CONTAINER_NAME" bash -c "
        set -e
        cd /etc/openvpn/easy-rsa

        # Получаем переменные окружения
        SERVER_IP=\${OPENVPN_SERVER_IP:-localhost}
        PORT=\${OPENVPN_PORT:-1194}
        PROTOCOL=\${OPENVPN_PROTOCOL:-udp}
        DNS1=\${OPENVPN_DNS1:-1.1.1.1}
        DNS2=\${OPENVPN_DNS2:-1.0.0.1}

        # Генерируем ключ и сертификат клиента
        echo '$client_name' | ./easyrsa gen-req '$client_name' nopass
        echo 'yes' | ./easyrsa sign-req client '$client_name'

        # Создаем .ovpn файл
        cat > /etc/openvpn/client/$client_name.ovpn << CLIENT_EOF
# OpenVPN Client Configuration
# Client: $client_name
# Generated: \$(date)

client
dev tun
proto \$PROTOCOL
remote \$SERVER_IP \$PORT
resolv-retry infinite
nobind

# Привилегии
user nobody
group nogroup

# Постоянные настройки
persist-key
persist-tun

# Безопасность
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
key-direction 1
tls-version-min 1.2

# Логирование
verb 3
mute 20

# Дополнительные настройки
connect-retry-max 5
connect-timeout 10

# Сжатие
comp-lzo adaptive

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

        echo '[INFO] Клиент $client_name создан в контейнере'
    " || {
        error "Не удалось создать клиента в контейнере"
        return 1
    }

    # Создаем директорию для клиентских конфигураций если её нет
    mkdir -p "$CLIENT_CONFIG_DIR"

    # Копируем конфигурацию на хост
    if docker cp "$CONTAINER_NAME:/client-configs/$client_name.ovpn" "$CLIENT_CONFIG_DIR/"; then
        log "Клиент '$client_name' успешно создан"
        log "Конфигурация сохранена: $CLIENT_CONFIG_DIR/$client_name.ovpn"

        # Показываем информацию о файле
        local file_size=$(stat -f%z "$CLIENT_CONFIG_DIR/$client_name.ovpn" 2>/dev/null || stat -c%s "$CLIENT_CONFIG_DIR/$client_name.ovpn" 2>/dev/null || echo "неизвестно")
        info "Размер файла: $file_size байт"

        # Показываем путь для скачивания
        echo ""
        info "Для скачивания конфигурации используйте:"
        echo "  scp root@YOUR_SERVER_IP:$CLIENT_CONFIG_DIR/$client_name.ovpn ."
        echo ""
        info "Или просмотрите содержимое:"
        echo "  cat $CLIENT_CONFIG_DIR/$client_name.ovpn"

        return 0
    else
        error "Не удалось скопировать конфигурацию клиента на хост"
        return 1
    fi
}

# Удаление клиента
remove_client() {
    local client_name="$1"

    # Валидация
    if ! validate_client_name "$client_name"; then
        return 1
    fi

    # Проверка контейнера
    check_container

    # Проверка, что клиент существует
    if ! client_exists "$client_name"; then
        warning "Клиент '$client_name' не найден"
        return 1
    fi

    # Подтверждение удаления
    echo -n "Вы действительно хотите удалить клиента '$client_name'? (y/N): "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "Отмена удаления"
        return 0
    fi

    log "Удаление клиента '$client_name'..."

    # Отзыв сертификата в контейнере
    docker exec "$CONTAINER_NAME" bash -c "
        set -e
        cd /etc/openvpn/easy-rsa

        # Отзываем сертификат
        echo 'yes' | ./easyrsa revoke '$client_name'

        # Обновляем CRL
        ./easyrsa gen-crl

        # Копируем обновленный CRL в директорию сервера
        cp pki/crl.pem /etc/openvpn/server/

        # Удаляем файлы клиента
        rm -f /etc/openvpn/client/$client_name.ovpn
        rm -f /client-configs/$client_name.ovpn

        echo '[INFO] Клиент $client_name удален из контейнера'
    " || {
        error "Не удалось удалить клиента в контейнере"
        return 1
    }

    # Удаляем локальную конфигурацию
    rm -f "$CLIENT_CONFIG_DIR/$client_name.ovpn"

    log "Клиент '$client_name' успешно удален"
    info "Сертификат отозван, CRL обновлен"

    return 0
}

# Список клиентов
list_clients() {
    check_container

    log "Получение списка клиентов..."

    # Получаем список клиентов из контейнера
    local clients_info
    clients_info=$(docker exec "$CONTAINER_NAME" bash -c "
        cd /etc/openvpn/easy-rsa

        echo '=== АКТИВНЫЕ КЛИЕНТЫ ==='
        if ls pki/issued/*.crt 2>/dev/null | grep -v server.crt; then
            for cert in pki/issued/*.crt; do
                if [[ \$(basename \"\$cert\") != 'server.crt' ]]; then
                    client_name=\$(basename \"\$cert\" .crt)

                    # Проверяем, отозван ли сертификат
                    if openssl crl -in pki/crl.pem -noout -text 2>/dev/null | grep -q \"\$client_name\"; then
                        echo \"  \$client_name (ОТОЗВАН)\"
                    else
                        echo \"  \$client_name (активен)\"

                        # Показываем срок действия
                        expiry=\$(openssl x509 -in \"\$cert\" -noout -enddate | cut -d= -f2)
                        echo \"    Истекает: \$expiry\"

                        # Проверяем наличие .ovpn файла
                        if [[ -f \"/etc/openvpn/client/\$client_name.ovpn\" ]]; then
                            echo \"    Конфигурация: доступна\"
                        else
                            echo \"    Конфигурация: отсутствует\"
                        fi
                    fi
                    echo
                fi
            done
        else
            echo '  Клиенты не найдены'
        fi

        echo '=== СТАТИСТИКА ==='
        echo \"Всего сертификатов: \$(ls pki/issued/*.crt 2>/dev/null | wc -l)\"
        echo \"Клиентских сертификатов: \$(ls pki/issued/*.crt 2>/dev/null | grep -v server.crt | wc -l)\"

        if [[ -f pki/crl.pem ]]; then
            revoked_count=\$(openssl crl -in pki/crl.pem -noout -text 2>/dev/null | grep -c 'Serial Number:' || echo 0)
            echo \"Отозванных сертификатов: \$revoked_count\"
        fi
    ")

    echo "$clients_info"

    # Показываем локальные конфигурации
    echo ""
    echo "=== ЛОКАЛЬНЫЕ КОНФИГУРАЦИИ ==="
    if [[ -d "$CLIENT_CONFIG_DIR" ]] && ls "$CLIENT_CONFIG_DIR"/*.ovpn >/dev/null 2>&1; then
        for ovpn_file in "$CLIENT_CONFIG_DIR"/*.ovpn; do
            local client_name=$(basename "$ovpn_file" .ovpn)
            local file_size=$(stat -f%z "$ovpn_file" 2>/dev/null || stat -c%s "$ovpn_file" 2>/dev/null || echo "неизвестно")
            local file_date=$(stat -f%Sm -t "%Y-%m-%d %H:%M" "$ovpn_file" 2>/dev/null || stat -c%y "$ovpn_file" 2>/dev/null | cut -d'.' -f1 || echo "неизвестно")

            echo "  $client_name.ovpn"
            echo "    Размер: $file_size байт"
            echo "    Изменен: $file_date"
            echo "    Путь: $ovpn_file"
            echo
        done
    else
        echo "  Локальные конфигурации не найдены"
        echo "  Директория: $CLIENT_CONFIG_DIR"
    fi
}

# Показ информации о клиенте
show_client_info() {
    local client_name="$1"

    if ! validate_client_name "$client_name"; then
        return 1
    fi

    check_container

    if ! client_exists "$client_name"; then
        error "Клиент '$client_name' не найден"
        return 1
    fi

    log "Информация о клиенте '$client_name':"

    docker exec "$CONTAINER_NAME" bash -c "
        cd /etc/openvpn/easy-rsa

        echo '=== СЕРТИФИКАТ ==='
        if [[ -f pki/issued/$client_name.crt ]]; then
            echo 'Сертификат: существует'

            # Информация о сертификате
            openssl x509 -in pki/issued/$client_name.crt -noout -subject -issuer -startdate -enddate

            # Проверка отзыва
            if openssl crl -in pki/crl.pem -noout -text 2>/dev/null | grep -q '$client_name'; then
                echo 'Статус: ОТОЗВАН'
            else
                echo 'Статус: активен'
            fi
        else
            echo 'Сертификат: не найден'
        fi

        echo
        echo '=== КОНФИГУРАЦИЯ ==='
        if [[ -f /etc/openvpn/client/$client_name.ovpn ]]; then
            echo 'Конфигурация OpenVPN: существует'
            echo \"Размер: \$(wc -c < /etc/openvpn/client/$client_name.ovpn) байт\"
        else
            echo 'Конфигурация OpenVPN: не найдена'
        fi
    "

    # Локальная информация
    echo ""
    echo "=== ЛОКАЛЬНАЯ КОПИЯ ==="
    if [[ -f "$CLIENT_CONFIG_DIR/$client_name.ovpn" ]]; then
        echo "Локальная конфигурация: существует"
        echo "Путь: $CLIENT_CONFIG_DIR/$client_name.ovpn"
        local file_size=$(stat -f%z "$CLIENT_CONFIG_DIR/$client_name.ovpn" 2>/dev/null || stat -c%s "$CLIENT_CONFIG_DIR/$client_name.ovpn" 2>/dev/null || echo "неизвестно")
        echo "Размер: $file_size байт"
    else
        echo "Локальная конфигурация: отсутствует"
    fi
}

# Экспорт конфигурации клиента
export_client() {
    local client_name="$1"
    local output_path="$2"

    if ! validate_client_name "$client_name"; then
        return 1
    fi

    check_container

    if ! client_exists "$client_name"; then
        error "Клиент '$client_name' не найден"
        return 1
    fi

    # Определяем путь вывода
    if [[ -z "$output_path" ]]; then
        output_path="./$client_name.ovpn"
    fi

    log "Экспорт конфигурации клиента '$client_name' в '$output_path'..."

    # Копируем из локальной директории если файл существует
    if [[ -f "$CLIENT_CONFIG_DIR/$client_name.ovpn" ]]; then
        cp "$CLIENT_CONFIG_DIR/$client_name.ovpn" "$output_path"
        log "Конфигурация экспортирована: $output_path"
    else
        # Копируем из контейнера
        if docker cp "$CONTAINER_NAME:/etc/openvpn/client/$client_name.ovpn" "$output_path"; then
            log "Конфигурация экспортирована из контейнера: $output_path"
        else
            error "Не удалось экспортировать конфигурацию"
            return 1
        fi
    fi

    # Показываем информацию о файле
    local file_size=$(stat -f%z "$output_path" 2>/dev/null || stat -c%s "$output_path" 2>/dev/null || echo "неизвестно")
    info "Размер файла: $file_size байт"
}

# Функция помощи
usage() {
    echo "OpenVPN Client Manager"
    echo ""
    echo "Использование: $0 <команда> [параметры]"
    echo ""
    echo "Команды:"
    echo "  add <name>              - Добавить нового клиента"
    echo "  remove <name>           - Удалить клиента"
    echo "  list                    - Показать список клиентов"
    echo "  info <name>             - Показать информацию о клиенте"
    echo "  export <name> [path]    - Экспортировать конфигурацию клиента"
    echo ""
    echo "Примеры:"
    echo "  $0 add john             - Создать клиента 'john'"
    echo "  $0 remove john          - Удалить клиента 'john'"
    echo "  $0 list                 - Показать всех клиентов"
    echo "  $0 info john            - Информация о клиенте 'john'"
    echo "  $0 export john          - Экспорт в ./john.ovpn"
    echo "  $0 export john john.ovpn - Экспорт в john.ovpn"
    echo ""
    echo "Примечания:"
    echo "  • Имя клиента может содержать только буквы, цифры, дефис и подчеркивание"
    echo "  • Длина имени от 2 до 32 символов"
    echo "  • Конфигурации сохраняются в $CLIENT_CONFIG_DIR/"
}

# Основная логика
main() {
    case "${1:-}" in
        add)
            add_client "$2"
            ;;
        remove|delete|del)
            remove_client "$2"
            ;;
        list|ls)
            list_clients
            ;;
        info|show)
            show_client_info "$2"
            ;;
        export)
            export_client "$2" "$3"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            error "Неизвестная команда: ${1:-}"
            echo ""
            usage
            exit 1
            ;;
    esac
}

# Запуск
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi