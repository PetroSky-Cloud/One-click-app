#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl uuid-runtime net-tools bind9-host > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO LINKWARDEN INSTALL SCRIPT                          ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo

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

mkdir -p /opt/linkwarden
cd /opt/linkwarden

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 3000 false
fi

echo -e ${BLU} "Generating secrets..." ${DEF}
export POSTGRES_PASSWORD=$(uuidgen)
export NEXTAUTH_SECRET=$(uuidgen)

if [ -n "$DOMAIN" ]; then
    NEXTAUTH_URL="https://${DOMAIN}/api/v1/auth"
else
    NEXTAUTH_URL="http://${MYIP}:3000/api/v1/auth"
fi

cat > .env <<-EOF
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
NEXTAUTH_URL=${NEXTAUTH_URL}
EOF

cat > docker-compose.yml <<- EOF
version: '3.8'

volumes:
  pgdata:

services:
  postgres:
    image: postgres:16-alpine
    restart: always
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=linkwarden
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -h localhost -U postgres -d linkwarden']
      interval: 5s
      timeout: 5s
      retries: 10

  linkwarden:
    image: ghcr.io/linkwarden/linkwarden:latest
    restart: always
    environment:
      - NEXTAUTH_URL=${NEXTAUTH_URL}
      - NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
      - DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/linkwarden
    ports:
      - '127.0.0.1:3000:3000'
    volumes:
      - ./data:/data/data
    depends_on:
      postgres:
        condition: service_healthy
EOF

if [ -z "$DOMAIN" ]; then
    echo -e ${GRN} "Installing without TLS - exposing port 3000 directly" ${DEF}
    sed -i "s/127.0.0.1:3000:3000/3000:3000/" /opt/linkwarden/docker-compose.yml
fi

echo -e ${BLU} "Starting Linkwarden..." ${DEF}
docker compose up -d

sleep 10

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:3000"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   LINKWARDEN INSTALLATION COMPLETE                     ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Create your account on first visit.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Linkwarden - Bookmark and Link Manager
=======================================

Access: ${ACCESS_URL}

First-time setup:
  1. Open the URL above
  2. Register your admin account
  3. Start saving links and bookmarks

Features:
  - Collaborative bookmark management
  - Automatic page archival and screenshots
  - Full-text search across saved pages
  - Tagging, collections, and sharing
  - Browser extensions (Chrome, Firefox)
  - REST API for integrations

Manage Linkwarden:
  cd /opt/linkwarden
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart service
  docker compose pull && docker compose up -d  # Update

Data Location:
  /opt/linkwarden/data

Documentation: https://docs.linkwarden.app/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
