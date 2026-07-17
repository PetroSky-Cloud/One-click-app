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

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO ACTUAL BUDGET INSTALL SCRIPT                        ${GRN}#"
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

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

echo -e ${BLU} "Creating Actual Budget directories..." ${DEF}
mkdir -p /opt/actualbudget/actual-data

echo -e ${BLU} "Creating Docker Compose file..." ${DEF}
cat > /opt/actualbudget/docker-compose.yml << 'EOFCOMPOSE'
services:
  actual-budget:
    image: docker.io/actualbudget/actual-server:latest
    container_name: actual-budget
    ports:
      - '127.0.0.1:5006:5006'
    volumes:
      - ./actual-data:/data
    restart: unless-stopped
EOFCOMPOSE

if [ "$DOMAIN" = "" ]; then
    echo -e ${GRN} "Installing without TLS - exposing port 5006 directly" ${DEF}
    sed -i "s/127.0.0.1:5006:5006/5006:5006/" /opt/actualbudget/docker-compose.yml
else
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 5006 false
fi

echo -e ${BLU} "Starting Actual Budget..." ${DEF}
cd /opt/actualbudget
docker compose pull
docker compose up -d

sleep 10

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:5006"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                 ACTUAL BUDGET INSTALLATION COMPLETE                    ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  First user sets the server password via the web UI.${DEF}"
echo -e "${BLU}  Then create a budget to get started.${DEF}"
echo
if [ -n "$DOMAIN" ]; then
    echo -e "${BLU}  TIP: Port 5006 is bound to localhost only (secure).${DEF}"
    echo
fi
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Actual Budget
=============

Access: ${ACCESS_URL}

First-time setup:
  1. Open the URL above
  2. Set your server password
  3. Create a new budget or import from file

Features:
  - Envelope-style budgeting
  - Bank sync support
  - Transaction import (OFX, QFX, QIF, CSV)
  - Reports and spending analysis
  - Multi-device sync
  - Fully local / self-hosted data

Manage Actual Budget:
  cd /opt/actualbudget
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart service
  docker compose pull && docker compose up -d  # Update

Data Location:
  /opt/actualbudget/actual-data/ # Budgets and server data

Documentation: https://actualbudget.org/docs/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
