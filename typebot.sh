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
echo -e ${GRN} "# ${BLU}WELCOME TO TYPEBOT INSTALL SCRIPT                             ${GRN}#"
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

mkdir -p /opt/typebot
cd /opt/typebot

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8080 false
fi

PG_PASSWORD=$(uuidgen)
ENCRYPTION_SECRET=$(uuidgen | tr -d '-')

# Typebot login works only via email magic links - SMTP is required
echo
echo -e "${YEL}Typebot sends login links by email, so SMTP settings are required.${DEF}"
printf "${YEL}Admin e-mail address: ${DEF}"
read ADMIN_EMAIL
printf "${YEL}SMTP host (leave empty to configure later): ${DEF}"
read SMTP_HOST
SMTP_PORT=587
SMTP_USERNAME=""
SMTP_PASSWORD=""
if [ -n "$SMTP_HOST" ]; then
    printf "${YEL}SMTP port [587]: ${DEF}"
    read SMTP_PORT_IN
    [ -n "$SMTP_PORT_IN" ] && SMTP_PORT="$SMTP_PORT_IN"
    printf "${YEL}SMTP username: ${DEF}"
    read SMTP_USERNAME
    printf "${YEL}SMTP password: ${DEF}"
    read -s SMTP_PASSWORD
    echo
else
    echo -e "${RED}WARNING: Without SMTP nobody can log in to the builder.${DEF}"
    echo -e "${RED}Add SMTP settings to /opt/typebot/docker-compose.yml later.${DEF}"
fi
SMTP_SECURE=false
[ "$SMTP_PORT" = "465" ] && SMTP_SECURE=true

# Typebot rejects empty SMTP_*/ADMIN_EMAIL env vars - only set them when filled
ADMIN_EMAIL_LINE=""
if [ -n "$ADMIN_EMAIL" ]; then
    ADMIN_EMAIL_LINE="- ADMIN_EMAIL=${ADMIN_EMAIL}"
fi
SMTP_ENV_LINES=""
if [ -n "$SMTP_HOST" ]; then
    SMTP_ENV_LINES=$(printf '      - SMTP_HOST=%s\n      - SMTP_PORT=%s\n      - SMTP_USERNAME=%s\n      - SMTP_PASSWORD=%s\n      - SMTP_SECURE=%s\n      - NEXT_PUBLIC_SMTP_FROM=%s' "$SMTP_HOST" "$SMTP_PORT" "$SMTP_USERNAME" "$SMTP_PASSWORD" "$SMTP_SECURE" "$ADMIN_EMAIL")
fi

if [ -z "$MYIP" ]; then
    MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
fi

if [ -n "$DOMAIN" ]; then
    BUILDER_URL="https://${DOMAIN}"
    VIEWER_URL="http://${MYIP}:8081"
else
    BUILDER_URL="http://${MYIP}:8080"
    VIEWER_URL="http://${MYIP}:8081"
fi

cat > docker-compose.yml <<- EOF
volumes:
  db_data:
  redis_data:

services:
  typebot-db:
    image: postgres:16-alpine
    restart: always
    environment:
      - POSTGRES_DB=typebot
      - POSTGRES_PASSWORD=${PG_PASSWORD}
    volumes:
      - db_data:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -h localhost -U postgres -d typebot']
      interval: 5s
      timeout: 5s
      retries: 10

  typebot-redis:
    image: redis:alpine
    restart: always
    volumes:
      - redis_data:/data
    healthcheck:
      test: ['CMD', 'redis-cli', 'ping']
      interval: 5s
      timeout: 5s
      retries: 10

  typebot-builder:
    image: baptistearno/typebot-builder:latest
    restart: always
    environment:
      - DATABASE_URL=postgresql://postgres:${PG_PASSWORD}@typebot-db:5432/typebot
      - ENCRYPTION_SECRET=${ENCRYPTION_SECRET}
      - NEXTAUTH_URL=${BUILDER_URL}
      - NEXT_PUBLIC_VIEWER_URL=${VIEWER_URL}
      ${ADMIN_EMAIL_LINE}
${SMTP_ENV_LINES}
      - REDIS_URL=redis://typebot-redis:6379
      - NODE_OPTIONS=--no-node-snapshot
    ports:
      - '127.0.0.1:8080:3000'
    depends_on:
      typebot-db:
        condition: service_healthy
      typebot-redis:
        condition: service_healthy

  typebot-viewer:
    image: baptistearno/typebot-viewer:latest
    restart: always
    environment:
      - DATABASE_URL=postgresql://postgres:${PG_PASSWORD}@typebot-db:5432/typebot
      - ENCRYPTION_SECRET=${ENCRYPTION_SECRET}
      - NEXTAUTH_URL=${BUILDER_URL}
      - NEXT_PUBLIC_VIEWER_URL=${VIEWER_URL}
      - REDIS_URL=redis://typebot-redis:6379
      - NODE_OPTIONS=--no-node-snapshot
    ports:
      - '8081:3000'
    depends_on:
      typebot-db:
        condition: service_healthy
      typebot-redis:
        condition: service_healthy
EOF

if [ -z "$DOMAIN" ]; then
    echo -e ${GRN} "Installing without TLS - exposing builder port 8080 directly" ${DEF}
    sed -i "s/127.0.0.1:8080:3000/8080:3000/" /opt/typebot/docker-compose.yml
fi

docker compose up -d

sleep 10

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    BUILDER_DISPLAY="https://${DOMAIN}"
else
    BUILDER_DISPLAY="http://${MYIP}:8080"
fi
VIEWER_DISPLAY="http://${MYIP}:8081"

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                 TYPEBOT INSTALLATION COMPLETE                           ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  BUILDER URL:  ${GRN}${BUILDER_DISPLAY}${DEF}"
echo -e "${YEL}  VIEWER URL:   ${GRN}${VIEWER_DISPLAY}${DEF}"
echo
echo -e "${BLU}  Builder: Create and manage your chatbots.${DEF}"
echo -e "${BLU}  Viewer:  Where published chatbots are served.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Typebot - Chatbot Builder
=========================

Builder: ${BUILDER_DISPLAY}
Viewer:  ${VIEWER_DISPLAY}

Builder vs Viewer:
  - Builder is the admin interface where you create and edit chatbots.
  - Viewer is the public-facing service that serves published chatbots.

First-time setup:
  1. Open the Builder URL above
  2. Sign in with your admin e-mail (a login link is sent via SMTP)
  3. Build your first chatbot
  4. Publish it - the bot will be accessible via the Viewer URL

SMTP:
  Login links are sent by e-mail. If SMTP was not configured during
  install, edit the SMTP_* values in /opt/typebot/docker-compose.yml
  and run: cd /opt/typebot && docker compose up -d

Manage Typebot:
  cd /opt/typebot
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Documentation: https://docs.typebot.io

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
