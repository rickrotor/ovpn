# OpenVPN Server in Docker

Этот проект поднимает OpenVPN-сервер в контейнере на базе образа [`kylemanna/openvpn`](https://hub.docker.com/r/kylemanna/openvpn).  
Все конфигурации и сертификаты хранятся локально в папке `ovpn-data`.

---

## Установка и запуск сервера

1. Скопируйте скрипт `setup_openvpn.sh` на ваш сервер.
2. Укажите в нём ваш статический IP:
- SERVER_IP="123.45.67.89"
3. Сделайте скрипт исполняемым:
- chmod +x setup_openvpn.sh
4. запустить установку
- ./vpn.sh

скрипт:
- проверяет наличие Docker, устанавливает при необходимости;
- создаёт папку ovpn-data для конфигов;
- генерирует сертификаты;
- исправляет настройки компрессии (comp-lzo заменяется на безопасный stub-v2);
- запускает контейнер openvpn-server на порту 1194/udp;
- создаёт первого клиента client1.ovpn.


## Управление клиентами

1. Для управления клиентами используйте скрипт manage_openvpn.sh.
2. Сделайте его исполняемым:
- chmod +x manage_openvpn.sh

3. Добавить клиента
- ./manage_openvpn.sh add user1
Создаст user1.ovpn, который можно импортировать в OpenVPN Client.

4. Получить конфиг клиента
- ./manage_openvpn.sh get user1

5. Отозвать клиента
- ./manage_openvpn.sh revoke user1

Где лежат файлы
- ovpn-data/ — папка с конфигурацией и сертификатами;
- *.ovpn — готовые клиентские конфиги.

## Подключение клиента

- Скопируйте файл user1.ovpn на устройство.
- Импортируйте его в OpenVPN-клиент:
- Windows: OpenVPN GUI
- macOS: Tunnelblick
- Linux: пакет openvpn → openvpn --config user1.ovpn
- iOS / Android: приложение OpenVPN Connect из App Store / Google Play.
- Подключитесь — весь трафик будет идти через ваш VPN.

## Удаление VPN сервера
- docker stop openvpn-server && docker rm openvpn-server
- rm -rf ovpn-data