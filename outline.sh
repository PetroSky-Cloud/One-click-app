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
EOFENV

echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 3000 false

echo -e ${BLU} "Starting Outline..." ${DEF}
docker compose pull
docker compose up -d

sleep 30

ACCESS_URL="https://${DOMAIN}"

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   OUTLINE INSTALLATION COMPLETE                        ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${RED}  IMPORTANT: You must configure authentication (SSO) to use Outline.${DEF}"
echo -e "${YEL}  See /root/README.txt for setup instructions.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Outline - Team Knowledge Base
=============================

Access: ${ACCESS_URL}

IMPORTANT: Authentication Setup Required!
-----------------------------------------
Outline requires SSO authentication. You must configure at least one
authentication provider before you can log in.

Authentication Options:
  1. Slack (easiest for teams already using Slack)
  2. Google Workspace
  3. Microsoft/Azure AD
  4. OIDC (any OpenID Connect provider)
  5. SAML

To configure authentication:
  1. Stop Outline: cd /opt/outline && docker compose down
  2. Edit docker-compose.yml and add your auth provider env vars
  3. Restart: docker compose up -d

Example - Google Authentication:
  Add to outline service environment in docker-compose.yml:
    GOOGLE_CLIENT_ID: your-client-id
    GOOGLE_CLIENT_SECRET: your-client-secret
    ALLOWED_DOMAINS: yourdomain.com

Example - Slack Authentication:
  Add to outline service environment in docker-compose.yml:
    SLACK_CLIENT_ID: your-client-id
    SLACK_CLIENT_SECRET: your-client-secret

For full authentication setup guide:
  https://docs.getoutline.com/s/hosting/doc/authentication-7ViKRmRY5o

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
