#!/bin/bash


apt-get update
apt-get install -y wget bash curl net-tools

# Download installer with retry - a failed wget must not leave a silent 0-byte file
for attempt in 1 2 3; do
    wget -q -O /root/supabase-install.sh https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/supabase.sh && [ -s /root/supabase-install.sh ] && break
    sleep 5
done

# Run the installer only for interactive root logins (not scp or ssh commands)
cat > /etc/profile.d/install.sh <<'STUB'
[ "$(id -u)" -eq 0 ] || return 0 2>/dev/null || exit 0
case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac
[ -t 0 ] || return 0 2>/dev/null || exit 0
[ -s /root/supabase-install.sh ] && bash /root/supabase-install.sh
STUB


SERVICE_PASSWORD="{$service.password}"
SERVICE_DOMAIN="{$service.domain}"
CONFIG_PASSWORD="{$config.password}"
CONFIG_USER="{$config.ciuser}"

{literal}
set -euo pipefail

echo "[$(date)] Supabase Installation Started"

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
{/literal}
