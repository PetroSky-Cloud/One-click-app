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
echo -e ${GRN} "# ${BLU}WELCOME TO PHOTOPRISM INSTALL SCRIPT                          ${GRN}#"
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

echo -e ${BLU} "Creating PhotoPrism directories..." ${DEF}
mkdir -p /opt/photoprism/{originals,storage,import}
cd /opt/photoprism

echo -e ${BLU} "Generating secrets..." ${DEF}
ADMIN_PASSWORD=$(openssl rand -hex 12)
MARIADB_PASSWORD=$(openssl rand -hex 16)

echo -e ${BLU} "Creating docker-compose.yml..." ${DEF}
cat > /opt/photoprism/docker-compose.yml << EOFCOMPOSE
services:
  photoprism:
    image: photoprism/photoprism:latest
    container_name: photoprism
    restart: unless-stopped
    stop_grace_period: 10s
    depends_on:
      - mariadb
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    ports:
      - "2342:2342"
    environment:
      PHOTOPRISM_ADMIN_USER: "admin"
      PHOTOPRISM_ADMIN_PASSWORD: "${ADMIN_PASSWORD}"
      PHOTOPRISM_AUTH_MODE: "password"
      PHOTOPRISM_SITE_URL: "http://localhost:2342/"
      PHOTOPRISM_ORIGINALS_LIMIT: 5000
      PHOTOPRISM_HTTP_COMPRESSION: "gzip"
      PHOTOPRISM_LOG_LEVEL: "info"
      PHOTOPRISM_READONLY: "false"
      PHOTOPRISM_EXPERIMENTAL: "false"
      PHOTOPRISM_DISABLE_CHOWN: "false"
      PHOTOPRISM_DISABLE_WEBDAV: "false"
      PHOTOPRISM_DISABLE_SETTINGS: "false"
      PHOTOPRISM_DISABLE_TENSORFLOW: "false"
      PHOTOPRISM_DISABLE_FACES: "false"
      PHOTOPRISM_DISABLE_CLASSIFICATION: "false"
      PHOTOPRISM_DISABLE_VECTORS: "false"
      PHOTOPRISM_DISABLE_RAW: "false"
      PHOTOPRISM_RAW_PRESETS: "false"
      PHOTOPRISM_JPEG_QUALITY: 85
      PHOTOPRISM_DETECT_NSFW: "false"
      PHOTOPRISM_UPLOAD_NSFW: "true"
      PHOTOPRISM_DATABASE_DRIVER: "mysql"
      PHOTOPRISM_DATABASE_SERVER: "mariadb:3306"
      PHOTOPRISM_DATABASE_NAME: "photoprism"
      PHOTOPRISM_DATABASE_USER: "photoprism"
      PHOTOPRISM_DATABASE_PASSWORD: "${MARIADB_PASSWORD}"
      PHOTOPRISM_SITE_CAPTION: "AI-Powered Photos App"
      PHOTOPRISM_SITE_DESCRIPTION: ""
      PHOTOPRISM_SITE_AUTHOR: ""
    working_dir: "/photoprism"
    volumes:
      - "./originals:/photoprism/originals"
      - "./storage:/photoprism/storage"
      - "./import:/photoprism/import"

  mariadb:
    image: mariadb:11
    container_name: photoprism_db
    restart: unless-stopped
    stop_grace_period: 5s
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    command: >
      --innodb-buffer-pool-size=512M
      --transaction-isolation=READ-COMMITTED
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_unicode_ci
      --max-connections=512
      --innodb-rollback-on-timeout=OFF
      --innodb-lock-wait-timeout=120
    volumes:
      - photoprism_db:/var/lib/mysql
    environment:
      MARIADB_AUTO_UPGRADE: "1"
      MARIADB_INITDB_SKIP_TZINFO: "1"
      MARIADB_DATABASE: "photoprism"
      MARIADB_USER: "photoprism"
      MARIADB_PASSWORD: "${MARIADB_PASSWORD}"
      MARIADB_ROOT_PASSWORD: "${MARIADB_PASSWORD}"

volumes:
  photoprism_db:
EOFCOMPOSE

echo -e ${BLU} "Creating environment file..." ${DEF}
cat > /opt/photoprism/.env << EOFENV
ADMIN_PASSWORD=${ADMIN_PASSWORD}
MARIADB_PASSWORD=${MARIADB_PASSWORD}
EOFENV

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 2342 false
fi

echo -e ${BLU} "Starting PhotoPrism..." ${DEF}
docker compose pull
docker compose up -d

sleep 30

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:2342"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                 PHOTOPRISM INSTALLATION COMPLETE                       ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo -e "${YEL}  USERNAME:    ${GRN}admin${DEF}"
echo -e "${YEL}  PASSWORD:    ${GRN}${ADMIN_PASSWORD}${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
PhotoPrism - AI-Powered Photos App
==================================

Access: ${ACCESS_URL}
Username: admin
Password: ${ADMIN_PASSWORD}

First-time setup:
  1. Login with credentials above
  2. Upload photos via web interface or import folder
  3. Run indexing to process photos
  4. Explore AI features (faces, places, objects)

Features:
  - AI-powered face recognition
  - Automatic place/location detection
  - Object classification
  - Full-text search
  - Live photos and videos
  - RAW file support
  - WebDAV for sync
  - Mobile-friendly PWA

Upload Photos:
  Option 1: Web interface upload
  Option 2: Copy to /opt/photoprism/import, then use Library > Import
  Option 3: Copy directly to /opt/photoprism/originals
  Option 4: WebDAV client to ${ACCESS_URL}/originals/

Photo Directories:
  /opt/photoprism/originals  - Your photo library
  /opt/photoprism/import     - Upload here, then import
  /opt/photoprism/storage    - Thumbnails, database, etc.

Indexing:
  After adding photos, go to Library > Index to process them

Mobile Apps:
  Use any WebDAV client or PWA (add to home screen)

Manage PhotoPrism:
  cd /opt/photoprism
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Re-index all photos:
  docker compose exec photoprism photoprism index --cleanup

Database Backup:
  docker exec photoprism_db mariadb-dump -u root -p${MARIADB_PASSWORD} photoprism > backup.sql

Documentation: https://docs.photoprism.app/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
