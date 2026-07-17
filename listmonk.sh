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
echo -e ${GRN} "# ${BLU}WELCOME TO LISTMONK INSTALL SCRIPT                           ${GRN}#"
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

mkdir -p /opt/listmonk
cd /opt/listmonk

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 9000 false
fi

export POSTGRES_USER=listmonk
export POSTGRES_PASSWORD=`uuidgen`
export POSTGRES_DB=listmonk
export LISTMONK_ADMIN_USER=admin
export LISTMONK_ADMIN_PASSWORD=`uuidgen`

cat > .env <<-EOF
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
LISTMONK_ADMIN_USER=${LISTMONK_ADMIN_USER}
LISTMONK_ADMIN_PASSWORD=${LISTMONK_ADMIN_PASSWORD}
EOF

cat > docker-compose.yml <<- EOF
volumes:
  db_storage:
  uploads:

services:
  db:
    image: postgres:17-alpine
    restart: always
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    volumes:
      - db_storage:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -h localhost -U ${POSTGRES_USER} -d ${POSTGRES_DB}']
      interval: 5s
      timeout: 5s
      retries: 10

  listmonk:
    image: listmonk/listmonk:latest
    restart: always
    command: >
      sh -c "./listmonk --install --idempotent --yes --config '' &&
             ./listmonk --upgrade --yes --config '' &&
             ./listmonk --config ''"
    environment:
      - LISTMONK_app__address=0.0.0.0:9000
      - LISTMONK_ADMIN_USER=${LISTMONK_ADMIN_USER}
      - LISTMONK_ADMIN_PASSWORD=${LISTMONK_ADMIN_PASSWORD}
      - LISTMONK_db__host=db
      - LISTMONK_db__port=5432
      - LISTMONK_db__user=${POSTGRES_USER}
      - LISTMONK_db__password=${POSTGRES_PASSWORD}
      - LISTMONK_db__database=${POSTGRES_DB}
      - LISTMONK_db__ssl_mode=disable
    ports:
      - '127.0.0.1:9000:9000'
    volumes:
      - uploads:/listmonk/uploads
    depends_on:
      db:
        condition: service_healthy
EOF

if [ -z "$DOMAIN" ]; then
    echo -e ${GRN} "Installing without TLS - exposing port 9000 directly" ${DEF}
    sed -i "s/127.0.0.1:9000:9000/9000:9000/" /opt/listmonk/docker-compose.yml
fi

docker compose up -d

sleep 10

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:9000"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                 LISTMONK INSTALLATION COMPLETE                         ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Admin Username:  ${GRN}${LISTMONK_ADMIN_USER}${DEF}"
echo -e "${BLU}  Admin Password:  ${GRN}${LISTMONK_ADMIN_PASSWORD}${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Listmonk - Newsletter & Mailing List Manager
=============================================

Access: ${ACCESS_URL}

Admin Credentials:
  Username: ${LISTMONK_ADMIN_USER}
  Password: ${LISTMONK_ADMIN_PASSWORD}

Getting Started:
  1. Open the URL above
  2. Log in with the admin credentials
  3. Configure SMTP settings under Settings > SMTP
  4. Create your first mailing list
  5. Start sending campaigns

Manage Listmonk:
  cd /opt/listmonk
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Backup Database:
  docker exec listmonk-db-1 pg_dump -U ${POSTGRES_USER} ${POSTGRES_DB} > backup.sql

Documentation: https://listmonk.app/docs

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
