# OpenVPN Docker Server - Полная автоматическая установка

Полностью автоматизированное решение для развертывания OpenVPN сервера в Docker контейнере на чистом Ubuntu сервере.

🚀 **Установка "под ключ"** - один скрипт устанавливает все: Docker, OpenVPN, настройки сети, клиентов.

## ✨ Особенности

- ✅ **Полная автоматизация** - работает на чистом Ubuntu из коробки
- ✅ **Docker контейнеризация** - изолированная и безопасная среда
- ✅ **Автоматическое определение IP** - никаких ручных настроек
- ✅ **Современная криптография** - ECDSA, SHA512, AES-256-GCM
- ✅ **Управление клиентами** - добавление, удаление, экспорт конфигураций
- ✅ **Безопасность** - TLS-Crypt, CRL, современные шифры
- ✅ **Мониторинг** - логи, статус, health checks
- ✅ **Простое управление** - единый скрипт для всех операций

## 📋 Требования

- **ОС**: Ubuntu 18.04+ (протестировано на 20.04, 22.04)
- **Права**: root доступ (sudo)
- **Сеть**: открытый порт 1194/UDP
- **Ресурсы**: минимум 1GB RAM, 2GB свободного места
- **Интернет**: для загрузки Docker и пакетов

## 🚀 Быстрая установка

### 1. Скачивание файлов

```bash
# Скачиваем все необходимые файлы
wget https://raw.githubusercontent.com/your-repo/openvpn-docker/main/install.sh
wget https://raw.githubusercontent.com/your-repo/openvpn-docker/main/Dockerfile
wget https://raw.githubusercontent.com/your-repo/openvpn-docker/main/docker-compose.yml
wget https://raw.githubusercontent.com/your-repo/openvpn-docker/main/entrypoint.sh
wget https://raw.githubusercontent.com/your-repo/openvpn-docker/main/client-manager.sh

chmod +x install.sh entrypoint.sh client-manager.sh
```

### 2. Запуск установки

```bash
# Автоматическое определение IP адреса
sudo ./install.sh

# Или указать IP вручную
sudo ./install.sh 1.2.3.4
```

### 3. Готово! 🎉

После установки у вас будет:
- Запущенный OpenVPN сервер в Docker
- Первый клиент `client1` с готовой конфигурацией
- Скрипт управления `openvpn-manager`
- Все необходимые настройки сети и безопасности

## 📁 Структура файлов

```
/opt/openvpn-docker/          # Основная директория
├── Dockerfile                # Образ Docker с OpenVPN
├── docker-compose.yml        # Конфигурация контейнера
├── entrypoint.sh             # Скрипт инициализации контейнера
├── client-configs/           # Клиентские .ovpn файлы
│   └── client1.ovpn         # Первый клиент
├── scripts/
│   └── client-manager.sh    # Управление клиентами
├── data/                    # PKI сертификаты (Docker volume)
└── logs/                    # Логи сервера (Docker volume)

/usr/local/bin/
└── openvpn-manager          # Основной скрипт управления
```

## 🔧 Управление сервером

### Основные команды

```bash
# Статус сервера
openvpn-manager status

# Запуск/остановка/перезапуск
openvpn-manager start
openvpn-manager stop
openvpn-manager restart

# Просмотр логов
openvpn-manager logs
```

### Управление клиентами

```bash
# Добавить клиента
openvpn-manager client add john

# Удалить клиента
openvpn-manager client remove john

# Список клиентов
openvpn-manager client list

# Информация о клиенте
./client-manager.sh info john

# Экспорт конфигурации
./client-manager.sh export john ./john.ovpn
```

## 👥 Управление клиентами

### Добавление нового клиента

```bash
# Через основной скрипт
openvpn-manager client add alice

# Или напрямую через client-manager
cd /opt/openvpn-docker
./scripts/client-manager.sh add alice
```

**Результат:**
- Создается новый сертификат клиента
- Генерируется .ovpn конфигурация
- Файл сохраняется в `/opt/openvpn-docker/client-configs/alice.ovpn`

### Удаление клиента

```bash
openvpn-manager client remove alice
```

**Что происходит:**
- Сертификат клиента отзывается (добавляется в CRL)
- Обновляется Certificate Revocation List на сервере
- Удаляются файлы конфигурации

### Список всех клиентов

```bash
openvpn-manager client list
```

**Показывает:**
- Активные клиенты
- Отозванные сертификаты
- Сроки действия сертификатов
- Локальные конфигурации

## 📱 Скачивание конфигураций клиентов

### С сервера на локальную машину

```bash
# SCP
scp root@your-server-ip:/opt/openvpn-docker/client-configs/client1.ovpn .

# Или просмотр в терминале
ssh root@your-server-ip "cat /opt/openvpn-docker/client-configs/client1.ovpn"
```

### Прямой экспорт

```bash
# На сервере
cd /opt/openvpn-docker
./scripts/client-manager.sh export client1 ./client1.ovpn
```

## 🖥️ Подключение клиентов

### Windows
1. Скачайте [OpenVPN GUI](https://openvpn.net/community-downloads/)
2. Поместите .ovpn файл в `C:\Program Files\OpenVPN\config\`
3. Запустите OpenVPN GUI и подключитесь

### macOS
1. Установите [Tunnelblick](https://tunnelblick.net/)
2. Дважды щелкните по .ovpn файлу
3. Следуйте инструкциям установки

### Linux
```bash
# Ubuntu/Debian
sudo apt install openvpn
sudo openvpn --config client1.ovpn

# Или как сервис
sudo cp client1.ovpn /etc/openvpn/client/
sudo systemctl start openvpn-client@client1
```

### Android/iOS
1. Установите OpenVPN Connect из App Store/Google Play
2. Импортируйте .ovpn файл через приложение
3. Подключитесь

## 🔍 Мониторинг и диагностика

### Проверка статуса

```bash
# Общий статус
openvpn-manager status

# Docker контейнер
docker ps | grep openvpn-server
docker stats openvpn-server

# Логи в реальном времени
openvpn-manager logs
```

### Активные подключения

```bash
# Статус подключений
docker exec openvpn-server cat /var/log/openvpn/status.log

# Подключенные клиенты
docker exec openvpn-server grep "CLIENT_LIST" /var/log/openvpn/status.log
```

### Сетевая диагностика

```bash
# Проверка портов
ss -ulnp | grep 1194
netstat -ulnp | grep 1194

# Проверка правил iptables
iptables -L -n | grep -A5 -B5 tun
iptables -t nat -L -n | grep MASQUERADE

# IP forwarding
sysctl net.ipv4.ip_forward
```

## 🛠️ Устранение неполадок

### Контейнер не запускается

```bash
# Проверка логов
docker logs openvpn-server

# Проверка конфигурации
docker exec openvpn-server openvpn --config /etc/openvpn/server/server.conf --test-crypto

# Перезапуск
openvpn-manager restart
```

### Клиенты не могут подключиться

```bash
# Проверка доступности порта
telnet YOUR_SERVER_IP 1194

# Проверка UFW/iptables
ufw status
iptables -L -n

# Проверка DNS
nslookup YOUR_SERVER_IP
```

### Нет интернета у клиентов

```bash
# Проверка IP forwarding
sysctl net.ipv4.ip_forward

# Проверка NAT правил
iptables -t nat -L -n | grep MASQUERADE

# Проверка интерфейса
ip route | grep default
```

## 🔐 Безопасность

### Использованные технологии

- **Криптография**: ECDSA ключи, SHA512 хеширование
- **Шифрование**: AES-256-GCM для данных
- **Аутентификация**: TLS-Crypt для дополнительной защиты
- **PKI**: Полная инфраструктура открытых ключей
- **CRL**: Отзыв скомпрометированных сертификатов

### Резервное копирование

```bash
# Создание резервной копии PKI
docker run --rm -v openvpn_data:/data -v $(pwd):/backup ubuntu tar czf /backup/openvpn-pki-backup.tar.gz -C /data .

# Восстановление
docker run --rm -v openvpn_data:/data -v $(pwd):/backup ubuntu tar xzf /backup/openvpn-pki-backup.tar.gz -C /data
```

## 📚 Техническая информация

### Что происходит при установке

1. **Проверка системы** - совместимость ОС, права root
2. **Обновление системы** - apt update/upgrade, установка базовых пакетов
3. **Установка Docker** - официальный репозиторий, последняя версия
4. **Настройка сети** - UFW, iptables, IP forwarding
5. **Создание проекта** - директории, конфигурации, скрипты
6. **Сборка образа** - Docker build с OpenVPN и зависимостями
7. **Запуск контейнера** - Docker Compose с правильными настройками
8. **Инициализация PKI** - CA, сертификаты сервера, TLS-Crypt ключи
9. **Создание первого клиента** - автоматическая генерация client1
10. **Установка скриптов** - openvpn-manager в /usr/local/bin

### Переменные окружения

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `OPENVPN_SERVER_IP` | auto-detect | Внешний IP сервера |
| `OPENVPN_PORT` | 1194 | UDP порт OpenVPN |
| `OPENVPN_PROTOCOL` | udp | Протокол (udp/tcp) |
| `OPENVPN_NETWORK` | 10.8.0.0 | Сеть VPN |
| `OPENVPN_NETMASK` | 255.255.255.0 | Маска сети |
| `OPENVPN_DNS1` | 1.1.1.1 | Первичный DNS |
| `OPENVPN_DNS2` | 1.0.0.1 | Вторичный DNS |

### Docker конфигурация

- **Образ**: Ubuntu 22.04 + OpenVPN + Easy-RSA
- **Привилегии**: NET_ADMIN для управления сетью
- **Устройства**: /dev/net/tun для VPN туннелей
- **Volumes**: Постоянное хранение PKI и логов
- **Health Check**: Автоматическая проверка работоспособности
- **Restart Policy**: Автоматический перезапуск при сбоях

## 🤝 Поддержка

### Файлы для анализа проблем

```bash
# Логи установки
journalctl -u docker
tail -f /var/log/syslog

# Конфигурация Docker
docker inspect openvpn-server
docker logs openvpn-server

# Сетевые настройки
ip route
iptables -L -n
ufw status verbose
```

### Часто задаваемые вопросы

**Q: Как изменить DNS серверы для клиентов?**
A: Отредактируйте переменные `OPENVPN_DNS1` и `OPENVPN_DNS2` в `docker-compose.yml`

**Q: Можно ли использовать TCP вместо UDP?**
A: Да, измените `OPENVPN_PROTOCOL=tcp` и порт в `docker-compose.yml`

**Q: Как добавить статические маршруты?**
A: Добавьте `push "route 192.168.1.0 255.255.255.0"` в конфигурацию сервера

**Q: Как ограничить количество одновременных подключений клиента?**
A: Уберите `duplicate-cn` из конфигурации сервера

## 📜 Лицензия

MIT License - используйте свободно для любых целей.

---

**Создано с ❤️ для быстрого и безопасного развертывания OpenVPN серверов**