#!/bin/bash
#
# Hermes Agent one-click wrapper for ModulesGarden Proxmox + WHMCS.
#
# Thin wrapper around the OFFICIAL Hermes installer. We add only what a
# public-facing VPS needs that the official installer does not:
#   1. UFW firewall (SSH only)
#   2. fail2ban (SSH 3-retry -> 24h ban)
#   3. 2 GB swap (pip install peaks ~1 GB RAM on small VPS)
#   4. Pre-seed /root/.hermes/.env from WHMCS order fields
# Then delegate everything else to upstream.
#

set -e

LOGFILE=/var/log/hermes-install.log
CONFIG_FILE=/root/.hermes-install-config
HERMES_INSTALLER_URL=https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh
ENV_FILE=/root/.hermes/.env

install -d -m 0755 /var/log
touch "$LOGFILE"
chmod 600 "$LOGFILE"

log() {
    printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOGFILE"
}

fail() {
    printf '[%s] ERROR: %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOGFILE" >&2
    exit 1
}

log "=== Hermes Agent install starting ==="

# ---------------------------------------------------------------------------
# Load WHMCS-supplied values (written by init/hermes-agent.sh)
# ---------------------------------------------------------------------------
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
fi
LLM_PROVIDER="${LLM_PROVIDER:-}"
LLM_API_KEY="${LLM_API_KEY:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
case "${LLM_PROVIDER,,}" in
    *openrouter*) LLM_PROVIDER=openrouter ;;
    *openai*)     LLM_PROVIDER=openai ;;
    *anthropic*)  LLM_PROVIDER=anthropic ;;
    *)            LLM_PROVIDER= ;;
esac

# ---------------------------------------------------------------------------
# 1. Firewall (UFW + fail2ban)
# ---------------------------------------------------------------------------
log "apt: installing ufw, fail2ban, curl"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >>"$LOGFILE" 2>&1
apt-get -qqy install ufw fail2ban curl >>"$LOGFILE" 2>&1

log "ufw: deny-in, allow-out, SSH only"
ufw default deny incoming  >>"$LOGFILE" 2>&1 || fail "ufw default deny failed"
ufw default allow outgoing >>"$LOGFILE" 2>&1 || fail "ufw default allow failed"
ufw allow ssh              >>"$LOGFILE" 2>&1 || fail "ufw allow ssh failed"
ufw --force enable         >>"$LOGFILE" 2>&1 || fail "ufw enable failed"

log "fail2ban: jail.local for sshd"
cat > /etc/fail2ban/jail.local <<'JAIL'
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
JAIL
systemctl enable --now fail2ban >>"$LOGFILE" 2>&1 || fail "fail2ban start failed"

# ---------------------------------------------------------------------------
# 2. Swap (only if no swap currently active)
# ---------------------------------------------------------------------------
if swapon --show=NAME --noheadings | grep -q /swapfile; then
    log "swap: /swapfile already active, skipping"
elif [ -f /swapfile ]; then
    log "swap: /swapfile exists but inactive, enabling"
    swapon /swapfile >>"$LOGFILE" 2>&1 || fail "swapon /swapfile failed"
else
    log "swap: creating 2 GB /swapfile"
    fallocate -l 2G /swapfile >>"$LOGFILE" 2>&1 || fail "fallocate failed"
    chmod 600 /swapfile
    mkswap /swapfile >>"$LOGFILE" 2>&1 || fail "mkswap failed"
    swapon /swapfile >>"$LOGFILE" 2>&1 || fail "swapon failed"
    grep -q '^/swapfile ' /etc/fstab || \
        printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
fi
log "swap: done"

# ---------------------------------------------------------------------------
# 3. Pre-seed /root/.hermes/.env with WHMCS-provided secrets
# ---------------------------------------------------------------------------
log "env: pre-seeding /root/.hermes/.env from WHMCS fields"
install -d -m 0700 /root/.hermes
{
    printf '# Hermes Agent environment (pre-seeded from WHMCS order)\n\n'
    case "$LLM_PROVIDER" in
        openrouter) [ -n "$LLM_API_KEY" ] && printf 'OPENROUTER_API_KEY=%s\n' "$LLM_API_KEY" ;;
        openai)     [ -n "$LLM_API_KEY" ] && printf 'OPENAI_API_KEY=%s\n'     "$LLM_API_KEY" ;;
        anthropic)  [ -n "$LLM_API_KEY" ] && printf 'ANTHROPIC_API_KEY=%s\n'  "$LLM_API_KEY" ;;
    esac
    [ -n "$TELEGRAM_BOT_TOKEN" ] && printf 'TELEGRAM_BOT_TOKEN=%s\n' "$TELEGRAM_BOT_TOKEN"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

# ---------------------------------------------------------------------------
# 4. Hand off to the OFFICIAL installer
# ---------------------------------------------------------------------------
log "installer: downloading and executing $HERMES_INSTALLER_URL (takes 3-5 min)"
# Hermes's installer puts uv in ~/.local/bin then immediately expects to find
# uv on PATH. Root's default PATH doesn't include ~/.local/bin, so the
# installer bails with "uv installed but not found on PATH". Prepend it.
export PATH="$HOME/.local/bin:$PATH"
if ! curl -fsSL "$HERMES_INSTALLER_URL" | bash -s -- --skip-setup 2>&1 | tee -a "$LOGFILE"; then
    fail "official Hermes installer failed; see $LOGFILE"
fi
# Verify the installer actually produced a working hermes binary
if [ ! -x /root/.local/bin/hermes ]; then
    fail "hermes binary missing at /root/.local/bin/hermes after installer run"
fi
log "installer: official installer finished (hermes binary present)"

# ---------------------------------------------------------------------------
# 5. README
# ---------------------------------------------------------------------------
log "readme: writing /root/README.txt"
MYIP=$(hostname -I 2>/dev/null | awk '{print $1}')
HERMES_BIN=/root/.local/bin/hermes
[ -x "$HERMES_BIN" ] || HERMES_BIN=hermes
VERSION=$("$HERMES_BIN" version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9a-z.-]+' | head -1 || true)
[ -z "$VERSION" ] && VERSION="v0.10.x"

NEXT_STEPS=""
if [ -z "$LLM_API_KEY" ]; then
    NEXT_STEPS+="
  - Configure an LLM provider (API key or subscription login):
      hermes model
"
fi
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    NEXT_STEPS+="
  - Add a messaging platform (Telegram, Discord, Slack, WhatsApp):
      hermes gateway setup
"
fi
[ -z "$NEXT_STEPS" ] && NEXT_STEPS="
  (none - everything pre-configured)
"

cat > /root/README.txt <<README
Hermes Agent - Self-Hosted Personal AI Agent
=============================================

Version:   ${VERSION}
Server IP: ${MYIP:-unknown}

GETTING STARTED
===============
    source ~/.bashrc            # reload PATH (first login only)
    hermes                      # interactive CLI
    hermes doctor               # diagnostics
    hermes model                # LLM provider
    hermes gateway setup        # messaging platforms
    hermes pairing list         # pending DM pairing codes
    hermes update               # update to latest
    hermes auth login nous      # subscription login (no API key needed)
    hermes auth login openai-codex   # ChatGPT Plus/Pro login (needs codex CLI)

PATHS
=====
    /root/.hermes/.env          # secrets (mode 600)
    /root/.hermes/config.yaml   # settings (written by 'hermes setup')
    journalctl --user -u hermes-gateway -f   # service logs

VPS HARDENING
=============
    ufw status
    fail2ban-client status sshd

Hermes's in-product security (dangerous-command approval, DM pairing,
SSRF blocks, credential redaction, Tirith scanning) is active by default.

NEXT STEPS
==========${NEXT_STEPS}

RESOURCES
=========
    Docs:    https://hermes-agent.nousresearch.com/
    GitHub:  https://github.com/NousResearch/hermes-agent
    License: MIT

Installed: $(date -u +%FT%TZ)
README
chmod 0644 /root/README.txt

# ---------------------------------------------------------------------------
# 6. Cleanup + banner
# ---------------------------------------------------------------------------
if [ -f "$CONFIG_FILE" ]; then
    shred -u "$CONFIG_FILE" 2>/dev/null || rm -f "$CONFIG_FILE"
fi

log "=== Install complete. See /root/README.txt ==="

printf '\n'
printf '========================================================================\n'
printf '            HERMES AGENT INSTALLATION COMPLETE\n'
printf '========================================================================\n\n'
printf '  Server IP:   %s\n'  "${MYIP:-unknown}"
printf '  README:      /root/README.txt\n'
printf '  Install log: %s\n'  "$LOGFILE"
printf '  Next:        source ~/.bashrc && hermes\n\n'
printf '========================================================================\n\n'
