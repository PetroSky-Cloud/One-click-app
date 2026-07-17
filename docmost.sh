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
echo -e ${GRN} "# ${BLU}WELCOME TO DOCMOST INSTALL SCRIPT                            ${GRN}#"
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

echo -e ${BLU} "Creating Docmost directories..." ${DEF}
mkdir -p /opt/docmost

echo -e ${BLU} "Generating secrets..." ${DEF}
APP_SECRET=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -hex 16)

echo -e ${BLU} "Creating Docker Compose file..." ${DEF}
cat > /opt/docmost/docker-compose.yml << EOFCOMPOSE
services:
  docmost:
    image: docmost/docmost:latest
    container_name: docmost
    depends_on:
      - db
      - redis
    ports:
      - '127.0.0.1:3000:3000'
    environment:
      APP_URL: 'http://localhost:3000'
      APP_SECRET: '${APP_SECRET}'
      DATABASE_URL: 'postgresql://docmost:${POSTGRES_PASSWORD}@db:5432/docmost?schema=public'
      REDIS_URL: 'redis://redis:6379'
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    container_name: docmost-db
    environment:
      POSTGRES_DB: docmost
      POSTGRES_USER: docmost
      POSTGRES_PASSWORD: '${POSTGRES_PASSWORD}'
    volumes:
      - docmost-db:/var/lib/postgresql/data
    restart: unless-stopped

  redis:
    image: redis:alpine
    container_name: docmost-redis
    restart: unless-stopped

volumes:
  docmost-db:
EOFCOMPOSE

if [ "$DOMAIN" = "" ]; then
    echo -e ${GRN} "Installing without TLS - exposing port 3000 directly" ${DEF}
    sed -i "s/127.0.0.1:3000:3000/3000:3000/" /opt/docmost/docker-compose.yml
else
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    sed -i "s|APP_URL: 'http://localhost:3000'|APP_URL: 'https://${DOMAIN}'|" /opt/docmost/docker-compose.yml
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 3000 false
fi

echo -e ${BLU} "Starting Docmost..." ${DEF}
cd /opt/docmost
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
echo -e "${GRN}                  DOCMOST INSTALLATION COMPLETE                         ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${RED}  IMPORTANT: Open the URL NOW and create your workspace and admin account.${DEF}"
echo -e "${RED}  The first visitor to this URL becomes the administrator.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Docmost - Collaborative Wiki & Documentation
=============================================

Access: ${ACCESS_URL}

First-time setup:
  1. Open the URL IMMEDIATELY - the first visitor can claim the workspace and admin account
  2. Create your workspace
  3. Create your admin account
  4. Start creating documentation

Features:
  - Real-time collaboration
  - Nested pages and spaces
  - Rich text editor
  - Comments and mentions
  - Version history
  - Full-text search

Manage Docmost:
  cd /opt/docmost
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart service
  docker compose pull && docker compose up -d  # Update

Backup Database:
  docker exec docmost-db pg_dump -U docmost docmost > backup.sql

Documentation: https://docmost.com/docs

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
