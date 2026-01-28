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
echo -e ${GRN} "# ${BLU}WELCOME TO OUTLINE INSTALL SCRIPT                             ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

while true; do
    echo
    printf "${YEL}Please enter Domain Name (REQUIRED for Outline): ${DEF}"
    read DOMAIN

    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}Outline requires a domain for proper operation.${DEF}"
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

echo
echo -e "${YEL}Outline requires email for authentication (magic link login).${DEF}"
echo -e "${YEL}You need SMTP credentials to send login emails.${DEF}"
echo
printf "${YEL}SMTP Host (e.g., smtp.gmail.com): ${DEF}"
read SMTP_HOST

printf "${YEL}SMTP Port (e.g., 587): ${DEF}"
read SMTP_PORT

printf "${YEL}SMTP Username (your email): ${DEF}"
read SMTP_USERNAME

printf "${YEL}SMTP Password (app password): ${DEF}"
read SMTP_PASSWORD

printf "${YEL}From Email (e.g., noreply@yourdomain.com): ${DEF}"
read SMTP_FROM_EMAIL

printf "${YEL}Admin Email (for first login): ${DEF}"
read ADMIN_EMAIL

echo -e ${BLU} "Creating Outline directories..." ${DEF}
mkdir -p /opt/outline/data
cd /opt/outline

echo -e ${BLU} "Generating secrets..." ${DEF}
SECRET_KEY=$(openssl rand -hex 32)
UTILS_SECRET=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -hex 16)
MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)

echo -e ${BLU} "Creating docker-compose.yml..." ${DEF}
cat > /opt/outline/docker-compose.yml << EOFCOMPOSE
services:
  outline:
    image: outlinewiki/outline:latest
    container_name: outline
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      SECRET_KEY: ${SECRET_KEY}
      UTILS_SECRET: ${UTILS_SECRET}
      DATABASE_URL: postgres://outline:${POSTGRES_PASSWORD}@postgres:5432/outline
      REDIS_URL: redis://redis:6379
      URL: https://${DOMAIN}
      PORT: 3000
      FILE_STORAGE: local
      FILE_STORAGE_LOCAL_ROOT_DIR: /var/lib/outline/data
      FILE_STORAGE_UPLOAD_MAX_SIZE: 26214400
      FORCE_HTTPS: "false"
      ENABLE_UPDATES: "true"
      WEB_CONCURRENCY: 1
      LOG_LEVEL: info
      DEFAULT_LANGUAGE: en_US
      RATE_LIMITER_ENABLED: "true"
      RATE_LIMITER_REQUESTS: 1000
      RATE_LIMITER_DURATION_WINDOW: 60
      SMTP_HOST: ${SMTP_HOST}
      SMTP_PORT: ${SMTP_PORT}
      SMTP_USERNAME: ${SMTP_USERNAME}
      SMTP_PASSWORD: ${SMTP_PASSWORD}
      SMTP_FROM_EMAIL: ${SMTP_FROM_EMAIL}
      SMTP_REPLY_EMAIL: ${SMTP_FROM_EMAIL}
      SMTP_SECURE: "false"
    volumes:
      - ./data:/var/lib/outline/data
    depends_on:
      - postgres
      - redis

  postgres:
    image: postgres:15
    container_name: outline_db
    restart: unless-stopped
    environment:
      POSTGRES_USER: outline
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: outline
    volumes:
      - outline_db:/var/lib/postgresql/data

  redis:
    image: redis:7
    container_name: outline_redis
    restart: unless-stopped
    volumes:
      - outline_redis:/data

volumes:
  outline_db:
  outline_redis:
EOFCOMPOSE

echo -e ${BLU} "Creating environment file..." ${DEF}
cat > /opt/outline/.env << EOFENV
SECRET_KEY=${SECRET_KEY}
UTILS_SECRET=${UTILS_SECRET}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
DOMAIN=${DOMAIN}
ADMIN_EMAIL=${ADMIN_EMAIL}
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_USERNAME=${SMTP_USERNAME}
SMTP_PASSWORD=${SMTP_PASSWORD}
SMTP_FROM_EMAIL=${SMTP_FROM_EMAIL}
EOFENV

echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 3000 false

echo -e ${BLU} "Starting Outline..." ${DEF}
docker compose pull
docker compose up -d

echo -e ${BLU} "Waiting for Outline to initialize..." ${DEF}
sleep 45

echo -e ${BLU} "Creating admin user (${ADMIN_EMAIL})..." ${DEF}
docker compose exec -T outline node build/server/scripts/seed.js ${ADMIN_EMAIL} 2>/dev/null || true
sleep 5

ACCESS_URL="https://${DOMAIN}"

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   OUTLINE INSTALLATION COMPLETE                        ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Admin Email: ${GRN}${ADMIN_EMAIL}${DEF}"
echo -e "${BLU}  Login via email magic link (check your inbox).${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Outline - Team Knowledge Base
=============================

Access: ${ACCESS_URL}

Login:
  Admin Email: ${ADMIN_EMAIL}
  Method: Email Magic Link (check your inbox)

How to Login:
  1. Open ${ACCESS_URL}
  2. Enter your email address
  3. Check your inbox for the magic link
  4. Click the link to sign in

Adding More Users:
  After logging in as admin, go to Settings > Members
  to invite new users via email.

SMTP Configuration:
  Host: ${SMTP_HOST}
  Port: ${SMTP_PORT}
  Username: ${SMTP_USERNAME}
  From: ${SMTP_FROM_EMAIL}

Features:
  - Beautiful document editor (Notion-like)
  - Real-time collaboration
  - Full-text search
  - Nested documents and collections
  - Markdown support
  - Integrations (Slack, GitHub, etc.)
  - API for automation

Database Credentials (stored in /opt/outline/.env):
  Host: postgres
  Database: outline
  User: outline
  Password: ${POSTGRES_PASSWORD}

Manage Outline:
  cd /opt/outline
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Backup:
  docker exec outline_db pg_dump -U outline outline > backup.sql
  tar -czf outline-data-backup.tar.gz /opt/outline/data

Documentation: https://docs.getoutline.com/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
