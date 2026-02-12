#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system dependencies" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl wget gnupg ca-certificates net-tools ufw fail2ban openssl > /dev/null 2>&1

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO OPENCLAW INSTALL SCRIPT                             ${GRN}#"
echo -e ${GRN} "# ${YEL}Self-Hosted Personal AI Assistant (formerly Clawdbot)          ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

echo -e ${BLU} "Configuring firewall (UFW)..." ${DEF}
ufw default deny incoming > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1
ufw allow ssh > /dev/null 2>&1
ufw --force enable > /dev/null 2>&1
echo -e ${GRN} "Firewall enabled (SSH only)" ${DEF}

echo -e ${BLU} "Configuring fail2ban..." ${DEF}
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
echo -e ${GRN} "Fail2ban configured (SSH protection)" ${DEF}

echo -e ${BLU} "Installing Node.js 22..." ${DEF}
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
apt-get install -y nodejs > /dev/null 2>&1

NODE_VERSION=$(node --version)
echo -e ${GRN} "Node.js ${NODE_VERSION} installed" ${DEF}

echo -e ${BLU} "Adding swap space (2GB)..." ${DEF}
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile > /dev/null 2>&1
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo -e ${BLU} "Installing OpenClaw..." ${DEF}
npm install -g openclaw@latest 2>&1 | grep -E "added|packages"

OPENCLAW_VERSION=$(openclaw --version 2>/dev/null)
echo -e ${GRN} "OpenClaw ${OPENCLAW_VERSION} installed" ${DEF}

echo -e ${BLU} "Creating openclaw user..." ${DEF}
useradd -m -s /bin/bash openclaw 2>/dev/null || true

echo -e ${BLU} "Configuring npm for openclaw user..." ${DEF}
sudo -u openclaw mkdir -p /home/openclaw/.npm-global
sudo -u openclaw npm config set prefix '/home/openclaw/.npm-global'
echo 'export PATH=/home/openclaw/.npm-global/bin:$PATH' >> /home/openclaw/.bashrc
echo 'export PATH=/home/openclaw/.npm-global/bin:$PATH' >> /home/openclaw/.profile

echo -e ${BLU} "Generating gateway auth token..." ${DEF}
GATEWAY_TOKEN=$(openssl rand -hex 32)

echo -e ${BLU} "Creating secure OpenClaw configuration..." ${DEF}
sudo -u openclaw mkdir -p /home/openclaw/.openclaw

cat > /home/openclaw/.openclaw/openclaw.json << EOFCONFIG
{
  "gateway": {
    "bind": "loopback",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "${GATEWAY_TOKEN}"
    },
    "controlUi": {
      "dangerouslyDisableDeviceAuth": false
    }
  },
  "channels": {
    "defaults": {
      "dmPolicy": "pairing"
    }
  },
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "all",
        "scope": "agent",
        "workspaceAccess": "none"
      }
    }
  },
  "discovery": {
    "mdns": {
      "mode": "off"
    }
  },
  "logging": {
    "redactSensitive": "tools"
  }
}
EOFCONFIG

chown -R openclaw:openclaw /home/openclaw/.openclaw
chmod 700 /home/openclaw/.openclaw
chmod 600 /home/openclaw/.openclaw/openclaw.json
echo -e ${GRN} "Secure configuration created" ${DEF}

echo -e ${BLU} "Setting up systemd service..." ${DEF}
cat > /etc/systemd/system/openclaw-gateway.service << 'EOFSERVICE'
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
User=openclaw
WorkingDirectory=/home/openclaw
ExecStart=/usr/bin/openclaw gateway
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=OPENCLAW_GATEWAY_BIND=loopback

[Install]
WantedBy=multi-user.target
EOFSERVICE

systemctl daemon-reload

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                  OPENCLAW INSTALLATION COMPLETE                        ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  NEXT STEPS:${DEF}"
echo
echo -e "${BLU}  1. Run the onboarding wizard:${DEF}"
echo -e "     sudo -iu openclaw openclaw onboard"
echo
echo -e "${BLU}  2. Start the gateway service:${DEF}"
echo -e "     systemctl enable --now openclaw-gateway"
echo
echo -e "${BLU}  3. Access Control UI via SSH tunnel:${DEF}"
echo -e "     ssh -L 18789:127.0.0.1:18789 root@${MYIP}"
echo -e "     Then open: ${GRN}http://127.0.0.1:18789/${DEF}"
echo
echo -e "${BLU}  4. Run security audit after setup:${DEF}"
echo -e "     sudo -iu openclaw openclaw security audit --deep"
echo
echo -e "${RED}  SECURITY:${DEF}"
echo -e "  - Gateway auth token generated (see /root/credentials.txt)"
echo -e "  - Gateway binds to localhost only (never exposed publicly)"
echo -e "  - DM policy: pairing mode (unknown senders must pair first)"
echo -e "  - Sandbox: enabled for all agents (isolated tool execution)"
echo -e "  - mDNS discovery: disabled"
echo -e "  - Never expose port 18789 to the internet"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/credentials.txt << EOF
OpenClaw Credentials
====================

Gateway Auth Token: ${GATEWAY_TOKEN}
Server IP: ${MYIP}

Use this token when connecting remote clients or the Control UI.
Keep this file secure and delete after noting credentials.

Generated: $(date)
EOF
chmod 600 /root/credentials.txt

cat > /root/README.txt << EOF
OpenClaw - Self-Hosted Personal AI Assistant
=============================================

Version: ${OPENCLAW_VERSION}
Server IP: ${MYIP}

SETUP INSTRUCTIONS
==================

1. Run the onboarding wizard (interactive):
   sudo -iu openclaw openclaw onboard

   This will:
   - Set up your AI provider (Anthropic Claude or OpenAI)
   - Configure messaging channels (Telegram, WhatsApp, Discord, etc.)
   - Create your workspace

2. Start the gateway service:
   systemctl enable --now openclaw-gateway

3. Access the Control UI:
   From your local machine, create an SSH tunnel:
   ssh -L 18789:127.0.0.1:18789 root@${MYIP}

   Then open in browser:
   http://127.0.0.1:18789/

4. Run security audit:
   sudo -iu openclaw openclaw security audit --deep

AVAILABLE CHANNELS
==================
- Telegram (easiest to set up)
- WhatsApp (via WhatsApp Web)
- Discord
- Slack
- Signal
- Matrix
- Microsoft Teams
- Google Chat
- WebChat
- iMessage (via BlueBubbles)

SECURITY
========
- Gateway binds to localhost only (127.0.0.1:18789)
- Gateway auth: token mode (see /root/credentials.txt)
- DM policy: pairing (unknown senders must pair first)
- Sandbox: enabled for all agents (isolated execution)
- mDNS discovery: disabled
- Access via SSH tunnel or Tailscale only
- Never expose port 18789 to the internet directly
- UFW firewall enabled (SSH only, all other ports blocked)
- Fail2ban active (blocks IPs after 3 failed SSH attempts for 24h)

FIREWALL COMMANDS
=================
ufw status                    # Check firewall status
fail2ban-client status sshd   # Check banned IPs
fail2ban-client unban <IP>    # Unban an IP address

MANAGEMENT COMMANDS
===================
openclaw gateway              # Start gateway (foreground)
openclaw doctor               # Check configuration health
openclaw security audit       # Run security audit
openclaw security audit --deep # Deep security audit
openclaw channel list         # List connected channels
openclaw skill list           # List available skills
openclaw pairing list <chan>  # List pending pairing requests
systemctl status openclaw-gateway   # Check service status
systemctl restart openclaw-gateway  # Restart service
journalctl -u openclaw-gateway -f   # View logs

DATA & CONFIG
=============
Config: /home/openclaw/.openclaw/openclaw.json
Data:   /home/openclaw/.openclaw/
Logs:   journalctl -u openclaw-gateway

RESOURCES
=========
Documentation: https://docs.openclaw.ai
GitHub: https://github.com/openclaw/openclaw
Website: https://openclaw.ai

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo -e "${BLU}Credentials: /root/credentials.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
