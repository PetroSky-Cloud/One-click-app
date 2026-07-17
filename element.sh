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
echo -e ${GRN} "# ${BLU}WELCOME TO ELEMENT WEB INSTALL SCRIPT                         ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e "${YEL}  Element Web is a full-featured Matrix chat client."
echo -e "${YEL}  This script deploys a standalone Element Web instance"
echo -e "${YEL}  that connects to any Matrix homeserver."
echo
echo -e "${YEL}  For a full Matrix + Element stack, use the Matrix script instead."
echo -e "${DEF}"

# Domain prompt
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

# Matrix homeserver URL
echo
echo -e "${YEL}  Element Web needs a Matrix homeserver to connect to."
echo -e "${YEL}  If you have your own Synapse server, enter its URL below."
echo -e "${YEL}  Otherwise, press Enter to use the public matrix.org server.${DEF}"
echo
printf "${YEL}Enter Matrix homeserver URL (default: https://matrix.org): ${DEF}"
read HOMESERVER_URL

if [ -z "$HOMESERVER_URL" ]; then
    HOMESERVER_URL="https://matrix.org"
    HOMESERVER_NAME="matrix.org"
else
    # Strip trailing slash
    HOMESERVER_URL=$(echo "$HOMESERVER_URL" | sed 's:/*$::')
    # Extract server name from URL (remove protocol)
    HOMESERVER_NAME=$(echo "$HOMESERVER_URL" | sed 's|https\?://||')
fi

echo -e "${GRN}Homeserver: ${HOMESERVER_URL}${DEF}"

# Install Docker
echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

echo -e ${BLU} "Creating Element Web directories..." ${DEF}
mkdir -p /opt/element

# Write Element config.json
cat > /opt/element/config.json << ELEMENTEOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "${HOMESERVER_URL}",
            "server_name": "${HOMESERVER_NAME}"
        },
        "m.identity_server": {
            "base_url": "https://vector.im"
        }
    },
    "disable_custom_urls": false,
    "disable_guests": true,
    "brand": "Element",
    "roomDirectory": {
        "servers": ["${HOMESERVER_NAME}", "matrix.org"]
    },
    "showLabsSettings": false,
    "enable_presence_by_hs_toggle": true
}
ELEMENTEOF

# Write docker-compose.yml
if [ -n "$DOMAIN" ]; then
    # Bind to localhost only — Caddy handles external traffic
    cat > /opt/element/docker-compose.yml << 'EOFCOMPOSE'
services:
  element:
    image: vectorim/element-web:latest
    container_name: element-web
    restart: unless-stopped
    ports:
      - '127.0.0.1:8080:80'
    volumes:
      - /opt/element/config.json:/app/config.json:ro
EOFCOMPOSE
else
    # No domain — expose port 8080 directly
    cat > /opt/element/docker-compose.yml << 'EOFCOMPOSE'
services:
  element:
    image: vectorim/element-web:latest
    container_name: element-web
    restart: unless-stopped
    ports:
      - '8080:80'
    volumes:
      - /opt/element/config.json:/app/config.json:ro
EOFCOMPOSE
fi

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8080 false
fi

echo -e ${BLU} "Starting Element Web..." ${DEF}
cd /opt/element
docker compose pull
docker compose up -d

sleep 5

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:8080"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}              ELEMENT WEB INSTALLATION COMPLETE                         ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:   ${GRN}${ACCESS_URL}${DEF}"
echo -e "${YEL}  HOMESERVER:   ${GRN}${HOMESERVER_URL}${DEF}"
echo
echo -e "${BLU}  Log in with your existing Matrix account, or register${DEF}"
echo -e "${BLU}  a new account on the configured homeserver.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Element Web - Matrix Chat Client
==================================

Access:     ${ACCESS_URL}
Homeserver: ${HOMESERVER_URL}

Getting started:
  1. Open the URL above
  2. Log in with your Matrix account or create a new one
  3. You can change the homeserver on the login screen

Configuration:
  Element config:   /opt/element/config.json
  Docker Compose:   /opt/element/docker-compose.yml

Change homeserver:
  1. Edit /opt/element/config.json
  2. Update "base_url" and "server_name" to your homeserver
  3. Run: cd /opt/element && docker compose restart

Manage Element Web:
  cd /opt/element
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart service
  docker compose pull && docker compose up -d  # Update

For a full Matrix server (Synapse + Element), use the Matrix script instead.

Documentation: https://element.io/user-guide

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
