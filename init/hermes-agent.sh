#!/bin/bash

apt-get update
apt-get install -y wget bash curl net-tools

wget -O /etc/profile.d/install.sh -q https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/hermes-agent.sh
chmod +x /etc/profile.d/install.sh

SERVICE_PASSWORD="{$service.password}"
SERVICE_DOMAIN="{$service.domain}"
CONFIG_PASSWORD="{$config.password}"
CONFIG_USER="{$config.ciuser}"
CLIENT_FIRSTNAME="{$client.firstname}"
CLIENT_LASTNAME="{$client.lastname}"
CLIENT_EMAIL="{$client.email}"

LLM_PROVIDER="{$params.customfields.llm_provider}"
LLM_API_KEY="{$params.customfields.llm_api_key}"
TELEGRAM_BOT_TOKEN="{$params.customfields.telegram_bot_token}"
TERMINAL_BACKEND="{$params.customfields.terminal_backend}"
AGENT_NAME="{$params.customfields.agent_name}"
SSH_KEYS="{$params.customfields.sshkeys}"

{literal}
set -euo pipefail
exec > >(tee -a /var/log/hermes-init.log) 2>&1

echo "[$(date)] Hermes Agent bootstrap starting"

if [ -n "$SERVICE_DOMAIN" ] && [ "$SERVICE_DOMAIN" != "{service.domain}" ]; then
    hostnamectl set-hostname "$SERVICE_DOMAIN"
    echo "[$(date)] Hostname set to $SERVICE_DOMAIN"
fi

PASSWORD_TO_USE=""
if [ -n "$CONFIG_PASSWORD" ] && [ "$CONFIG_PASSWORD" != "{config.password}" ]; then
    PASSWORD_TO_USE="$CONFIG_PASSWORD"
elif [ -n "$SERVICE_PASSWORD" ] && [ "$SERVICE_PASSWORD" != "{service.password}" ]; then
    PASSWORD_TO_USE="$SERVICE_PASSWORD"
fi
if [ -n "$PASSWORD_TO_USE" ]; then
    echo "root:$PASSWORD_TO_USE" | chpasswd > /dev/null 2>&1
    echo "[$(date)] Root password set"
fi

if [ -n "$CONFIG_USER" ] && [ "$CONFIG_USER" != "{config.ciuser}" ] && [ "$CONFIG_USER" != "root" ]; then
    if [ -n "$PASSWORD_TO_USE" ]; then
        useradd -m -s /bin/bash "$CONFIG_USER" 2>/dev/null || true
        echo "$CONFIG_USER:$PASSWORD_TO_USE" | chpasswd > /dev/null 2>&1
        usermod -aG sudo "$CONFIG_USER"
        echo "[$(date)] Created sudo user: $CONFIG_USER"
    fi
fi

if [ -n "$SSH_KEYS" ] && [ "$SSH_KEYS" != "{params.customfields.sshkeys}" ]; then
    mkdir -p /root/.ssh
    echo "$SSH_KEYS" >> /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    if [ -n "$CONFIG_USER" ] && id "$CONFIG_USER" >/dev/null 2>&1; then
        mkdir -p "/home/$CONFIG_USER/.ssh"
        echo "$SSH_KEYS" >> "/home/$CONFIG_USER/.ssh/authorized_keys"
        chmod 700 "/home/$CONFIG_USER/.ssh"
        chmod 600 "/home/$CONFIG_USER/.ssh/authorized_keys"
        chown -R "$CONFIG_USER:$CONFIG_USER" "/home/$CONFIG_USER/.ssh"
    fi
    echo "[$(date)] SSH keys installed"
fi

[ "$LLM_PROVIDER"       = "{params.customfields.llm_provider}" ]       && LLM_PROVIDER=""
[ "$LLM_API_KEY"        = "{params.customfields.llm_api_key}" ]        && LLM_API_KEY=""
[ "$TELEGRAM_BOT_TOKEN" = "{params.customfields.telegram_bot_token}" ] && TELEGRAM_BOT_TOKEN=""
[ "$TERMINAL_BACKEND"   = "{params.customfields.terminal_backend}" ]   && TERMINAL_BACKEND=""
[ "$AGENT_NAME"         = "{params.customfields.agent_name}" ]         && AGENT_NAME=""

umask 077
cat > /root/.hermes-install-config <<EOF
LLM_PROVIDER=$(printf '%q' "$LLM_PROVIDER")
LLM_API_KEY=$(printf '%q' "$LLM_API_KEY")
TELEGRAM_BOT_TOKEN=$(printf '%q' "$TELEGRAM_BOT_TOKEN")
TERMINAL_BACKEND=$(printf '%q' "$TERMINAL_BACKEND")
AGENT_NAME=$(printf '%q' "$AGENT_NAME")
CLIENT_FIRSTNAME=$(printf '%q' "$CLIENT_FIRSTNAME")
CLIENT_LASTNAME=$(printf '%q' "$CLIENT_LASTNAME")
CLIENT_EMAIL=$(printf '%q' "$CLIENT_EMAIL")
EOF
chmod 600 /root/.hermes-install-config

echo "[$(date)] Bootstrap complete. Main installer will run on first root login via /etc/profile.d/install.sh"
{/literal}

