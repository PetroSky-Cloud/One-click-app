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
echo -e ${GRN} "# ${BLU}WELCOME TO CAL.COM INSTALL SCRIPT                             ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

while true; do
    echo
    printf "${YEL}Please enter Domain Name (REQUIRED for Cal.com): ${DEF}"
    read DOMAIN

    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}Cal.com requires a domain for proper operation.${DEF}"
        echo -e "${YEL}Please enter a domain or press Ctrl+C to cancel.${DEF}"
        continue
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
    fi
done

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

echo -e ${BLU} "Creating Cal.com directories..." ${DEF}
mkdir -p /opt/calcom
cd /opt/calcom

echo -e ${BLU} "Generating secrets..." ${DEF}
POSTGRES_PASSWORD=$(openssl rand -hex 16)
NEXTAUTH_SECRET=$(openssl rand -base64 32 | tr -d '/+=')
CALENDSO_ENCRYPTION_KEY=$(openssl rand -hex 16)

echo -e ${BLU} "Creating docker-compose.yml..." ${DEF}
cat > /opt/calcom/docker-compose.yml << EOFCOMPOSE
services:
  calcom:
    image: calcom/cal.com:latest
    container_name: calcom
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgresql://calcom:${POSTGRES_PASSWORD}@db:5432/calcom
      DATABASE_DIRECT_URL: postgresql://calcom:${POSTGRES_PASSWORD}@db:5432/calcom
      NEXTAUTH_SECRET: ${NEXTAUTH_SECRET}
      CALENDSO_ENCRYPTION_KEY: ${CALENDSO_ENCRYPTION_KEY}
      NEXTAUTH_URL: https://${DOMAIN}
      NEXT_PUBLIC_WEBAPP_URL: https://${DOMAIN}
      NEXT_PUBLIC_API_V2_URL: https://${DOMAIN}/api/v2
      LICENSE: agree
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:15
    container_name: calcom_db
    restart: unless-stopped
    environment:
      POSTGRES_DB: calcom
      POSTGRES_USER: calcom
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - calcom_db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U calcom"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  calcom_db:
EOFCOMPOSE

echo -e ${BLU} "Creating environment file..." ${DEF}
cat > /opt/calcom/.env << EOFENV
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY}
DOMAIN=${DOMAIN}
EOFENV

echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 3000 false

echo -e ${BLU} "Starting Cal.com..." ${DEF}
docker compose pull
docker compose up -d

sleep 45

ACCESS_URL="https://${DOMAIN}"

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   CAL.COM INSTALLATION COMPLETE                        ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Create your account at the URL above.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Cal.com - Scheduling Infrastructure
===================================

Access: ${ACCESS_URL}

First-time setup:
  1. Open the URL above
  2. Click "Create an account"
  3. Set up your availability
  4. Create event types
  5. Share your booking link!

Features:
  - Calendar integrations (Google, Outlook, Apple)
  - Custom event types and durations
  - Team scheduling
  - Round-robin and collective booking
  - Payments integration (Stripe)
  - Webhooks and API
  - Custom branding
  - Video conferencing integrations

Calendar Integrations:
  Go to Settings > Calendars to connect:
  - Google Calendar
  - Microsoft Outlook
  - Apple Calendar

Video Integrations:
  Go to Settings > Apps to enable:
  - Zoom
  - Google Meet
  - Microsoft Teams
  - Daily.co

Database Credentials (stored in /opt/calcom/.env):
  Host: db
  Database: calcom
  User: calcom
  Password: ${POSTGRES_PASSWORD}

Manage Cal.com:
  cd /opt/calcom
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Backup:
  docker exec calcom_db pg_dump -U calcom calcom > backup.sql

Environment Variables:
  See /opt/calcom/.env for configuration
  Full list: https://cal.com/docs/self-hosting/docker

Documentation: https://cal.com/docs

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
