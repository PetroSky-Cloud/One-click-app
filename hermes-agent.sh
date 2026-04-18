#!/bin/bash
#
# Hermes Agent one-click installer for ModulesGarden Proxmox + WHMCS.
#
# Wraps the official Hermes installer (curl | bash) with the minimal additions
# a public-facing VPS needs: firewall, non-root runtime user, pre-seeded
# secrets from WHMCS custom fields, systemd hardening drop-in, and a
# system-scope gateway unit.
#
# Spec: docs/superpowers/specs/2026-04-18-hermes-agent-one-click-design.md
#

# ---------------------------------------------------------------------------
# Guard: /etc/profile.d/install.sh is sourced by EVERY login shell on this
# system, including the one `sudo -iu hermes` spawns later. Without the guard
# plus early removal, the hermes login shell re-sources us as a non-root user,
# fails at the root-only /var/log touch, and the whole sudo call exits
# non-zero before the Hermes installer ever runs.
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
rm -f /etc/profile.d/install.sh 2>/dev/null || true

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly HERMES_USER=hermes
readonly HERMES_GROUP=hermes
readonly HERMES_DATA=/home/${HERMES_USER}/.hermes
readonly HERMES_BIN=/home/${HERMES_USER}/.local/bin/hermes
readonly HERMES_INSTALLER_URL=https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh

readonly LOGFILE=/var/log/hermes-install.log
readonly CONFIG_FILE=/root/.hermes-install-config

readonly SWAP_SIZE=2G
readonly SYSTEMD_DROPIN=/etc/systemd/system/hermes-gateway.service.d/10-hardening.conf

# Env-var names that indicate a messaging channel is configured. Presence of
# any one triggers system-scope gateway install after the drop-in is in place.
readonly CHANNEL_TOKEN_VARS=(
    TELEGRAM_BOT_TOKEN
    DISCORD_BOT_TOKEN
    SLACK_BOT_TOKEN
    SLACK_APP_TOKEN
    WHATSAPP_ENABLED
)

readonly RED=$'\e[31m'
readonly BLU=$'\e[34m'
readonly GRN=$'\e[32m'
readonly YEL=$'\e[33m'
readonly DEF=$'\e[0m'

log_info() { printf '%s[%s] %s%s\n' "$BLU" "$(date -u +%FT%TZ)" "$*" "$DEF"; }
log_ok()   { printf '%s[%s] %s%s\n' "$GRN" "$(date -u +%FT%TZ)" "$*" "$DEF"; }
log_warn() { printf '%s[%s] %s%s\n' "$YEL" "$(date -u +%FT%TZ)" "$*" "$DEF"; }
log_err()  { printf '%s[%s] %s%s\n' "$RED" "$(date -u +%FT%TZ)" "$*" "$DEF" >&2; }

# ---------------------------------------------------------------------------
# Logging setup — capture stdout+stderr to $LOGFILE (mode 600)
# ---------------------------------------------------------------------------
touch "$LOGFILE"
chmod 600 "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

log_info "=== Hermes Agent one-click install starting ==="

# ---------------------------------------------------------------------------
# Load WHMCS-supplied values (written by init/hermes-agent.sh), with empty
# defaults when the wrapper is invoked manually for a re-run.
# ---------------------------------------------------------------------------
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
fi

LLM_PROVIDER="${LLM_PROVIDER:-}"
LLM_API_KEY="${LLM_API_KEY:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"

# Normalize dropdown labels ("OpenRouter (Recommended)") to bash tokens
case "${LLM_PROVIDER,,}" in
    *openrouter*) LLM_PROVIDER=openrouter ;;
    *openai*)     LLM_PROVIDER=openai ;;
    *anthropic*)  LLM_PROVIDER=anthropic ;;
    *)            LLM_PROVIDER= ;;
esac

log_info "config: provider=${LLM_PROVIDER:-none} llm_key=$([ -n "$LLM_API_KEY" ] && echo yes || echo no) tg_token=$([ -n "$TELEGRAM_BOT_TOKEN" ] && echo yes || echo no)"

# ===========================================================================
# Step functions
# ===========================================================================

install_base_packages() {
    log_info "Installing base packages"
    # Mask unattended-upgrades during install to avoid dpkg lock contention
    systemctl stop unattended-upgrades.service 2>/dev/null || true
    systemctl mask unattended-upgrades.service 2>/dev/null || true

    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a

    apt-get update -qq
    apt-get -qqy install \
        curl wget git ca-certificates \
        ufw fail2ban openssl \
        ripgrep ffmpeg \
        build-essential python3-dev libffi-dev >/dev/null

    systemctl unmask unattended-upgrades.service 2>/dev/null || true
}

configure_firewall() {
    log_info "Configuring UFW (SSH only)"
    ufw default deny incoming  >/dev/null
    ufw default allow outgoing >/dev/null
    ufw allow ssh              >/dev/null
    ufw --force enable         >/dev/null
}

configure_fail2ban() {
    log_info "Configuring fail2ban (SSH 3-retry -> 24h ban)"
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
    systemctl enable fail2ban >/dev/null
    systemctl restart fail2ban
}

ensure_swap() {
    if [ -f /swapfile ]; then
        return 0
    fi
    log_info "Creating ${SWAP_SIZE} swap file"
    fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
}

create_hermes_user() {
    if id "$HERMES_USER" >/dev/null 2>&1; then
        return 0
    fi
    log_info "Creating ${HERMES_USER} system user"
    useradd -m -s /bin/bash "$HERMES_USER"
}

# Writes ~/.hermes/.env with ONLY the LLM API key. Channel tokens are
# deliberately held back — see seed_channel_tokens() for rationale.
seed_env_with_llm_key() {
    install -d -m 0700 -o "$HERMES_USER" -g "$HERMES_GROUP" "$HERMES_DATA"

    local env_file="$HERMES_DATA/.env"
    {
        printf '# Hermes Agent environment (one-click installer)\n'
        printf '# Manage with: sudo -iu %s hermes config set KEY value\n\n' "$HERMES_USER"
        case "$LLM_PROVIDER" in
            openrouter) [ -n "$LLM_API_KEY" ] && printf 'OPENROUTER_API_KEY=%s\n' "$LLM_API_KEY" ;;
            openai)     [ -n "$LLM_API_KEY" ] && printf 'OPENAI_API_KEY=%s\n'     "$LLM_API_KEY" ;;
            anthropic)  [ -n "$LLM_API_KEY" ] && printf 'ANTHROPIC_API_KEY=%s\n'  "$LLM_API_KEY" ;;
        esac
    } > "$env_file"
    chown "$HERMES_USER:$HERMES_GROUP" "$env_file"
    chmod 600 "$env_file"
}

seed_config_yaml() {
    local cfg="$HERMES_DATA/config.yaml"
    cat > "$cfg" <<'YAML'
# Hermes Agent config (one-click installer defaults)
approvals:
  mode: manual
  timeout: 60
unauthorized_dm_behavior: pair
YAML
    chown "$HERMES_USER:$HERMES_GROUP" "$cfg"
    chmod 600 "$cfg"
}

# Invokes the OFFICIAL Hermes installer from upstream. This is the source of
# truth for Python/Node/venv/pip/symlink/data-dirs — we don't duplicate it.
run_official_installer() {
    log_info "Running official Hermes installer (takes ~3-5 minutes)"
    if ! sudo -iu "$HERMES_USER" bash -c \
            "curl -fsSL $HERMES_INSTALLER_URL | bash -s -- --skip-setup"; then
        log_err "Official Hermes installer failed; see $LOGFILE"
        exit 1
    fi
    if [ ! -x "$HERMES_BIN" ]; then
        log_err "Hermes binary not at $HERMES_BIN after install"
        exit 1
    fi
    log_ok "Hermes installed"
}

# Writes /etc/systemd/system/hermes-gateway.service.d/10-hardening.conf. Safe
# to place before the parent unit exists — systemd merges drop-ins at unit
# load time. Eight directives chosen for best security-per-line ratio; the
# more exotic ones (MemoryDenyWriteExecute, SystemCallFilter) are omitted
# because they break Python JIT / subprocess spawning.
install_systemd_hardening() {
    log_info "Installing systemd hardening drop-in"
    install -d -m 0755 "$(dirname "$SYSTEMD_DROPIN")"
    cat > "$SYSTEMD_DROPIN" <<DROPIN
[Service]
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=${HERMES_DATA}
ProtectKernelTunables=yes
ProtectKernelModules=yes
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
PrivateTmp=yes
CapabilityBoundingSet=
AmbientCapabilities=
MemoryMax=2G
TasksMax=512
DROPIN
    chmod 0644 "$SYSTEMD_DROPIN"
}

# Appends channel tokens AFTER the official installer has run AND the
# hardening drop-in is in place. Why: if channel tokens are present when the
# official installer runs, it auto-invokes `hermes gateway install` with no
# flags, which creates a user-scope unit at ~/.config/systemd/user/. Our
# drop-in at /etc/systemd/system/.../d/ cannot override user-scope units.
seed_channel_tokens() {
    local env_file="$HERMES_DATA/.env"
    if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
        printf '\nTELEGRAM_BOT_TOKEN=%s\n' "$TELEGRAM_BOT_TOKEN" >> "$env_file"
    fi
    chmod 600 "$env_file"
}

has_channel_token() {
    local env_file="$HERMES_DATA/.env" var
    [ -f "$env_file" ] || return 1
    for var in "${CHANNEL_TOKEN_VARS[@]}"; do
        if grep -qE "^${var}=..*" "$env_file"; then
            return 0
        fi
    done
    return 1
}

# Installs hermes-gateway as a SYSTEM-scope unit running under the hermes uid.
# Run as root (required to write /etc/systemd/system/) with --run-as-user so
# Hermes's "refuse to install as root" guard is satisfied.
install_gateway_system_scope() {
    log_info "Installing hermes-gateway as system-scope service"
    HERMES_HOME="$HERMES_DATA" "$HERMES_BIN" \
        gateway install --system --run-as-user "$HERMES_USER"
    systemctl daemon-reload
    systemctl enable --now hermes-gateway.service
}

detect_public_ip() {
    # Prefer kernel-reported address; avoid external services during install.
    hostname -I 2>/dev/null | awk '{print $1}'
}

detect_hermes_version() {
    sudo -u "$HERMES_USER" "$HERMES_BIN" version 2>/dev/null \
        | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9a-z.-]+' \
        | head -1
}

write_readme() {
    local ip version gateway_state next_steps=""
    ip=$(detect_public_ip)
    version=$(detect_hermes_version)
    [ -z "$version" ] && version="v0.10.x"

    if has_channel_token; then
        gateway_state="active"
    else
        gateway_state="not configured (no channel tokens)"
    fi

    if [ -z "$LLM_API_KEY" ]; then
        next_steps="$next_steps
  - Configure an LLM provider (API key or subscription login):
      sudo -iu ${HERMES_USER} hermes model
"
    fi
    if ! has_channel_token; then
        next_steps="$next_steps
  - Add a messaging platform (Telegram, Discord, Slack, WhatsApp, Signal):
      sudo -iu ${HERMES_USER} hermes gateway setup
"
    fi
    [ -z "$next_steps" ] && next_steps="
  (none — everything is pre-configured)
"

    cat > /root/README.txt <<README
Hermes Agent — Self-Hosted Personal AI Agent
=============================================

Version:         ${version}
Server IP:       ${ip:-unknown}
CLI user:        ${HERMES_USER}  (access: sudo -iu ${HERMES_USER})
Gateway service: ${gateway_state}

COMMANDS
========
    sudo -iu ${HERMES_USER}                      # Switch to the hermes user
    hermes                                       # Start the interactive CLI
    hermes doctor                                # Diagnostics
    hermes model                                 # Configure LLM provider
    hermes gateway setup                         # Add messaging platforms
    hermes pairing list                          # Show DM pairing codes
    hermes update                                # Update to latest

PATHS
=====
    ${HERMES_DATA}/.env                          # Secrets (mode 600)
    ${HERMES_DATA}/config.yaml                   # Settings
    journalctl -u hermes-gateway -f              # Service logs (if gateway active)

SECURITY
========
  - UFW: SSH inbound only, everything else denied
  - fail2ban: 3 SSH retries -> 24h ban
  - Gateway runs as non-root '${HERMES_USER}' user
  - systemd hardening drop-in applied
       (verify: systemd-analyze security hermes-gateway.service)
  - .env is mode 600, owned by ${HERMES_USER}:${HERMES_GROUP}

MESSAGING AUTH
==============
Unknown users get an 8-character DM pairing code. Approve on the CLI:
    sudo -iu ${HERMES_USER} hermes pairing approve telegram ABC12DEF

SUBSCRIPTION LOGIN (alternatives to an API key)
===============================================
    hermes auth login nous                       # Nous Portal subscription
    hermes auth login openai-codex               # ChatGPT Plus/Pro (needs codex CLI)
    hermes auth login google-gemini-cli          # Gemini OAuth

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
    # Wipe the bootstrap config (contained plaintext API keys)
    if [ -f "$CONFIG_FILE" ]; then
        shred -u "$CONFIG_FILE" 2>/dev/null || rm -f "$CONFIG_FILE"
    fi
    # Belt-and-braces — we did this at the top of the script too
    rm -f /etc/profile.d/install.sh
}

print_banner() {
    local ip
    ip=$(detect_public_ip)
    printf '\n%s========================================================================%s\n' "$GRN" "$DEF"
    printf   '%s            HERMES AGENT INSTALLATION COMPLETE                          %s\n' "$GRN" "$DEF"
    printf   '%s========================================================================%s\n\n' "$GRN" "$DEF"
    printf '  %sServer IP:%s   %s\n' "$YEL" "$DEF" "${ip:-unknown}"
    printf '  %sCLI user:%s    %s  (sudo -iu %s)\n' "$YEL" "$DEF" "$HERMES_USER" "$HERMES_USER"
    printf '  %sREADME:%s      /root/README.txt\n' "$YEL" "$DEF"
    printf '  %sInstall log:%s %s\n\n' "$YEL" "$DEF" "$LOGFILE"
    printf '%s========================================================================%s\n\n' "$GRN" "$DEF"
}

# ===========================================================================
# Main
# ===========================================================================

install_base_packages
configure_firewall
configure_fail2ban
ensure_swap
create_hermes_user
seed_env_with_llm_key
seed_config_yaml
run_official_installer
install_systemd_hardening
seed_channel_tokens
if has_channel_token; then
    install_gateway_system_scope
else
    log_warn "No channel tokens — gateway service not installed. Run 'hermes gateway setup' after SSH."
fi
write_readme
cleanup
print_banner
log_ok "=== Hermes Agent install complete ==="
