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
echo -e ${GRN} "# ${BLU}WELCOME TO MINIO INSTALL SCRIPT                               ${GRN}#"
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

echo -e ${BLU} "Creating MinIO directories..." ${DEF}
mkdir -p /opt/minio/data
cd /opt/minio

echo -e ${BLU} "Generating credentials..." ${DEF}
MINIO_ROOT_USER="admin"
MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)

echo -e ${BLU} "Creating docker-compose.yml..." ${DEF}
cat > /opt/minio/docker-compose.yml << EOFCOMPOSE
services:
  minio:
    image: minio/minio:latest
    container_name: minio
    restart: unless-stopped
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    volumes:
      - ./data:/data
    command: server /data --console-address ":9001"
EOFCOMPOSE

echo -e ${BLU} "Creating environment file..." ${DEF}
cat > /opt/minio/.env << EOFENV
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
EOFENV

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 9001 false
fi

echo -e ${BLU} "Starting MinIO..." ${DEF}
docker compose pull
docker compose up -d

sleep 15

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    CONSOLE_URL="https://${DOMAIN}"
else
    CONSOLE_URL="http://${MYIP}:9001"
fi
API_URL="http://${MYIP}:9000"

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                    MINIO INSTALLATION COMPLETE                         ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  CONSOLE URL: ${GRN}${CONSOLE_URL}${DEF}"
echo -e "${YEL}  API URL:     ${GRN}${API_URL}${DEF}"
echo -e "${YEL}  USERNAME:    ${GRN}${MINIO_ROOT_USER}${DEF}"
echo -e "${YEL}  PASSWORD:    ${GRN}${MINIO_ROOT_PASSWORD}${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
MinIO - High Performance Object Storage
=======================================

Console: ${CONSOLE_URL}
API: ${API_URL}

Credentials:
  Username: ${MINIO_ROOT_USER}
  Password: ${MINIO_ROOT_PASSWORD}

First-time setup:
  1. Open the Console URL above
  2. Login with credentials above
  3. Create buckets for your data
  4. Create access keys for applications

Features:
  - S3-compatible object storage
  - High performance (up to 100GB/s)
  - Bucket policies and versioning
  - Server-side encryption
  - Identity management
  - Replication and erasure coding

Use Cases:
  - Backup storage
  - Application data storage
  - Data lakes
  - AI/ML model storage
  - Container registry backend

S3 Client Configuration:
  Endpoint: ${API_URL}
  Access Key: Create in Console > Access Keys
  Secret Key: Created with Access Key
  Region: us-east-1 (default)

AWS CLI Example:
  aws configure
  aws --endpoint-url ${API_URL} s3 ls

mc (MinIO Client):
  docker exec -it minio mc alias set local http://localhost:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD}
  docker exec -it minio mc ls local

Manage MinIO:
  cd /opt/minio
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Data Location: /opt/minio/data

Documentation: https://min.io/docs/minio/container/index.html

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
