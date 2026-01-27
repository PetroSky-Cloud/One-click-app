#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system dependencies" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl wget gnupg ca-certificates net-tools ufw fail2ban > /dev/null 2>&1

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO CLAWDBOT INSTALL SCRIPT                            ${GRN}#"
echo -e ${GRN} "# ${YEL}Self-Hosted Personal AI Assistant                             ${GRN}#"
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

echo -e ${BLU} "Installing Clawdbot..." ${DEF}
npm install -g clawdbot@latest 2>&1 | grep -E "added|packages"

CLAWDBOT_VERSION=$(clawdbot --version 2>/dev/null)
echo -e ${GRN} "Clawdbot ${CLAWDBOT_VERSION} installed" ${DEF}

echo -e ${BLU} "Creating clawdbot user..." ${DEF}
useradd -m -s /bin/bash clawdbot 2>/dev/null || true

echo -e ${BLU} "Configuring npm for clawdbot user..." ${DEF}
sudo -u clawdbot mkdir -p /home/clawdbot/.npm-global
sudo -u clawdbot npm config set prefix '/home/clawdbot/.npm-global'
echo 'export PATH=/home/clawdbot/.npm-global/bin:$PATH' >> /home/clawdbot/.bashrc
echo 'export PATH=/home/clawdbot/.npm-global/bin:$PATH' >> /home/clawdbot/.profile

echo -e ${BLU} "Setting up systemd service..." ${DEF}
cat > /etc/systemd/system/clawdbot-gateway.service << 'EOFSERVICE'
[Unit]
Description=Clawdbot Gateway
After=network.target

[Service]
Type=simple
User=clawdbot
WorkingDirectory=/home/clawdbot
ExecStart=/usr/bin/clawdbot gateway
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOFSERVICE

systemctl daemon-reload

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                  CLAWDBOT INSTALLATION COMPLETE                        ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  NEXT STEPS:${DEF}"
echo
echo -e "${BLU}  1. Run the onboarding wizard:${DEF}"
echo -e "     sudo -iu clawdbot clawdbot onboard"
echo
echo -e "${BLU}  2. Start the gateway service:${DEF}"
echo -e "     systemctl enable --now clawdbot-gateway"
echo
echo -e "${BLU}  3. Access Control UI via SSH tunnel:${DEF}"
echo -e "     ssh -L 18789:127.0.0.1:18789 root@${MYIP}"
echo -e "     Then open: ${GRN}http://127.0.0.1:18789/${DEF}"
echo
echo -e "${RED}  IMPORTANT:${DEF}"
echo -e "  - The onboarding wizard will ask for your Anthropic/OpenAI OAuth"
echo -e "  - Claude Pro or Max subscription recommended for best experience"
echo -e "  - Gateway binds to localhost only (secure by default)"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Clawdbot - Self-Hosted Personal AI Assistant
=============================================

Version: ${CLAWDBOT_VERSION}
Server IP: ${MYIP}

SETUP INSTRUCTIONS
==================

1. Run the onboarding wizard (interactive):
   sudo -iu clawdbot clawdbot onboard

   This will:
   - Set up your AI provider (Anthropic Claude or OpenAI)
   - Configure messaging channels (Telegram, WhatsApp, Discord, etc.)
   - Create your workspace

2. Start the gateway service:
   systemctl enable --now clawdbot-gateway

3. Access the Control UI:
   From your local machine, create an SSH tunnel:
   ssh -L 18789:127.0.0.1:18789 root@${MYIP}

   Then open in browser:
   http://127.0.0.1:18789/

RECOMMENDED AI PROVIDER
=======================
Anthropic Claude Pro or Max subscription
- Claude Opus 4.5 provides the best experience
- OAuth login during onboarding

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

SECURITY
========
- Gateway binds to localhost only (127.0.0.1:18789)
- Access via SSH tunnel or Tailscale
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
clawdbot gateway              # Start gateway (foreground)
clawdbot channel list         # List connected channels
clawdbot skill list           # List available skills
clawdbot memory search <term> # Search memory
systemctl status clawdbot-gateway   # Check service status
systemctl restart clawdbot-gateway  # Restart service
journalctl -u clawdbot-gateway -f   # View logs

MEMORY & DATA
=============
All data stored in: /home/clawdbot/.clawdbot/
- Memory: Plain text Markdown files
- Settings: YAML configuration
- Compatible with Obsidian and standard backup tools

RESOURCES
=========
Documentation: https://docs.clawd.bot
GitHub: https://github.com/clawdbot/clawdbot
Discord: https://discord.gg/clawdbot

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
