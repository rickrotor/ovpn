#!/bin/bash
set -e

DATA_DIR="$PWD/ovpn-data"
CONTAINER_IMAGE="kylemanna/openvpn"

usage() {
    echo "Использование:"
    echo "  $0 add CLIENT_NAME        # создать нового клиента"
    echo "  $0 revoke CLIENT_NAME     # отозвать клиента"
    echo "  $0 get CLIENT_NAME        # получить .ovpn профиль"
    echo
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

COMMAND=$1
CLIENT_NAME=$2

case "$COMMAND" in
    add)
        echo "Создаём нового клиента: $CLIENT_NAME ..."
        docker run -v "$DATA_DIR:/etc/openvpn" --rm -it $CONTAINER_IMAGE easyrsa build-client-full $CLIENT_NAME nopass
        docker run -v "$DATA_DIR:/etc/openvpn" --rm $CONTAINER_IMAGE ovpn_getclient $CLIENT_NAME > "${CLIENT_NAME}.ovpn"
        echo "Клиент создан. Конфиг: ${CLIENT_NAME}.ovpn"
        ;;
    get)
        echo "Экспортируем профиль клиента: $CLIENT_NAME ..."
        docker run -v "$DATA_DIR:/etc/openvpn" --rm $CONTAINER_IMAGE ovpn_getclient $CLIENT_NAME > "${CLIENT_NAME}.ovpn"
        echo "Файл сохранён: ${CLIENT_NAME}.ovpn"
        ;;
    revoke)
        echo "Отзываем доступ клиента: $CLIENT_NAME ..."
        docker run -v "$DATA_DIR:/etc/openvpn" --rm -it $CONTAINER_IMAGE easyrsa revoke $CLIENT_NAME
        docker run -v "$DATA_DIR:/etc/openvpn" --rm $CONTAINER_IMAGE ovpn_crl_update
        docker restart openvpn-server
        echo "Клиент $CLIENT_NAME отозван и сервер перезапущен."
        ;;
    *)
        usage
        ;;
esac
