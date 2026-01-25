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
echo -e ${GRN} "# ${BLU}WELCOME TO IMMICH INSTALL SCRIPT                             ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

printf "%s" "Please enter Domain Name, or hit enter for insecure installation: "
read DOMAIN

echo -e ${DEF}

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

echo -e ${BLU} "Creating Immich directories..." ${DEF}
mkdir -p /opt/immich
mkdir -p /opt/immich/library

echo -e ${BLU} "Generating secrets..." ${DEF}
DB_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -base64 32 | tr -d '\n')

echo -e ${BLU} "Downloading official Immich compose files..." ${DEF}
cd /opt/immich

curl -sL https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml -o docker-compose.yml
curl -sL https://github.com/immich-app/immich/releases/latest/download/hwaccel.transcoding.yml -o hwaccel.transcoding.yml
curl -sL https://github.com/immich-app/immich/releases/latest/download/hwaccel.ml.yml -o hwaccel.ml.yml

echo -e ${BLU} "Creating environment file..." ${DEF}
cat > /opt/immich/.env << EOFENV
UPLOAD_LOCATION=/opt/immich/library
IMMICH_VERSION=release
DB_PASSWORD=${DB_PASSWORD}

DB_HOSTNAME=immich_postgres
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
REDIS_HOSTNAME=immich_redis
EOFENV

if [ "$DOMAIN" = "" ]; then
    echo -e ${GRN} "Installing without TLS - exposing port 2283 directly" ${DEF}
else
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 2283 false
fi

echo -e ${BLU} "Starting Immich..." ${DEF}
docker compose pull
docker compose up -d

sleep 30

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:2283"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   IMMICH INSTALLATION COMPLETE                         ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Create your admin account on first visit.${DEF}"
echo -e "${BLU}  Download mobile apps to auto-backup photos.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Immich - Self-hosted Photo & Video Backup
==========================================

Access: ${ACCESS_URL}

First-time setup:
  1. Open the URL above
  2. Create your admin account
  3. Download mobile app (iOS/Android)
  4. Configure backup settings in app

Features:
  - Automatic photo/video backup from mobile
  - Face recognition and people tagging
  - Location-based browsing (map view)
  - Memories and timeline view
  - Sharing and albums
  - Machine learning features

Mobile Apps:
  iOS: App Store - search "Immich"
  Android: Play Store or F-Droid - search "Immich"

Library Location:
  /opt/immich/library

Manage Immich:
  cd /opt/immich
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart all services
  docker compose pull && docker compose up -d  # Update

Backup:
  - Photos: /opt/immich/library
  - Database: docker exec immich_postgres pg_dump -U postgres immich > backup.sql

Documentation: https://immich.app/docs

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
