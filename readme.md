# OpenVPN Server in Docker

Этот проект поднимает OpenVPN-сервер в контейнере на базе образа [`kylemanna/openvpn`](https://hub.docker.com/r/kylemanna/openvpn).  
Все конфигурации и сертификаты хранятся локально в папке `ovpn-data`.

---

## Установка и запуск сервера

1. Скопируйте скрипт `vpn.sh` на ваш сервер.
2. Укажите в нём ваш статический IP:
- SERVER_IP="255.255.255.255"
3. запустить установку
- sudo bash ./vpn.sh

скрипт:
- проверяет наличие Docker, устанавливает при необходимости;
- создаёт папку ovpn-data для конфигов;
- генерирует сертификаты;
- исправляет настройки компрессии (comp-lzo заменяется на безопасный stub-v2);
- запускает контейнер openvpn-server на порту 1194/udp;
- создаёт первого клиента client1.ovpn.


## Управление клиентами

1. Для управления клиентами используйте скрипт manage-vpn.sh.
2. Добавить клиента
- sudo bash ./manage-vpn.sh add <user_name>
Создаст <user_name>.ovpn, который можно импортировать в OpenVPN Client.

3. Получить конфиг клиента
- sudo bash ./manage-vpn.sh get <user_name>

4. Отозвать клиента
- sudo bash ./manage-vpn.sh revoke <user_name>

Где лежат файлы
- ovpn-data/ — папка с конфигурацией и сертификатами;
- *.ovpn — готовые клиентские конфиги.

## Подключение клиента

- Скопируйте файл <user_name>.ovpn на устройство.
- Импортируйте его в OpenVPN-клиент:
- Windows: OpenVPN GUI
- macOS: Tunnelblick
- Linux: пакет openvpn → openvpn --config <user_name>.ovpn
- iOS / Android: приложение OpenVPN Connect из App Store / Google Play.
- Подключитесь — весь трафик будет идти через ваш VPN.

## Удаление VPN сервера
- docker stop openvpn-server && docker rm openvpn-server
- rm -rf ovpn-data