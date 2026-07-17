#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl net-tools bind9-host > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO UPTIME KUMA INSTALL SCRIPT                         ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

while true; do
    echo
    printf "${YEL}Please enter Domain Name, or hit enter for insecure installation: ${DEF}"
    read DOMAIN

    if [ -z "$DOMAIN" ]; then
        echo -e "${GRN}Proceeding without TLS (HTTP only)${DEF}"
        break
    fi

    echo -e "${BLU}Checking DNS for ${DOMAIN}...${DEF}"

    if validate_domain "$DOMAIN"; then
        RESOLVED_IP=$(host "$DOMAIN" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
        if [ "$RESOLVED_IP" = "$MYIP" ]; then
            echo -e "${GRN}DNS verified: ${DOMAIN} -> ${MYIP} (direct)${DEF}"
        else
            echo -e "${GRN}DNS verified: ${DOMAIN} -> ${RESOLVED_IP} (CDN/proxy)${DEF}"
        fi
        break
    else
        echo -e "${RED}ERROR: Domain '${DOMAIN}' does not resolve to any IP address.${DEF}"
        echo -e "${YEL}Please ensure DNS is configured correctly, then try again.${DEF}"
        echo -e "${YEL}Or press Enter to skip TLS and use HTTP only.${DEF}"
    fi
done

if [ -n "$DOMAIN" ]; then
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 3001 false
fi

cd /opt
mkdir -p uptime-kuma
cd uptime-kuma
curl -sO https://raw.githubusercontent.com/louislam/uptime-kuma/master/compose.yaml

if [ -n "$DOMAIN" ]; then
    # Upstream compose publishes "3001:3001" - bind to localhost since Caddy proxies from 127.0.0.1
    sed -i 's/"3001:3001"/"127.0.0.1:3001:3001"/' /opt/uptime-kuma/compose.yaml
fi

docker compose up -d

sleep 15

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:3001"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                 UPTIME KUMA INSTALLATION COMPLETE                      ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${RED}  IMPORTANT: Open the URL NOW and create the admin account.${DEF}"
echo -e "${RED}  The first visitor to this URL becomes the administrator.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Uptime Kuma - Monitoring Tool
=============================

Access: ${ACCESS_URL}

First-time setup:
  1. Open the URL above IMMEDIATELY - the first visitor becomes admin
  2. Create your admin account
  3. Add monitors for your services

Features:
  - HTTP(s), TCP, DNS, Ping, and more
  - Beautiful status pages
  - Multiple notification channels
  - Certificate expiry monitoring
  - Maintenance windows
  - Multi-language support

Notification Options:
  - Email, Slack, Discord, Telegram
  - Webhooks, Pushover, Gotify
  - 90+ notification services

Manage Uptime Kuma:
  cd /opt/uptime-kuma
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Data Location:
  Docker volume: uptime-kuma

Backup:
  docker run --rm -v uptime-kuma:/data -v \$(pwd):/backup alpine tar czf /backup/uptime-kuma-backup.tar.gz /data

Documentation: https://github.com/louislam/uptime-kuma/wiki

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
