#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl net-tools > /dev/null 2>&1

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO PAPERLESS-NGX INSTALL SCRIPT                      ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

printf "%s" "Please enter Domain Name, or hit enter for insecure installation: "
read DOMAIN

echo -e ${DEF}

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

echo -e ${BLU} "Creating Paperless-ngx directories..." ${DEF}
mkdir -p /opt/paperless/data
mkdir -p /opt/paperless/media
mkdir -p /opt/paperless/export
mkdir -p /opt/paperless/consume

echo -e ${BLU} "Generating secrets..." ${DEF}
SECRET_KEY=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -hex 16)
ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -d /=+ | head -c 12)

echo -e ${BLU} "Creating Docker Compose file..." ${DEF}
cat > /opt/paperless/docker-compose.yml << EOFCOMPOSE
services:
  broker:
    image: redis:alpine
    container_name: paperless-redis
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    container_name: paperless-db
    environment:
      POSTGRES_DB: paperless
      POSTGRES_USER: paperless
      POSTGRES_PASSWORD: '${POSTGRES_PASSWORD}'
    volumes:
      - paperless-db:/var/lib/postgresql/data
    restart: unless-stopped

  webserver:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    container_name: paperless
    depends_on:
      - db
      - broker
    ports:
      - '127.0.0.1:8000:8000'
    volumes:
      - ./data:/usr/src/paperless/data
      - ./media:/usr/src/paperless/media
      - ./export:/usr/src/paperless/export
      - ./consume:/usr/src/paperless/consume
    environment:
      PAPERLESS_REDIS: redis://broker:6379
      PAPERLESS_DBHOST: db
      PAPERLESS_DBUSER: paperless
      PAPERLESS_DBPASS: '${POSTGRES_PASSWORD}'
      PAPERLESS_SECRET_KEY: '${SECRET_KEY}'
      PAPERLESS_ADMIN_USER: admin
      PAPERLESS_ADMIN_PASSWORD: '${ADMIN_PASSWORD}'
      PAPERLESS_OCR_LANGUAGE: eng
      PAPERLESS_TIME_ZONE: UTC
    restart: unless-stopped

volumes:
  paperless-db:
EOFCOMPOSE

if [ "$DOMAIN" = "" ]; then
    echo -e ${GRN} "Installing without TLS - exposing port 8000 directly" ${DEF}
    sed -i "s/127.0.0.1:8000:8000/8000:8000/" /opt/paperless/docker-compose.yml
else
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8000 false
fi

echo -e ${BLU} "Starting Paperless-ngx..." ${DEF}
cd /opt/paperless
docker compose pull
docker compose up -d

sleep 20

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:8000"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}               PAPERLESS-NGX INSTALLATION COMPLETE                      ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Admin Login:${DEF}"
echo -e "${BLU}    Username: admin${DEF}"
echo -e "${BLU}    Password: ${ADMIN_PASSWORD}${DEF}"
echo
echo -e "${BLU}  Drop files into: /opt/paperless/consume${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Paperless-ngx - Document Management System
==========================================

Access: ${ACCESS_URL}

Admin Credentials:
  Username: admin
  Password: ${ADMIN_PASSWORD}

Quick Start:
  1. Log in with admin credentials above
  2. Drop PDF/images into /opt/paperless/consume
  3. Documents are auto-processed with OCR
  4. Search, tag, and organize documents

Directories:
  Consume (drop files here): /opt/paperless/consume
  Media (processed files):   /opt/paperless/media
  Export (backups):          /opt/paperless/export
  Data (database):           /opt/paperless/data

Manage Paperless-ngx:
  cd /opt/paperless
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart service
  docker compose pull && docker compose up -d  # Update

Export All Documents:
  docker exec paperless document_exporter ../export

Mobile Apps:
  - Paperless Mobile (iOS/Android)

Documentation: https://docs.paperless-ngx.com/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
