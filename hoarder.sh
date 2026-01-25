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
echo -e ${GRN} "# ${BLU}WELCOME TO HOARDER INSTALL SCRIPT                            ${GRN}#"
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

echo -e ${BLU} "Creating Hoarder directories..." ${DEF}
mkdir -p /opt/hoarder/data

echo -e ${BLU} "Generating secrets..." ${DEF}
NEXTAUTH_SECRET=$(openssl rand -base64 36 | tr -d '\n')
MEILI_MASTER_KEY=$(openssl rand -base64 36 | tr -d '\n')

echo -e ${BLU} "Creating Docker Compose file..." ${DEF}
cat > /opt/hoarder/docker-compose.yml << EOFCOMPOSE
services:
  web:
    image: ghcr.io/hoarder-app/hoarder:latest
    container_name: hoarder
    restart: unless-stopped
    ports:
      - '127.0.0.1:3000:3000'
    volumes:
      - ./data:/data
    environment:
      MEILI_ADDR: http://meilisearch:7700
      BROWSER_WEB_URL: http://chrome:9222
      DATA_DIR: /data
      NEXTAUTH_SECRET: '${NEXTAUTH_SECRET}'
      NEXTAUTH_URL: 'http://localhost:3000'
      MEILI_MASTER_KEY: '${MEILI_MASTER_KEY}'

  chrome:
    image: gcr.io/zenika-hub/alpine-chrome:latest
    container_name: hoarder-chrome
    restart: unless-stopped
    command:
      - --no-sandbox
      - --disable-gpu
      - --disable-dev-shm-usage
      - --remote-debugging-address=0.0.0.0
      - --remote-debugging-port=9222
      - --hide-scrollbars

  meilisearch:
    image: getmeili/meilisearch:v1.6
    container_name: hoarder-meilisearch
    restart: unless-stopped
    environment:
      MEILI_NO_ANALYTICS: true
      MEILI_MASTER_KEY: '${MEILI_MASTER_KEY}'
    volumes:
      - meilisearch-data:/meili_data

volumes:
  meilisearch-data:
EOFCOMPOSE

if [ "$DOMAIN" = "" ]; then
    echo -e ${GRN} "Installing without TLS - exposing port 3000 directly" ${DEF}
    sed -i "s/127.0.0.1:3000:3000/3000:3000/" /opt/hoarder/docker-compose.yml
else
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    sed -i "s|NEXTAUTH_URL: 'http://localhost:3000'|NEXTAUTH_URL: 'https://${DOMAIN}'|" /opt/hoarder/docker-compose.yml
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 3000 false
fi

echo -e ${BLU} "Starting Hoarder..." ${DEF}
cd /opt/hoarder
docker compose pull
docker compose up -d

sleep 15

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:3000"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   HOARDER INSTALLATION COMPLETE                        ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Create your account on first visit.${DEF}"
echo -e "${BLU}  Install browser extension for easy bookmarking.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Hoarder - Bookmark Manager with AI
==================================

Access: ${ACCESS_URL}

First-time setup:
  1. Open the URL above
  2. Create your account
  3. Install browser extension
  4. Start saving bookmarks

Features:
  - AI-powered tagging and categorization
  - Full-text search with Meilisearch
  - Screenshot capture via headless Chrome
  - Browser extensions (Chrome, Firefox)
  - Mobile apps (iOS, Android)

Browser Extensions:
  Chrome: chrome://extensions -> Load unpacked
  Firefox: about:debugging -> Load Temporary Add-on

Manage Hoarder:
  cd /opt/hoarder
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart service
  docker compose pull && docker compose up -d  # Update

Data Location:
  /opt/hoarder/data

Documentation: https://docs.hoarder.app/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
