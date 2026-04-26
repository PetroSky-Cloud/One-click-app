#!/bin/bash

# Idempotency gate: cloud-init can re-run user-data on reboot. Skip bootstrap
# only when the completed-install marker is backed by a real Hermes install.
# This avoids a stale marker in a template preventing the first-login trigger.
if [ -f /var/lib/hermes-one-click.done ]; then
    if id hermes >/dev/null 2>&1 && { [ -x /usr/local/bin/hermes ] || [ -x /home/hermes/.local/bin/hermes ]; }; then
        exit 0
    fi
    echo "[init] Stale Hermes done marker found without installed Hermes; continuing bootstrap"
    rm -f /var/lib/hermes-one-click.done
fi

apt-get update
apt-get install -y wget bash curl net-tools

# Download the main wrapper to a private path. We do NOT put it directly in
# /etc/profile.d/ because profile.d files are *sourced* by bash at login, and
# a sourced script's `set -euo pipefail` leaks into the interactive shell
# (causing later errors like "debian_chroot: unbound variable"). Instead, we
# write a tiny stub to profile.d that runs the wrapper as a subprocess.
#
# Retry up to 3x with backoff: at early cloud-init boot the network or
# github.com DNS can be flaky, and wget -q hides the failure (leaving a
# 0-byte file that then "runs" as a no-op — the most confusing failure mode).
WRAPPER_URL=https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/hermes-agent.sh
for attempt in 1 2 3; do
    wget -O /root/hermes-agent.sh "$WRAPPER_URL" && [ -s /root/hermes-agent.sh ] && break
    echo "[init] wget attempt $attempt failed; retrying in 5s"
    sleep 5
done
if [ ! -s /root/hermes-agent.sh ]; then
    echo "[init] FATAL: could not download $WRAPPER_URL" >&2
    exit 1
fi
chmod +x /root/hermes-agent.sh

cat > /etc/profile.d/install.sh <<'STUB'
# Hermes Agent first-boot stub. Runs the installer in a subshell so its
# strict-mode options don't contaminate the interactive login shell, then
# removes itself so subsequent logins are normal.
[ "$(id -u)" -eq 0 ] || return 0 2>/dev/null || exit 0

# Only real interactive root sessions should consume this one-shot trigger.
# Non-interactive platform checks such as `ssh root@host command` or
# `bash -lc ...` may source /etc/profile; they must not silently start or
# consume the installer before the customer enters the VPS.
case $- in
    *i*) ;;
    *) return 0 2>/dev/null || exit 0 ;;
esac
[ -t 0 ] || return 0 2>/dev/null || exit 0

if [ -x /root/hermes-agent.sh ]; then
    if bash /root/hermes-agent.sh; then
        rm -f /etc/profile.d/install.sh
    else
        echo "Hermes Agent installer failed. See /var/log/hermes-install.log, then open a new root shell to retry." >&2
    fi
fi
STUB
chmod +x /etc/profile.d/install.sh

SERVICE_PASSWORD="{$service.password}"
SERVICE_DOMAIN="{$service.domain}"
CONFIG_PASSWORD="{$config.password}"
CONFIG_USER="{$config.ciuser}"

LLM_PROVIDER="{$params.customfields.llm_provider}"
LLM_API_KEY="{$params.customfields.llm_api_key}"
TELEGRAM_BOT_TOKEN="{$params.customfields.telegram_bot_token}"
SSH_KEYS="{$params.customfields.sshkeys}"

{literal}
set -euo pipefail
exec > >(tee -a /var/log/hermes-init.log) 2>&1

echo "[$(date)] Hermes Agent bootstrap starting"

# Hostname from service domain (leak guard: no $ in the literal placeholder)
if [ -n "$SERVICE_DOMAIN" ] && [ "$SERVICE_DOMAIN" != "{service.domain}" ]; then
    hostnamectl set-hostname "$SERVICE_DOMAIN"
    echo "[$(date)] Hostname set to $SERVICE_DOMAIN"
fi

# Root password: prefer App Template password, fall back to service password
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

# Optional additional sudo user
if [ -n "$CONFIG_USER" ] && [ "$CONFIG_USER" != "{config.ciuser}" ] && [ "$CONFIG_USER" != "root" ]; then
    if [ -n "$PASSWORD_TO_USE" ]; then
        useradd -m -s /bin/bash "$CONFIG_USER" 2>/dev/null || true
        echo "$CONFIG_USER:$PASSWORD_TO_USE" | chpasswd > /dev/null 2>&1
        usermod -aG sudo "$CONFIG_USER"
        echo "[$(date)] Created sudo user: $CONFIG_USER"
    fi
fi

# SSH key installation (root + optional user)
if [ -n "$SSH_KEYS" ] && [ "$SSH_KEYS" != "{params.customfields.sshkeys}" ]; then
    mkdir -p /root/.ssh
    printf '%s\n' "$SSH_KEYS" >> /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    if [ -n "$CONFIG_USER" ] && id "$CONFIG_USER" >/dev/null 2>&1; then
        mkdir -p "/home/$CONFIG_USER/.ssh"
        printf '%s\n' "$SSH_KEYS" >> "/home/$CONFIG_USER/.ssh/authorized_keys"
        chmod 700 "/home/$CONFIG_USER/.ssh"
        chmod 600 "/home/$CONFIG_USER/.ssh/authorized_keys"
        chown -R "$CONFIG_USER:$CONFIG_USER" "/home/$CONFIG_USER/.ssh"
    fi
    echo "[$(date)] SSH keys installed"
fi

# Normalize leaked Smarty placeholders to empty (Smarty strips $ when the
# variable is undefined, leaving the literal placeholder behind)
[ "$LLM_PROVIDER"       = "{params.customfields.llm_provider}" ]       && LLM_PROVIDER=""
[ "$LLM_API_KEY"        = "{params.customfields.llm_api_key}" ]        && LLM_API_KEY=""
[ "$TELEGRAM_BOT_TOKEN" = "{params.customfields.telegram_bot_token}" ] && TELEGRAM_BOT_TOKEN=""

# Write install config for the main wrapper (consumed, then shredded)
umask 077
cat > /root/.hermes-install-config <<EOF
LLM_PROVIDER=$(printf '%q' "$LLM_PROVIDER")
LLM_API_KEY=$(printf '%q' "$LLM_API_KEY")
TELEGRAM_BOT_TOKEN=$(printf '%q' "$TELEGRAM_BOT_TOKEN")
EOF
chmod 600 /root/.hermes-install-config

echo "[$(date)] Bootstrap complete. Main installer will run on first root login via /etc/profile.d/install.sh stub."
{/literal}
