#!/bin/bash

SERVICE_PASSWORD="{$service.password}"
SERVICE_DOMAIN="{$service.domain}"
CONFIG_PASSWORD="{$config.password}"
CONFIG_USER="{$config.ciuser}"

{literal}
set -euo pipefail

echo "[$(date)] n8n Installation Started"

if [ -n "$SERVICE_DOMAIN" ]; then
    hostnamectl set-hostname "$SERVICE_DOMAIN"
    echo "[$(date)] Hostname set to: $SERVICE_DOMAIN"
fi

PASSWORD_TO_USE=""
if [ -n "$CONFIG_PASSWORD" ] && [ "$CONFIG_PASSWORD" != "{config.password}" ]; then
    PASSWORD_TO_USE="$CONFIG_PASSWORD"
elif [ -n "$SERVICE_PASSWORD" ] && [ "$SERVICE_PASSWORD" != "{service.password}" ]; then
    PASSWORD_TO_USE="$SERVICE_PASSWORD"
fi

if [ -n "$PASSWORD_TO_USE" ]; then
    echo "root:$PASSWORD_TO_USE" | chpasswd > /dev/null 2>&1
    echo "[$(date)] Root password updated"
else
    echo "[$(date)] WARNING: No password configured!"
fi

if [ -n "$CONFIG_USER" ] && [ "$CONFIG_USER" != "{config.ciuser}" ] && [ "$CONFIG_USER" != "root" ]; then
    if [ -n "$PASSWORD_TO_USE" ]; then
        useradd -m -s /bin/bash "$CONFIG_USER" 2>/dev/null || true
        echo "$CONFIG_USER:$PASSWORD_TO_USE" | chpasswd > /dev/null 2>&1
        usermod -aG sudo "$CONFIG_USER"
        echo "[$(date)] Created user: $CONFIG_USER"
    fi
fi


apt-get update
apt-get install -y wget bash curl net-tools

wget -O /etc/profile.d/install.sh  -q  https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/gitea.sh
