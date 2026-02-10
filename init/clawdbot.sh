#!/bin/bash

apt-get update
apt-get install -y wget bash curl net-tools ufw fail2ban

wget -O /etc/profile.d/install.sh -q https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/clawdbot.sh
chmod +x /etc/profile.d/install.sh


SERVICE_PASSWORD="{$service.password}"
SERVICE_DOMAIN="{$service.domain}"
CONFIG_PASSWORD="{$config.password}"
CONFIG_USER="{$config.ciuser}"

{literal}
set -euo pipefail

echo "[$(date)] Clawdbot Installation Started"

# Configure UFW firewall
echo "[$(date)] Configuring firewall..."
ufw default deny incoming > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1
ufw allow ssh > /dev/null 2>&1
ufw --force enable > /dev/null 2>&1
echo "[$(date)] UFW firewall enabled (SSH only)"

# Configure fail2ban for SSH brute-force protection
echo "[$(date)] Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << 'EOFFAIL2BAN'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
banaction = ufw

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 24h
EOFFAIL2BAN
systemctl enable fail2ban > /dev/null 2>&1
systemctl restart fail2ban > /dev/null 2>&1
echo "[$(date)] Fail2ban configured (SSH protection)"

if [ -n "$SERVICE_DOMAIN" ] && [ "$SERVICE_DOMAIN" != "{service.domain}" ]; then
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

echo "[$(date)] Security hardening complete"
{/literal}

