FROM ubuntu:22.04

# Метаданные
LABEL maintainer="OpenVPN Docker"
LABEL description="OpenVPN Server in Docker container"
LABEL version="1.0"

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
    vim \
    tree \
    htop \
    iproute2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Создание пользователя openvpn
RUN groupadd -r openvpn && useradd -r -g openvpn openvpn

# Создание директорий
RUN mkdir -p \
    /etc/openvpn/server \
    /etc/openvpn/client \
    /etc/openvpn/easy-rsa \
    /var/log/openvpn \
    /client-configs \
    /dev/net

# Создание устройства tun (если не существует)
RUN [ ! -c /dev/net/tun ] && mkdir -p /dev/net && mknod /dev/net/tun c 10 200 || true
RUN chmod 600 /dev/net/tun 2>/dev/null || true

# Настройка прав доступа
RUN chown -R root:root /etc/openvpn \
    && chown -R openvpn:openvpn /var/log/openvpn \
    && chown -R openvpn:openvpn /client-configs

# Копирование entrypoint скрипта
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Создание символических ссылок для easy-rsa
RUN ln -sf /usr/share/easy-rsa/* /etc/openvpn/easy-rsa/ 2>/dev/null || true

# Настройка переменных окружения для OpenVPN
ENV OPENVPN_SERVER_IP=""
ENV OPENVPN_PORT=1194
ENV OPENVPN_PROTOCOL=udp
ENV OPENVPN_NETWORK=10.8.0.0
ENV OPENVPN_NETMASK=255.255.255.0
ENV OPENVPN_DNS1=1.1.1.1
ENV OPENVPN_DNS2=1.0.0.1

# Открытие портов
EXPOSE 1194/udp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD pgrep openvpn >/dev/null || exit 1

# Volumes для постоянного хранения данных
VOLUME ["/etc/openvpn", "/var/log/openvpn", "/client-configs"]

# Рабочая директория
WORKDIR /etc/openvpn

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Команда по умолчанию
CMD ["openvpn", "--config", "/etc/openvpn/server/server.conf"]