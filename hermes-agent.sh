#!/bin/bash
#
# Hermes Agent one-click wrapper for ModulesGarden Proxmox + WHMCS.
#
# This remains a thin wrapper around the official Nous Research installer.
# Root only provisions the VPS. Hermes itself is installed and run as a
# dedicated, non-sudo runtime user.
#
# Official installer: https://github.com/NousResearch/hermes-agent
#

set -Eeuo pipefail

DONE_MARKER="${DONE_MARKER:-/var/lib/hermes-one-click.done}"
CONFIG_FILE="${CONFIG_FILE:-/root/.hermes-install-config}"
HERMES_INSTALLER_URL="${HERMES_INSTALLER_URL:-https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"

HERMES_USER="${HERMES_USER:-hermes}"
HERMES_HOME_DIR_WAS_SET="${HERMES_HOME_DIR+x}"
HERMES_HOME_WAS_SET="${HERMES_HOME+x}"
HERMES_WORKSPACE_WAS_SET="${HERMES_WORKSPACE+x}"
HERMES_BACKUP_DIR_WAS_SET="${HERMES_BACKUP_DIR+x}"

HERMES_HOME_DIR="${HERMES_HOME_DIR:-/home/${HERMES_USER}}"
HERMES_HOME="${HERMES_HOME:-${HERMES_HOME_DIR}/.hermes}"
HERMES_WORKSPACE="${HERMES_WORKSPACE:-${HERMES_HOME_DIR}/workspace}"
HERMES_BACKUP_DIR="${HERMES_BACKUP_DIR:-${HERMES_HOME_DIR}/backups}"
HERMES_BIN="${HERMES_HOME_DIR}/.local/bin/hermes"
HERMES_ENV_FILE="${HERMES_HOME}/.env"
ROOT_WRAPPER="${ROOT_WRAPPER:-/usr/local/bin/hermes}"

LOG_FILE="${LOG_FILE:-/var/log/hermes-install.log}"
DOCTOR_LOG="${DOCTOR_LOG:-/var/log/hermes-doctor.log}"
UPDATE_LOG="${UPDATE_LOG:-/var/log/hermes-update.log}"
BACKUP_LOG="${BACKUP_LOG:-/var/log/hermes-backup.log}"

touch "$LOG_FILE"
chmod 600 "$LOG_FILE" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1

on_error() {
    local rc=$?
    local line="${1:-unknown}"
    echo "ERROR: Hermes one-click install failed at line ${line}. See ${LOG_FILE}." >&2
    exit "$rc"
}

trap 'on_error "$LINENO"' ERR

log() {
    printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"
}

die() {
    log "ERROR: $*"
    exit 1
}

refresh_runtime_paths() {
    local passwd_home
    passwd_home="$(getent passwd "$HERMES_USER" | cut -d: -f6 || true)"

    if [ -z "$HERMES_HOME_DIR_WAS_SET" ] && [ -n "$passwd_home" ]; then
        HERMES_HOME_DIR="$passwd_home"
    fi
    if [ -z "$HERMES_HOME_WAS_SET" ]; then
        HERMES_HOME="${HERMES_HOME_DIR}/.hermes"
    fi
    if [ -z "$HERMES_WORKSPACE_WAS_SET" ]; then
        HERMES_WORKSPACE="${HERMES_HOME_DIR}/workspace"
    fi
    if [ -z "$HERMES_BACKUP_DIR_WAS_SET" ]; then
        HERMES_BACKUP_DIR="${HERMES_HOME_DIR}/backups"
    fi

    HERMES_BIN="${HERMES_HOME_DIR}/.local/bin/hermes"
    HERMES_ENV_FILE="${HERMES_HOME}/.env"
}

runtime_group() {
    id -gn "$HERMES_USER"
}

run_as_hermes() {
    # shellcheck disable=SC2016
    runuser -u "$HERMES_USER" -- env \
        HOME="$HERMES_HOME_DIR" \
        HERMES_HOME="$HERMES_HOME" \
        PATH="${HERMES_HOME_DIR}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        bash -c 'cd "$1"; shift; exec "$@"' bash "$HERMES_HOME_DIR" "$@"
}

validate_runtime_user() {
    if ! [[ "$HERMES_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
        die "Invalid HERMES_USER: ${HERMES_USER}"
    fi
    if [ "$HERMES_USER" = "root" ]; then
        die "Refusing to use root as the Hermes runtime user"
    fi
}

normalize_inputs() {
    LLM_PROVIDER="${LLM_PROVIDER:-}"
    LLM_API_KEY="${LLM_API_KEY:-}"
    TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"

    case "${LLM_PROVIDER,,}" in
        *openrouter*) LLM_PROVIDER=openrouter ;;
        *openai*)     LLM_PROVIDER=openai ;;
        *anthropic*)  LLM_PROVIDER=anthropic ;;
        *)            LLM_PROVIDER= ;;
    esac
}

install_base_packages() {
    log "Installing VPS baseline packages"
    export DEBIAN_FRONTEND=noninteractive

    systemctl stop unattended-upgrades.service 2>/dev/null || true
    apt-get update -qq
    apt-get -qqy install \
        bash ca-certificates curl wget git net-tools \
        ufw fail2ban unattended-upgrades ripgrep >/dev/null

    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT
    systemctl enable --now unattended-upgrades.service >/dev/null 2>&1 || true
}

allow_ssh_firewall() {
    local ports port
    ports=""

    if command -v sshd >/dev/null 2>&1; then
        ports="$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2}' | sort -n -u || true)"
    fi

    if [ -z "$ports" ]; then
        ufw allow OpenSSH >/dev/null 2>&1 || ufw allow ssh >/dev/null
        return
    fi

    for port in $ports; do
        if [[ "$port" =~ ^[0-9]+$ ]]; then
            ufw allow "${port}/tcp" >/dev/null
        fi
    done
}

configure_firewall_and_fail2ban() {
    log "Configuring firewall and SSH brute-force protection"

    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null
    allow_ssh_firewall
    ufw --force enable >/dev/null

    cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
banaction = ufw
backend = systemd

[sshd]
enabled = true
filter = sshd
maxretry = 3
bantime = 24h
JAIL
    systemctl enable --now fail2ban >/dev/null
    systemctl restart fail2ban >/dev/null
}

configure_swap() {
    if swapon --show=NAME --noheadings 2>/dev/null | grep -qx '/swapfile'; then
        return
    fi

    if [ ! -f /swapfile ]; then
        log "Adding 2 GB swap file"
        fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null
    fi

    swapon /swapfile 2>/dev/null || true
    grep -qs '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
}

wait_for_network() {
    log "Checking outbound DNS and HTTPS before running the official installer"

    local attempt
    for attempt in $(seq 1 30); do
        if getent ahostsv4 raw.githubusercontent.com >/dev/null 2>&1 \
            && getent ahostsv4 github.com >/dev/null 2>&1 \
            && getent ahostsv4 nodejs.org >/dev/null 2>&1 \
            && curl -4 -fsI --max-time 8 https://raw.githubusercontent.com >/dev/null 2>&1 \
            && curl -4 -fsI --max-time 8 https://github.com >/dev/null 2>&1 \
            && curl -4 -fsI --max-time 8 https://nodejs.org >/dev/null 2>&1; then
            return 0
        fi

        log "Network not ready yet, retrying (${attempt}/30)"
        sleep 5
    done

    die "Outbound DNS/HTTPS is not ready; cannot safely run the official Hermes installer"
}

create_runtime_user() {
    validate_runtime_user

    if ! getent passwd "$HERMES_USER" >/dev/null; then
        log "Creating non-root Hermes runtime user: ${HERMES_USER}"
        useradd --create-home --shell /bin/bash --user-group "$HERMES_USER"
    fi

    refresh_runtime_paths
    passwd -l "$HERMES_USER" >/dev/null 2>&1 || true

    local group
    group="$(runtime_group)"
    install -d -o "$HERMES_USER" -g "$group" -m 700 "$HERMES_HOME"
    install -d -o "$HERMES_USER" -g "$group" -m 700 "$HERMES_WORKSPACE"
    install -d -o "$HERMES_USER" -g "$group" -m 700 "$HERMES_BACKUP_DIR"
}

install_hermes_agent() {
    log "Installing Hermes Agent as ${HERMES_USER} using the official installer"

    run_as_hermes git config --global http.lowSpeedLimit 1024 >/dev/null 2>&1 || true
    run_as_hermes git config --global http.lowSpeedTime 60 >/dev/null 2>&1 || true

    local attempt
    local installer_command
    for attempt in 1 2 3; do
        log "Official installer attempt ${attempt}/3"

        installer_command=(
            timeout 30m
            bash -c "
                set -euo pipefail
                curl -4 -fsSL --retry 5 --retry-delay 5 \"\$1\" | bash -s -- --skip-setup --hermes-home \"\$2\"
            "
            bash "$HERMES_INSTALLER_URL" "$HERMES_HOME"
        )

        if command -v setsid >/dev/null 2>&1; then
            installer_command=(setsid -w "${installer_command[@]}")
        fi

        if run_as_hermes "${installer_command[@]}"; then
            break
        fi

        log "Official installer attempt ${attempt}/3 failed"
        rm -rf "${HERMES_HOME}/hermes-agent"
        sleep $((attempt * 10))
    done

    if [ ! -x "$HERMES_BIN" ]; then
        die "Hermes binary not found after installer run: ${HERMES_BIN}"
    fi
}

sanitize_env_value() {
    printf '%s' "$1" | tr -d '\r\n'
}

is_placeholder_value() {
    local value="$1"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"

    case "$value" in
        ""|your-*|YOUR_*|changeme|CHANGE_ME|placeholder)
            return 0
            ;;
    esac
    return 1
}

upsert_env_var() {
    local key="$1"
    local value="$2"
    local clean existing tmp group

    clean="$(sanitize_env_value "$value")"
    [ -n "$clean" ] || return 0

    group="$(runtime_group)"
    touch "$HERMES_ENV_FILE"
    chown "$HERMES_USER:$group" "$HERMES_ENV_FILE"
    chmod 600 "$HERMES_ENV_FILE"

    if grep -qE "^${key}=" "$HERMES_ENV_FILE"; then
        existing="$(awk -F= -v key="$key" '$1 == key {print substr($0, length(key) + 2); exit}' "$HERMES_ENV_FILE")"
        if ! is_placeholder_value "$existing"; then
            return 0
        fi

        tmp="$(mktemp)"
        awk -v key="$key" -v value="$clean" '
            BEGIN { done = 0 }
            $0 ~ "^" key "=" {
                if (!done) {
                    print key "=" value
                    done = 1
                }
                next
            }
            { print }
            END {
                if (!done) {
                    print key "=" value
                }
            }
        ' "$HERMES_ENV_FILE" > "$tmp"
        install -o "$HERMES_USER" -g "$group" -m 600 "$tmp" "$HERMES_ENV_FILE"
        rm -f "$tmp"
        return 0
    fi

    printf '%s=%s\n' "$key" "$clean" >> "$HERMES_ENV_FILE"
    chown "$HERMES_USER:$group" "$HERMES_ENV_FILE"
    chmod 600 "$HERMES_ENV_FILE"
}

write_initial_hermes_env() {
    log "Writing Hermes environment defaults under ${HERMES_ENV_FILE}"

    local group
    group="$(runtime_group)"
    install -d -o "$HERMES_USER" -g "$group" -m 700 "$HERMES_HOME"
    touch "$HERMES_ENV_FILE"
    chown "$HERMES_USER:$group" "$HERMES_ENV_FILE"
    chmod 600 "$HERMES_ENV_FILE"

    case "$LLM_PROVIDER" in
        openrouter) upsert_env_var OPENROUTER_API_KEY "$LLM_API_KEY" ;;
        openai)     upsert_env_var OPENAI_API_KEY "$LLM_API_KEY" ;;
        anthropic)  upsert_env_var ANTHROPIC_API_KEY "$LLM_API_KEY" ;;
    esac

    upsert_env_var TELEGRAM_BOT_TOKEN "$TELEGRAM_BOT_TOKEN"
    upsert_env_var MESSAGING_CWD "$HERMES_WORKSPACE"
}

write_root_wrapper() {
    log "Installing root-friendly Hermes command wrapper at ${ROOT_WRAPPER}"

    cat > "$ROOT_WRAPPER" <<WRAPPER
#!/bin/bash
set -e

HERMES_USER="${HERMES_USER}"
HERMES_HOME_DIR="${HERMES_HOME_DIR}"
HERMES_HOME="${HERMES_HOME}"
HERMES_BIN="${HERMES_BIN}"
HERMES_PATH="${HERMES_HOME_DIR}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [ ! -x "\$HERMES_BIN" ]; then
    echo "Hermes binary not found: \$HERMES_BIN" >&2
    exit 127
fi

needs_root=false
if [ "\${1:-}" = "gateway" ]; then
    for arg in "\$@"; do
        if [ "\$arg" = "--system" ]; then
            needs_root=true
            break
        fi
    done
fi

if [ "\$(id -u)" -eq 0 ] && [ "\$needs_root" = true ]; then
    exec env HOME="\$HERMES_HOME_DIR" HERMES_HOME="\$HERMES_HOME" PATH="\$HERMES_PATH:\$PATH" "\$HERMES_BIN" "\$@"
fi

if [ "\$(id -un)" = "\$HERMES_USER" ]; then
    exec env HOME="\$HERMES_HOME_DIR" HERMES_HOME="\$HERMES_HOME" PATH="\$HERMES_PATH:\$PATH" "\$HERMES_BIN" "\$@"
fi

if [ "\$(id -u)" -eq 0 ]; then
    exec runuser -u "\$HERMES_USER" -- env HOME="\$HERMES_HOME_DIR" HERMES_HOME="\$HERMES_HOME" PATH="\$HERMES_PATH:\$PATH" "\$HERMES_BIN" "\$@"
fi

echo "Hermes is installed for user '\$HERMES_USER'. Run this command as root, or switch to that user." >&2
exit 1
WRAPPER
    chmod 0755 "$ROOT_WRAPPER"
}

write_cron_jobs() {
    log "Installing Hermes update and backup cron jobs"

    cat > /etc/cron.weekly/hermes-update <<CRON
#!/bin/bash
set -e
LOG="${UPDATE_LOG}"
touch "\$LOG"; chmod 600 "\$LOG"
{
    echo "=== \$(date -u +%FT%TZ) ==="
    if [ -x "${HERMES_BIN}" ]; then
        flock -n /var/lock/hermes-update.lock \\
            runuser -u "${HERMES_USER}" -- env \\
                HOME="${HERMES_HOME_DIR}" \\
                HERMES_HOME="${HERMES_HOME}" \\
                PATH="${HERMES_HOME_DIR}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \\
                "${HERMES_BIN}" update || echo "Hermes update skipped or failed"
    fi
} >> "\$LOG" 2>&1
CRON
    chmod 0755 /etc/cron.weekly/hermes-update

    cat > /etc/cron.daily/hermes-backup <<CRON
#!/bin/bash
set -e
umask 077
LOG="${BACKUP_LOG}"
BACKUP_DIR="${HERMES_BACKUP_DIR}"
touch "\$LOG"; chmod 600 "\$LOG"
{
    echo "=== \$(date -u +%FT%TZ) ==="
    install -d -o "${HERMES_USER}" -g "$(runtime_group)" -m 700 "\$BACKUP_DIR"
    if [ -x "${HERMES_BIN}" ]; then
        runuser -u "${HERMES_USER}" -- env \\
            HOME="${HERMES_HOME_DIR}" \\
            HERMES_HOME="${HERMES_HOME}" \\
            PATH="${HERMES_HOME_DIR}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \\
            "${HERMES_BIN}" backup --output "\$BACKUP_DIR" || echo "Hermes backup failed"
        find "\$BACKUP_DIR" -type f -name 'hermes-backup-*.zip' -mtime +14 -delete
    fi
} >> "\$LOG" 2>&1
CRON
    chmod 0755 /etc/cron.daily/hermes-backup
}

write_motd() {
    cat > /etc/update-motd.d/99-hermes <<MOTD
#!/bin/bash
HERMES_USER="${HERMES_USER}"
HERMES_HOME_DIR="${HERMES_HOME_DIR}"
HERMES_HOME="${HERMES_HOME}"
HERMES_ENV_FILE="${HERMES_ENV_FILE}"
HERMES_WRAPPER="${ROOT_WRAPPER}"

[ -x "\$HERMES_WRAPPER" ] || exit 0
version=\$("\$HERMES_WRAPPER" version 2>/dev/null | grep -oE 'v?[0-9]+\\.[0-9]+\\.[0-9a-z.-]+' | head -1)
llm=no; grep -qE '^[A-Z_]+API_KEY=..*' "\$HERMES_ENV_FILE" 2>/dev/null && llm=yes
channels=no; grep -qE '^(TELEGRAM|DISCORD|SLACK)_BOT_TOKEN=..*|^WHATSAPP_ENABLED=..*' "\$HERMES_ENV_FILE" 2>/dev/null && channels=yes
gw=absent
{ [ -f /etc/systemd/system/hermes-gateway.service ] || [ -f "\$HERMES_HOME_DIR/.config/systemd/user/hermes-gateway.service" ]; } && gw=installed
printf '\\n  Hermes %-10s  Runtime: %s   LLM: %s   Channels: %s   Gateway: %s\\n' "\${version:-unknown}" "\$HERMES_USER" "\$llm" "\$channels" "\$gw"
printf '  Quick: hermes  |  hermes doctor  |  hermes update\\n\\n'
MOTD
    chmod 0755 /etc/update-motd.d/99-hermes
}

write_readme() {
    cat > /root/README.txt <<README
Hermes Agent - Self-Hosted Personal AI Agent
=============================================

GETTING STARTED
===============
    hermes setup                 # configure LLM + messaging interactively
    hermes                       # start chatting
    hermes doctor                # diagnostics

RUNTIME MODEL
=============
    Root provisions the VPS only. Hermes runs as the non-sudo Linux user:

        ${HERMES_USER}

    Root can still type 'hermes' because /usr/local/bin/hermes forwards normal
    Hermes commands to that runtime user.

PATHS
=====
    ${HERMES_HOME}/.env              # secrets, mode 600
    ${HERMES_HOME}/config.yaml       # Hermes settings
    ${HERMES_WORKSPACE}              # default messaging work directory
    ${HERMES_BACKUP_DIR}             # daily local backups
    ${DOCTOR_LOG}                    # post-install diagnostics
    ${UPDATE_LOG}                    # weekly auto-update log
    ${BACKUP_LOG}                    # daily backup log

GATEWAY SERVICE
===============
    Do not run the gateway as root. After configuring messaging allowlists or
    pairing, install the VPS boot-time service like this:

        hermes gateway install --system --run-as-user ${HERMES_USER}
        hermes gateway start --system
        hermes gateway status --system

COMMANDS
========
    hermes model                # choose or switch LLM provider
    hermes gateway setup        # add Telegram, Discord, Slack, etc.
    hermes pairing list         # show pending DM pairing codes
    hermes backup --output ${HERMES_BACKUP_DIR}
    hermes update               # update to latest, also runs weekly

SECURITY
========
    ufw status
    fail2ban-client status sshd

    Keep ${HERMES_HOME}/.env at mode 600.
    Avoid GATEWAY_ALLOW_ALL_USERS=true on production VPSs.
    Keep MESSAGING_CWD pointed at ${HERMES_WORKSPACE}, not /root.

RESOURCES
=========
    Docs:    https://hermes-agent.nousresearch.com/
    GitHub:  https://github.com/NousResearch/hermes-agent
README
    chmod 0644 /root/README.txt

    install -o "$HERMES_USER" -g "$(runtime_group)" -m 0644 /root/README.txt "${HERMES_HOME_DIR}/README.txt"
}

run_doctor() {
    log "Running Hermes doctor"
    touch "$DOCTOR_LOG"
    chmod 600 "$DOCTOR_LOG"

    run_as_hermes "$HERMES_BIN" doctor > "$DOCTOR_LOG" 2>&1 || true
}

cleanup_bootstrap() {
    mkdir -p "$(dirname "$DONE_MARKER")"
    date -u +%FT%TZ > "$DONE_MARKER"
    rm -f /etc/profile.d/install.sh

    if [ -f "$CONFIG_FILE" ]; then
        shred -u "$CONFIG_FILE" 2>/dev/null || rm -f "$CONFIG_FILE"
    fi
}

main() {
    if [ -f "$DONE_MARKER" ]; then
        rm -f /etc/profile.d/install.sh
        log "Hermes already installed ($(cat "$DONE_MARKER")), skipping."
        exit 0
    fi

    export HOME="${HOME:-/root}"

    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090,SC1091
        . "$CONFIG_FILE"
    fi
    normalize_inputs

    log "Hermes Agent install starting"
    log "Config: provider=${LLM_PROVIDER:-none}, llm_key=$([ -n "$LLM_API_KEY" ] && echo yes || echo no), telegram_token=$([ -n "$TELEGRAM_BOT_TOKEN" ] && echo yes || echo no)"

    install_base_packages
    configure_firewall_and_fail2ban
    configure_swap
    create_runtime_user
    wait_for_network
    install_hermes_agent
    write_initial_hermes_env
    write_root_wrapper
    write_cron_jobs
    write_motd
    write_readme
    run_doctor
    cleanup_bootstrap

    cat <<EOF

==============================================================
  Hermes Agent installation complete.

  Runtime user: ${HERMES_USER}
  Command:      hermes
  README:       /root/README.txt
  Doctor log:   ${DOCTOR_LOG}
==============================================================
EOF
}

main "$@"
