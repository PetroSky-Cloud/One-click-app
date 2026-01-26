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
echo -e ${GRN} "# ${BLU}WELCOME TO HOME ASSISTANT INSTALL SCRIPT                      ${GRN}#"
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

echo -e ${BLU} "Creating Home Assistant directories..." ${DEF}
mkdir -p /opt/homeassistant/config
cd /opt/homeassistant

echo -e ${BLU} "Creating docker-compose.yml..." ${DEF}
cat > /opt/homeassistant/docker-compose.yml << 'EOFCOMPOSE'
services:
  homeassistant:
    image: ghcr.io/home-assistant/home-assistant:stable
    container_name: homeassistant
    restart: unless-stopped
    privileged: true
    network_mode: host
    environment:
      TZ: UTC
    volumes:
      - ./config:/config
      - /run/dbus:/run/dbus:ro
EOFCOMPOSE

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8123 false
fi

echo -e ${BLU} "Starting Home Assistant..." ${DEF}
docker compose pull
docker compose up -d

sleep 30

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:8123"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                HOME ASSISTANT INSTALLATION COMPLETE                    ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Complete the onboarding wizard to create your account.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Home Assistant - Smart Home Automation
======================================

Access: ${ACCESS_URL}

First-time setup:
  1. Open the URL above
  2. Create your admin account
  3. Set up your home location and units
  4. Start adding integrations and devices!

Features:
  - Local control of smart home devices
  - 2000+ integrations available
  - Automations and scenes
  - Energy monitoring
  - Voice assistant integration
  - Mobile apps (iOS/Android)

Network Mode:
  Home Assistant runs in host network mode for device discovery.
  This allows mDNS, Bluetooth, and other discovery protocols.

Ports used:
  - 8123: Web interface
  - Various ports for integrations (Zigbee, Z-Wave, etc.)

Manage Home Assistant:
  cd /opt/homeassistant
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Add-ons:
  Home Assistant Supervised add-ons are not available in Docker mode.
  Use HACS (Home Assistant Community Store) for custom integrations:
  https://hacs.xyz/

Configuration: /opt/homeassistant/config
  - configuration.yaml: Main config
  - automations.yaml: Automations
  - scripts.yaml: Scripts
  - scenes.yaml: Scenes

Backup:
  tar -czf homeassistant-backup.tar.gz /opt/homeassistant/config

Documentation: https://www.home-assistant.io/docs/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
