#!/bin/bash
#
# Hermes Agent one-click wrapper for ModulesGarden Proxmox + WHMCS.
#
# This is a THIN wrapper around the official Hermes installer. Philosophy:
# upstream is the source of truth, we add only what a public-facing VPS
# needs that the official installer doesn't cover — UFW, fail2ban, swap,
# and WHMCS-driven secret pre-seed. Everything else (Python, venv, pip,
# data dirs, systemd unit, gateway install) is delegated to upstream so
# Nous's updates flow through without changes on our side.
#
# Official installer: https://github.com/NousResearch/hermes-agent
# Spec:               docs/superpowers/specs/2026-04-18-hermes-agent-one-click-design.md
#

set -euo pipefail

readonly LOGFILE=/var/log/hermes-install.log
readonly CONFIG_FILE=/root/.hermes-install-config
readonly HERMES_INSTALLER_URL=https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh
readonly ENV_FILE=/root/.hermes/.env

readonly RED=$'\e[31m'
readonly BLU=$'\e[34m'
readonly GRN=$'\e[32m'
readonly YEL=$'\e[33m'
readonly DEF=$'\e[0m'

log()     { printf '%s[%s] %s%s\n' "$BLU" "$(date -u +%FT%TZ)" "$*" "$DEF"; }
log_ok()  { printf '%s[%s] %s%s\n' "$GRN" "$(date -u +%FT%TZ)" "$*" "$DEF"; }
log_err() { printf '%s[%s] %s%s\n' "$RED" "$(date -u +%FT%TZ)" "$*" "$DEF" >&2; }

touch "$LOGFILE"
chmod 600 "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

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
# VPS baseline — the three things the official installer does not do
# ---------------------------------------------------------------------------
configure_firewall() {
    log "Installing UFW + fail2ban"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get -qqy install ufw fail2ban curl >/dev/null

    log "Enabling UFW (SSH only)"
    ufw default deny incoming  >/dev/null
    ufw default allow outgoing >/dev/null
    ufw allow ssh              >/dev/null
    ufw --force enable         >/dev/null

    log "Enabling fail2ban (SSH 3-retry -> 24h ban)"
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
    systemctl enable --now fail2ban >/dev/null
}

ensure_swap() {
    # Hermes's pip install peaks around 1 GB RAM; small VPS OOM without swap
    if [ -f /swapfile ]; then
        return 0
    fi
    log "Creating 2 GB swap file"
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
}

# ---------------------------------------------------------------------------
# Pre-seed ~/.hermes/.env with whatever the customer supplied on the WHMCS
# order form. The official installer creates this file itself if missing,
# but preserves existing values. Writing it first means the installer's
# post-install gateway setup can find our keys/tokens and finish the job.
# ---------------------------------------------------------------------------
seed_env() {
    install -d -m 0700 /root/.hermes
    touch "$ENV_FILE"
    chmod 600 "$ENV_FILE"

    {
        printf '# Hermes Agent environment (pre-seeded from WHMCS order)\n\n'
        case "$LLM_PROVIDER" in
            openrouter) [ -n "$LLM_API_KEY" ] && printf 'OPENROUTER_API_KEY=%s\n' "$LLM_API_KEY" ;;
            openai)     [ -n "$LLM_API_KEY" ] && printf 'OPENAI_API_KEY=%s\n'     "$LLM_API_KEY" ;;
            anthropic)  [ -n "$LLM_API_KEY" ] && printf 'ANTHROPIC_API_KEY=%s\n'  "$LLM_API_KEY" ;;
        esac
        [ -n "$TELEGRAM_BOT_TOKEN" ] && printf 'TELEGRAM_BOT_TOKEN=%s\n' "$TELEGRAM_BOT_TOKEN"
    } > "$ENV_FILE"
}

# ---------------------------------------------------------------------------
# Hand off to the OFFICIAL installer. --skip-setup suppresses the interactive
# wizard; everything else (Python, venv, pip, symlink, data dirs, systemd
# unit, optional gateway install) is upstream's job.
# ---------------------------------------------------------------------------
run_official_installer() {
    log "Running official Hermes installer (takes ~3-5 minutes)"
    if ! curl -fsSL "$HERMES_INSTALLER_URL" | bash -s -- --skip-setup; then
        log_err "Official installer failed; see $LOGFILE"
        exit 1
    fi
    log_ok "Official installer finished"
}

# ---------------------------------------------------------------------------
# README
# ---------------------------------------------------------------------------
write_readme() {
    local ip hermes_bin version next_steps=""
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    hermes_bin="$HOME/.local/bin/hermes"
    [ -x "$hermes_bin" ] || hermes_bin=hermes
    version=$("$hermes_bin" version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9a-z.-]+' | head -1)
    [ -z "$version" ] && version="v0.10.x"

    if [ -z "$LLM_API_KEY" ]; then
        next_steps+="
  - Configure an LLM provider (API key or subscription login):
      hermes model
"
    fi
    if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
        next_steps+="
  - Add a messaging platform (Telegram, Discord, Slack, WhatsApp, Signal):
      hermes gateway setup
"
    fi
    [ -z "$next_steps" ] && next_steps="
  (none — everything pre-configured)
"

    cat > /root/README.txt <<README
Hermes Agent — Self-Hosted Personal AI Agent
=============================================

Version:   ${version}
Server IP: ${ip:-unknown}

GETTING STARTED
===============
    source ~/.bashrc            # reload PATH (first login only)
    hermes                      # interactive CLI
    hermes doctor               # diagnostics
    hermes model                # LLM provider
    hermes gateway setup        # messaging platforms
    hermes pairing list         # DM pairing codes (for unknown users)
    hermes update               # update to latest
    hermes auth login nous      # subscription login (alternative to API key)
    hermes auth login openai-codex   # ChatGPT Plus/Pro login (needs codex CLI)

PATHS
=====
    /root/.hermes/.env          # secrets (0600)
    /root/.hermes/config.yaml   # settings (created by 'hermes setup' if missing)
    journalctl --user -u hermes-gateway -f   # service logs (once gateway is set up)

SECURITY (VPS baseline)
=======================
    ufw status
    fail2ban-client status sshd
    # Hermes's own in-product security (dangerous-command approval, DM
    # pairing, SSRF blocks, credential redaction) is active by default.

NEXT STEPS
==========${next_steps}

RESOURCES
=========
    Docs:    https://hermes-agent.nousresearch.com/
    GitHub:  https://github.com/NousResearch/hermes-agent
    License: MIT

Installed: $(date -u +%FT%TZ)
README
    chmod 0644 /root/README.txt
}

cleanup() {
    if [ -f "$CONFIG_FILE" ]; then
        shred -u "$CONFIG_FILE" 2>/dev/null || rm -f "$CONFIG_FILE"
    fi
}

print_banner() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    printf '\n%s========================================================================%s\n' "$GRN" "$DEF"
    printf   '%s            HERMES AGENT INSTALLATION COMPLETE                          %s\n' "$GRN" "$DEF"
    printf   '%s========================================================================%s\n\n' "$GRN" "$DEF"
    printf '  %sServer IP:%s   %s\n'   "$YEL" "$DEF" "${ip:-unknown}"
    printf '  %sREADME:%s      /root/README.txt\n' "$YEL" "$DEF"
    printf '  %sInstall log:%s %s\n\n' "$YEL" "$DEF" "$LOGFILE"
    printf '  %sNext:%s        source ~/.bashrc && hermes\n\n' "$YEL" "$DEF"
    printf '%s========================================================================%s\n\n' "$GRN" "$DEF"
}

# ===========================================================================
# Main
# ===========================================================================

configure_firewall
ensure_swap
seed_env
run_official_installer
write_readme
cleanup
print_banner
log_ok "=== Install complete ==="
