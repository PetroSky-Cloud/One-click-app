#!/bin/bash
#
# Hermes Agent one-click wrapper for ModulesGarden Proxmox + WHMCS.
#
# Thin wrapper around the official installer. We only add what a public VPS
# needs that upstream doesn't: firewall, fail2ban, swap, and WHMCS secret
# pre-seeding. Everything else is the official installer's job.
#
# Official installer: https://github.com/NousResearch/hermes-agent
#

set -e

DONE_MARKER=/var/lib/hermes-one-click.done
CONFIG_FILE=/root/.hermes-install-config
HERMES_INSTALLER_URL=https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh

# Idempotency gate: cloud-init re-runs user-data on every reboot. Skip if
# we already installed, and remove the first-login stub so it doesn't loop.
if [ -f "$DONE_MARKER" ]; then
    rm -f /etc/profile.d/install.sh
    echo "Hermes already installed ($(cat "$DONE_MARKER")), skipping."
    exit 0
fi

# Cloud-init scripts sometimes run with HOME unset. Both our code and the
# Hermes installer rely on $HOME for ~/.local/bin.
export HOME="${HOME:-/root}"

# Load WHMCS values written by init/, and normalize the provider dropdown
# shellcheck disable=SC1090,SC1091
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
LLM_PROVIDER="${LLM_PROVIDER:-}"
LLM_API_KEY="${LLM_API_KEY:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
case "${LLM_PROVIDER,,}" in
    *openrouter*) LLM_PROVIDER=openrouter ;;
    *openai*)     LLM_PROVIDER=openai ;;
    *anthropic*)  LLM_PROVIDER=anthropic ;;
    *)            LLM_PROVIDER= ;;
esac

echo "==> Hermes Agent install starting"

# ---------------------------------------------------------------------------
# 1. Firewall + brute-force protection (Hermes does not do this)
# ---------------------------------------------------------------------------
echo "==> Configuring firewall (UFW + fail2ban)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get -qqy install ufw fail2ban curl >/dev/null
ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null
ufw allow ssh              >/dev/null
ufw --force enable         >/dev/null
cat > /etc/fail2ban/jail.local <<'JAIL'
[sshd]
enabled = true
maxretry = 3
bantime = 24h
JAIL
systemctl enable --now fail2ban >/dev/null

# ---------------------------------------------------------------------------
# 2. Swap (Hermes's pip install peaks near 1 GB RAM; small VPS need headroom)
# ---------------------------------------------------------------------------
if [ ! -f /swapfile ]; then
    echo "==> Adding 2 GB swap file"
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ---------------------------------------------------------------------------
# 3. Pre-seed /root/.hermes/.env from WHMCS order fields. Never overwrite —
#    a customer may have added more secrets after provisioning.
# ---------------------------------------------------------------------------
mkdir -p /root/.hermes
chmod 700 /root/.hermes
if [ ! -s /root/.hermes/.env ]; then
    echo "==> Writing initial configuration (/root/.hermes/.env)"
    {
        case "$LLM_PROVIDER" in
            openrouter) [ -n "$LLM_API_KEY" ] && echo "OPENROUTER_API_KEY=$LLM_API_KEY" ;;
            openai)     [ -n "$LLM_API_KEY" ] && echo "OPENAI_API_KEY=$LLM_API_KEY" ;;
            anthropic)  [ -n "$LLM_API_KEY" ] && echo "ANTHROPIC_API_KEY=$LLM_API_KEY" ;;
        esac
        [ -n "$TELEGRAM_BOT_TOKEN" ] && echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN"
    } > /root/.hermes/.env
    chmod 600 /root/.hermes/.env
fi

# ---------------------------------------------------------------------------
# 4. Hand off to the official Hermes installer
# ---------------------------------------------------------------------------
echo "==> Installing Hermes Agent (this takes about 3-5 minutes)"
curl -fsSL "$HERMES_INSTALLER_URL" | bash -s -- --skip-setup
if [ ! -x "$HOME/.local/bin/hermes" ]; then
    echo "ERROR: Hermes binary not found after installer run." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 5. Weekly auto-update. 'hermes update' only modifies /root/.hermes/hermes-
#    agent/ (code repo); user data (.env, config.yaml, sessions, memories)
#    is untouched, and the gateway service auto-restarts after updating.
# ---------------------------------------------------------------------------
cat > /etc/cron.weekly/hermes-update <<'CRON'
#!/bin/bash
# Weekly Hermes Agent auto-update. Output -> /var/log/hermes-update.log
export HOME=/root
export PATH="/root/.local/bin:$PATH"
LOG=/var/log/hermes-update.log
touch "$LOG"; chmod 600 "$LOG"
{
    echo "=== $(date -u +%FT%TZ) ==="
    command -v hermes >/dev/null && flock -n /var/lock/hermes-update.lock -c 'hermes update'
} >> "$LOG" 2>&1
CRON
chmod 0755 /etc/cron.weekly/hermes-update

# ---------------------------------------------------------------------------
# 6. Dynamic MOTD on login. File-check only (no systemctl --user) so it is
#    fast and doesn't need a live user DBus.
# ---------------------------------------------------------------------------
cat > /etc/update-motd.d/99-hermes <<'MOTD'
#!/bin/bash
HERMES_BIN=/root/.local/bin/hermes
[ -x "$HERMES_BIN" ] || exit 0
version=$("$HERMES_BIN" version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9a-z.-]+' | head -1)
llm=no; grep -qE '^[A-Z_]+API_KEY=..*' /root/.hermes/.env 2>/dev/null && llm=yes
channels=no; grep -qE '^(TELEGRAM|DISCORD|SLACK)_BOT_TOKEN=..*|^WHATSAPP_ENABLED=..*' /root/.hermes/.env 2>/dev/null && channels=yes
gw=absent; { [ -f /root/.config/systemd/user/hermes-gateway.service ] || [ -f /etc/systemd/system/hermes-gateway.service ]; } && gw=installed
printf '\n  Hermes %-10s  LLM: %s   Channels: %s   Gateway: %s\n' "${version:-unknown}" "$llm" "$channels" "$gw"
printf '  Quick: hermes  |  hermes doctor  |  hermes update\n\n'
MOTD
chmod 0755 /etc/update-motd.d/99-hermes

# ---------------------------------------------------------------------------
# 7. README
# ---------------------------------------------------------------------------
cat > /root/README.txt <<'README'
Hermes Agent - Self-Hosted Personal AI Agent
=============================================

GETTING STARTED
===============
    source ~/.bashrc            # reload PATH (first time only)
    hermes setup                # configure LLM + messaging (interactive)
    hermes                      # start chatting

COMMANDS
========
    hermes model                # choose / switch LLM provider
    hermes gateway setup        # add messaging bots (Telegram, Discord, etc.)
    hermes pairing list         # show pending DM pairing codes
    hermes doctor               # diagnostics
    hermes update               # update to latest (runs weekly via cron)

SUBSCRIPTION LOGIN (no API key needed)
======================================
    hermes auth login nous           # Nous Portal subscription
    hermes auth login openai-codex   # ChatGPT Plus/Pro (needs codex CLI)
    hermes auth login google-gemini-cli

PATHS
=====
    /root/.hermes/.env              # secrets (mode 600, safe to edit)
    /root/.hermes/config.yaml       # settings
    /etc/cron.weekly/hermes-update  # weekly auto-update (chmod -x to disable)
    journalctl --user -u hermes-gateway -f   # service logs

SECURITY
========
    ufw status                      # firewall (SSH only)
    fail2ban-client status sshd     # brute-force protection

Hermes's in-product security — dangerous-command approval, DM pairing,
SSRF blocks, credential redaction, Tirith scanning — is active by default.

RESOURCES
=========
    Docs:    https://hermes-agent.nousresearch.com/
    GitHub:  https://github.com/NousResearch/hermes-agent
README
chmod 0644 /root/README.txt

# ---------------------------------------------------------------------------
# 8. Mark done + clean up sensitive bootstrap artefacts
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$DONE_MARKER")"
date -u +%FT%TZ > "$DONE_MARKER"
rm -f /etc/profile.d/install.sh
if [ -f "$CONFIG_FILE" ]; then
    shred -u "$CONFIG_FILE" 2>/dev/null || rm -f "$CONFIG_FILE"
fi

cat <<EOF

==============================================================
  Hermes Agent installation complete.

  Next:    source ~/.bashrc && hermes setup
  README:  /root/README.txt
==============================================================
EOF
