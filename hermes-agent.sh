#!/bin/bash
#
# Hermes Agent one-click installer for ModulesGarden Proxmox + WHMCS.
# Wraps the official Hermes installer with VPS hardening, non-root user,
# systemd drop-in, pre-seeded secrets, backups, and logrotate.
#
# Spec: docs/superpowers/specs/2026-04-18-hermes-agent-one-click-design.md
#

set -euo pipefail

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

LOGFILE=/var/log/hermes-install.log
touch "$LOGFILE"
chmod 600 "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

echo "[$(date)] === Hermes Agent one-click install starting ==="

# -----------------------------------------------------------------------------
# Load config written by init/ bootstrap (or use safe defaults for manual runs).
# -----------------------------------------------------------------------------
CONFIG_FILE=/root/.hermes-install-config
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
fi

LLM_PROVIDER="${LLM_PROVIDER:-openrouter}"
LLM_API_KEY="${LLM_API_KEY:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TERMINAL_BACKEND="${TERMINAL_BACKEND:-local}"
AGENT_NAME="${AGENT_NAME:-}"
CLIENT_FIRSTNAME="${CLIENT_FIRSTNAME:-}"
CLIENT_LASTNAME="${CLIENT_LASTNAME:-}"
CLIENT_EMAIL="${CLIENT_EMAIL:-}"

# Normalize dropdown values (human-readable labels -> bash tokens)
case "${LLM_PROVIDER,,}" in
    *openrouter*) LLM_PROVIDER=openrouter ;;
    *openai*)     LLM_PROVIDER=openai ;;
    *anthropic*)  LLM_PROVIDER=anthropic ;;
    skip|*)       LLM_PROVIDER= ;;
esac
case "${TERMINAL_BACKEND,,}" in
    *docker*) TERMINAL_BACKEND=docker ;;
    *)        TERMINAL_BACKEND=local ;;
esac

echo "[$(date)] Config: provider=${LLM_PROVIDER:-none} backend=$TERMINAL_BACKEND llm_key=$([ -n "$LLM_API_KEY" ] && echo yes || echo no) tg_token=$([ -n "$TELEGRAM_BOT_TOKEN" ] && echo yes || echo no)"

# -----------------------------------------------------------------------------
# Step 1: apt baseline. Temporarily mask unattended-upgrades to avoid dpkg
# locks during install.
# -----------------------------------------------------------------------------
echo -e "${BLU}[$(date)] Installing base packages...${DEF}"

systemctl stop unattended-upgrades.service 2>/dev/null || true
systemctl mask unattended-upgrades.service 2>/dev/null || true

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

apt-get update -qq
apt-get -qqy install \
    curl wget git gnupg ca-certificates net-tools \
    ufw fail2ban unattended-upgrades openssl tar gzip bind9-host \
    ripgrep ffmpeg \
    build-essential python3-dev libffi-dev >/dev/null

# -----------------------------------------------------------------------------
# Step 2: UFW -- deny-in, allow-out, SSH only
# -----------------------------------------------------------------------------
echo -e "${BLU}[$(date)] Configuring UFW firewall...${DEF}"
ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null
ufw allow ssh              >/dev/null
ufw --force enable         >/dev/null
echo -e "${GRN}[$(date)] UFW enabled (SSH only)${DEF}"

# -----------------------------------------------------------------------------
# Step 3: fail2ban -- SSH protection (3 retries -> 24h ban)
# -----------------------------------------------------------------------------
echo -e "${BLU}[$(date)] Configuring fail2ban...${DEF}"
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
echo -e "${GRN}[$(date)] fail2ban active (SSH 3-retry -> 24h ban)${DEF}"

# -----------------------------------------------------------------------------
# Step 4: Swap (dynamic: 4 GB on <2 GB RAM VPS, else 2 GB)
# -----------------------------------------------------------------------------
if [ ! -f /swapfile ]; then
    TOTAL_MB=$(free -m | awk '/^Mem:/ {print $2}')
    if [ "$TOTAL_MB" -lt 2000 ]; then
        SWAP_SIZE=4G
    else
        SWAP_SIZE=2G
    fi
    echo -e "${BLU}[$(date)] Creating ${SWAP_SIZE} swap file...${DEF}"
    fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# -----------------------------------------------------------------------------
# Step 5: unattended-upgrades -- security pocket only, no auto-reboot
# -----------------------------------------------------------------------------
echo -e "${BLU}[$(date)] Enabling security auto-updates...${DEF}"
cat > /etc/apt/apt.conf.d/52unattended-upgrades-security <<'UNATT'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
UNATT

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'UPG'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
UPG

systemctl unmask unattended-upgrades.service 2>/dev/null || true
systemctl enable --now unattended-upgrades >/dev/null
echo -e "${GRN}[$(date)] Security auto-updates enabled${DEF}"

# -----------------------------------------------------------------------------
# Step 6: Docker CE (only if terminal_backend=docker)
# -----------------------------------------------------------------------------
DOCKER_PULL_PID=""
if [ "$TERMINAL_BACKEND" = "docker" ]; then
    echo -e "${BLU}[$(date)] Installing Docker CE for docker terminal backend...${DEF}"
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
    systemctl enable --now docker >/dev/null

    AGENT_IMAGE=nikolaik/python-nodejs:python3.11-nodejs20
    echo -e "${BLU}[$(date)] Pre-pulling $AGENT_IMAGE in background...${DEF}"
    docker pull "$AGENT_IMAGE" >/var/log/hermes-docker-pull.log 2>&1 &
    DOCKER_PULL_PID=$!
fi

# -----------------------------------------------------------------------------
# Step 7: Create hermes system user (non-root runtime identity)
# -----------------------------------------------------------------------------
if ! id hermes >/dev/null 2>&1; then
    echo -e "${BLU}[$(date)] Creating hermes system user...${DEF}"
    useradd -m -s /bin/bash hermes
fi

if [ "$TERMINAL_BACKEND" = "docker" ]; then
    usermod -aG docker hermes
fi

# Enable systemd linger so user-scope timers/journals survive logout. Harmless
# no-op for system-scope unit; gives us room to expand later.
loginctl enable-linger hermes 2>/dev/null || true

install -d -m 0700 -o hermes -g hermes /home/hermes/.hermes

# -----------------------------------------------------------------------------
# Step 8: Pre-seed .env with LLM keys ONLY. We deliberately withhold channel
# tokens so the Hermes installer's auto-gateway-install does NOT run -- that
# path creates a user-scope systemd unit that our /etc/ drop-in cannot
# override. Channel tokens are appended after the drop-in exists (Step 13).
# -----------------------------------------------------------------------------
ENV_FILE=/home/hermes/.hermes/.env
{
    echo "# Hermes Agent environment (auto-generated by one-click installer)"
    echo "# Add/update keys with: sudo -iu hermes hermes config set KEY value"
    echo ""
    case "$LLM_PROVIDER" in
        openrouter) [ -n "$LLM_API_KEY" ] && echo "OPENROUTER_API_KEY=$LLM_API_KEY" ;;
        openai)     [ -n "$LLM_API_KEY" ] && echo "OPENAI_API_KEY=$LLM_API_KEY" ;;
        anthropic)  [ -n "$LLM_API_KEY" ] && echo "ANTHROPIC_API_KEY=$LLM_API_KEY" ;;
    esac
} > "$ENV_FILE"
chown hermes:hermes "$ENV_FILE"
chmod 600 "$ENV_FILE"

# -----------------------------------------------------------------------------
# Step 9: config.yaml -- backend, approvals, pairing defaults
# -----------------------------------------------------------------------------
CFG_YAML=/home/hermes/.hermes/config.yaml
{
    echo "# Hermes Agent config (one-click installer defaults)"
    echo ""
    echo "terminal:"
    echo "  backend: $TERMINAL_BACKEND"
    if [ "$TERMINAL_BACKEND" = "docker" ]; then
        echo "  docker_image: \"nikolaik/python-nodejs:python3.11-nodejs20\""
        echo "  container_cpu: 1"
        echo "  container_memory: 2048"
        echo "  container_persistent: false"
    fi
    echo ""
    echo "approvals:"
    echo "  mode: manual"
    echo "  timeout: 60"
    echo ""
    echo "unauthorized_dm_behavior: pair"
} > "$CFG_YAML"
chown hermes:hermes "$CFG_YAML"
chmod 600 "$CFG_YAML"

# -----------------------------------------------------------------------------
# Step 10: SOUL.md (optional personalization)
# -----------------------------------------------------------------------------
if [ -n "$CLIENT_FIRSTNAME" ] || [ -n "$AGENT_NAME" ]; then
    SOUL=/home/hermes/.hermes/SOUL.md
    {
        echo "# Agent Context"
        echo ""
        if [ -n "$CLIENT_FIRSTNAME" ] || [ -n "$CLIENT_LASTNAME" ]; then
            echo "The person you are serving is ${CLIENT_FIRSTNAME:-} ${CLIENT_LASTNAME:-}."
            echo ""
        fi
        if [ -n "$AGENT_NAME" ]; then
            echo "You should refer to yourself as \"$AGENT_NAME\" when asked."
            echo ""
        fi
        echo "Respond with warmth and respect. Keep conversations private and do not"
        echo "reveal API keys, system paths, or session data to external parties."
    } > "$SOUL"
    chown hermes:hermes "$SOUL"
    chmod 644 "$SOUL"
fi

# -----------------------------------------------------------------------------
# Step 11: Run official Hermes installer as hermes user, --skip-setup to avoid
# the interactive wizard. With no channel tokens in .env, the installer will
# skip auto-gateway-install (which would create an unoverridable user unit).
# -----------------------------------------------------------------------------
echo -e "${BLU}[$(date)] Running official Hermes installer (this takes 3-5 minutes)...${DEF}"

HERMES_INSTALL_URL=https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh

if ! sudo -iu hermes bash -c "curl -fsSL $HERMES_INSTALL_URL | bash -s -- --skip-setup"; then
    echo -e "${RED}[$(date)] Hermes installer failed; see $LOGFILE${DEF}"
    exit 1
fi

HERMES_BIN=/home/hermes/.local/bin/hermes
if [ ! -x "$HERMES_BIN" ]; then
    echo -e "${RED}[$(date)] hermes binary not found at $HERMES_BIN after install${DEF}"
    exit 1
fi

# Use absolute path so interactive login MOTD doesn't pollute capture; grep for
# a line that looks like a version string.
HERMES_VERSION=$(sudo -u hermes "$HERMES_BIN" version 2>/dev/null \
    | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9a-z.-]+' | head -1)
[ -z "$HERMES_VERSION" ] && HERMES_VERSION="v0.10.x"
echo -e "${GRN}[$(date)] Hermes installed: $HERMES_VERSION${DEF}"

# -----------------------------------------------------------------------------
# Step 12: systemd hardening drop-in. Safe to write before the parent unit
# exists -- systemd merges drop-ins at daemon-reload / unit load.
# -----------------------------------------------------------------------------
echo -e "${BLU}[$(date)] Installing systemd hardening drop-in...${DEF}"
install -d -m 0755 /etc/systemd/system/hermes-gateway.service.d

cat > /etc/systemd/system/hermes-gateway.service.d/10-hardening.conf <<'DROPIN'
[Service]
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/home/hermes/.hermes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
ProtectProc=invisible
ProcSubset=pid
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
RestrictNamespaces=yes
LockPersonality=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
SystemCallArchitectures=native
PrivateTmp=yes
CapabilityBoundingSet=
AmbientCapabilities=
UMask=0077
MemoryMax=2G
TasksMax=512
DROPIN
chmod 0644 /etc/systemd/system/hermes-gateway.service.d/10-hardening.conf

# -----------------------------------------------------------------------------
# Step 13: Append channel tokens to .env (post-installer, pre-gateway-install)
# -----------------------------------------------------------------------------
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    {
        echo ""
        echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN"
    } >> "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"

# -----------------------------------------------------------------------------
# Step 14: Install system-scope gateway IFF any channel token present. Run as
# root (required for /etc/systemd/system write). --run-as-user hermes ensures
# the service drops privileges at runtime and satisfies Hermes's "refuse to
# install system service as root" guard.
# -----------------------------------------------------------------------------
HAS_CHANNEL_TOKEN=no
for VAR in TELEGRAM_BOT_TOKEN DISCORD_BOT_TOKEN SLACK_BOT_TOKEN SLACK_APP_TOKEN WHATSAPP_ENABLED; do
    if grep -qE "^${VAR}=..*" "$ENV_FILE"; then
        HAS_CHANNEL_TOKEN=yes
        break
    fi
done

if [ "$HAS_CHANNEL_TOKEN" = "yes" ]; then
    echo -e "${BLU}[$(date)] Installing hermes-gateway as system-scope service...${DEF}"
    if ! HERMES_HOME=/home/hermes/.hermes "$HERMES_BIN" \
            gateway install --system --run-as-user hermes; then
        echo -e "${RED}[$(date)] gateway install failed; see $LOGFILE${DEF}"
        exit 1
    fi

    systemctl daemon-reload
    if ! systemctl enable --now hermes-gateway.service; then
        echo -e "${YEL}[$(date)] hermes-gateway failed to start -- check journalctl${DEF}"
    fi
    echo -e "${GRN}[$(date)] hermes-gateway.service installed and started${DEF}"
else
    echo -e "${YEL}[$(date)] No channel tokens configured -- gateway service not installed.${DEF}"
    echo -e "${YEL}    Run 'sudo -iu hermes hermes gateway setup' after first login.${DEF}"
fi

# -----------------------------------------------------------------------------
# Step 15: Daily backup cron (7-day retention, exclude *_cache and sandboxes)
# -----------------------------------------------------------------------------
install -d -m 0700 /root/hermes-backups

cat > /etc/cron.daily/hermes-backup <<'CRON'
#!/bin/bash
# Daily snapshot of /home/hermes/.hermes (excluding caches). 7-day rotation.
set -e
BACKUP_DIR=/root/hermes-backups
DATE=$(date +%F)
OUT="$BACKUP_DIR/hermes-$DATE.tar.gz"
tar --warning=no-file-changed \
    --exclude='.hermes/*_cache' \
    --exclude='.hermes/sandboxes' \
    -czf "$OUT" -C /home/hermes .hermes 2>/dev/null || true
chmod 600 "$OUT" 2>/dev/null || true
ls -1t "$BACKUP_DIR"/hermes-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
CRON
chmod 0755 /etc/cron.daily/hermes-backup

# -----------------------------------------------------------------------------
# Step 16: logrotate (systemd journal handles service logs separately)
# -----------------------------------------------------------------------------
cat > /etc/logrotate.d/hermes <<'ROT'
/home/hermes/.hermes/logs/*.log {
    weekly
    rotate 4
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    su hermes hermes
}
ROT
chmod 0644 /etc/logrotate.d/hermes

# -----------------------------------------------------------------------------
# Step 17: Post-install health check (log-only, don't fail install)
# -----------------------------------------------------------------------------
echo -e "${BLU}[$(date)] Running hermes doctor...${DEF}"
# shellcheck disable=SC2024  # redirect runs as root (caller) which owns /var/log
sudo -iu hermes hermes doctor > /var/log/hermes-doctor.log 2>&1 || true
chmod 600 /var/log/hermes-doctor.log 2>/dev/null || true

# -----------------------------------------------------------------------------
# Step 18: Wait on background Docker pull (if any)
# -----------------------------------------------------------------------------
if [ -n "$DOCKER_PULL_PID" ] && kill -0 "$DOCKER_PULL_PID" 2>/dev/null; then
    echo -e "${BLU}[$(date)] Waiting for Docker pull to finish...${DEF}"
    wait "$DOCKER_PULL_PID" || true
fi

# -----------------------------------------------------------------------------
# Step 19: Detect public IP
# -----------------------------------------------------------------------------
MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || true)
if ! echo "$MYIP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    MYIP=$(curl -4s --max-time 10 icanhazip.com 2>/dev/null || true)
fi
if ! echo "$MYIP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    MYIP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
[ -z "$MYIP" ] && MYIP=YOUR_SERVER_IP

# -----------------------------------------------------------------------------
# Step 20: README.txt
# -----------------------------------------------------------------------------
NEXT_STEPS=""
if [ -z "$LLM_API_KEY" ]; then
    NEXT_STEPS="${NEXT_STEPS}
  - Configure LLM provider:
      sudo -iu hermes hermes model
"
fi
if [ "$HAS_CHANNEL_TOKEN" != "yes" ]; then
    NEXT_STEPS="${NEXT_STEPS}
  - Set up messaging platforms (Telegram / Discord / Slack / etc.):
      sudo -iu hermes hermes gateway setup
"
fi

BACKEND_NOTE=""
if [ "$TERMINAL_BACKEND" = "local" ]; then
    BACKEND_NOTE="  (dangerous commands require approval via messaging; HERMES_EXEC_ASK=1)"
elif [ "$TERMINAL_BACKEND" = "docker" ]; then
    BACKEND_NOTE="  (agent commands run in isolated Docker containers)"
fi

cat > /root/README.txt <<EOF
Hermes Agent - Self-Hosted Personal AI Agent
=============================================

Version: $HERMES_VERSION
Server IP: $MYIP
Terminal backend: $TERMINAL_BACKEND

ACCESS
======
The agent runs under the non-root 'hermes' user. To use the CLI:
    sudo -iu hermes

Then:
    hermes                    Start interactive chat (TUI)
    hermes doctor             Run diagnostics
    hermes model              Configure LLM provider
    hermes gateway setup      Add messaging platforms
    hermes pairing list       Show pending DM pairing codes
    hermes update             Update to latest version

Configuration:    /home/hermes/.hermes/config.yaml
Secrets (.env):   /home/hermes/.hermes/.env           (chmod 600)
Service logs:     journalctl -u hermes-gateway -f
App logs:         /home/hermes/.hermes/logs/

SECURITY
========
- UFW firewall: SSH inbound only, all other incoming denied
- fail2ban: 3 SSH retries -> 24h ban
- unattended-upgrades: security pocket enabled (no auto-reboot)
- Gateway runs as 'hermes' user (non-root)
- systemd hardening drop-in applied
   (verify: systemd-analyze security hermes-gateway.service)
- .env permissions: 600 hermes:hermes
- Terminal backend: $TERMINAL_BACKEND
$BACKEND_NOTE

MESSAGING AUTH
==============
Hermes uses DM pairing. When an unknown user DMs the bot, the bot replies
with an 8-character pairing code. Approve on the CLI:
    sudo -iu hermes hermes pairing approve telegram ABC12DEF

Revoke a user:
    sudo -iu hermes hermes pairing revoke telegram <user_id>

BACKUPS
=======
Daily tars at /root/hermes-backups/ (7-day retention, excludes *_cache and sandboxes).
Restore by extracting into /home/hermes/ as the hermes user:
    sudo -iu hermes tar -xzf /root/hermes-backups/hermes-YYYY-MM-DD.tar.gz -C /home/hermes

NEXT STEPS
==========$NEXT_STEPS

RESOURCES
=========
Docs:       https://hermes-agent.nousresearch.com/
GitHub:     https://github.com/NousResearch/hermes-agent
License:    MIT

Installed: $(date)
EOF
chmod 0644 /root/README.txt

# -----------------------------------------------------------------------------
# Step 21: credentials.txt (reference only -- never echo raw key values)
# -----------------------------------------------------------------------------
{
    echo "Hermes Agent - Credentials Reference"
    echo "====================================="
    echo "Server IP: $MYIP"
    echo "CLI user: hermes (access via: sudo -iu hermes)"
    echo ""
    echo "Paths:"
    echo "  .env:        /home/hermes/.hermes/.env"
    echo "  config:      /home/hermes/.hermes/config.yaml"
    echo "  hardening:   /etc/systemd/system/hermes-gateway.service.d/10-hardening.conf"
    echo ""
    [ -n "$LLM_API_KEY" ] && echo "LLM provider: $LLM_PROVIDER (key pre-seeded in .env)"
    [ -n "$TELEGRAM_BOT_TOKEN" ] && echo "Telegram bot token: pre-seeded in .env"
    echo ""
    echo "After noting anything you need from this file, delete it:"
    echo "    shred -u /root/credentials.txt"
    echo ""
    echo "Generated: $(date)"
} > /root/credentials.txt
chmod 0600 /root/credentials.txt

# -----------------------------------------------------------------------------
# Step 22: Clean up sensitive bootstrap artifacts
# -----------------------------------------------------------------------------
if [ -f /root/.hermes-install-config ]; then
    shred -u /root/.hermes-install-config 2>/dev/null \
        || rm -f /root/.hermes-install-config
fi
rm -f /etc/profile.d/install.sh

# -----------------------------------------------------------------------------
# Step 23: Completion banner
# -----------------------------------------------------------------------------
if [ "$HAS_CHANNEL_TOKEN" = "yes" ]; then
    GW_STATUS="active"
else
    GW_STATUS="not configured (no channel tokens)"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                HERMES AGENT INSTALLATION COMPLETE                      ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  Server IP:${DEF}        $MYIP"
echo -e "${YEL}  CLI user:${DEF}         hermes  (access: sudo -iu hermes)"
echo -e "${YEL}  Terminal backend:${DEF} $TERMINAL_BACKEND"
echo -e "${YEL}  Gateway service:${DEF}  $GW_STATUS"
echo
echo -e "${BLU}  README:${DEF}       /root/README.txt"
echo -e "${BLU}  Credentials:${DEF}  /root/credentials.txt  (chmod 600 -- shred after noting)"
echo -e "${BLU}  Install log:${DEF}  $LOGFILE"
echo
echo -e "${GRN}========================================================================${DEF}"
echo
echo "[$(date)] === Hermes Agent install complete ==="
