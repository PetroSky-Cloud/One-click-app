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
echo -e ${GRN} "# ${BLU}WELCOME TO GHOST INSTALL SCRIPT                               ${GRN}#"
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

echo -e ${BLU} "Creating Ghost directories..." ${DEF}
mkdir -p /opt/ghost
cd /opt/ghost

echo -e ${BLU} "Generating secrets..." ${DEF}
MYSQL_ROOT_PASSWORD=$(openssl rand -hex 16)
MYSQL_PASSWORD=$(openssl rand -hex 16)

if [ -n "$DOMAIN" ]; then
    GHOST_URL="https://${DOMAIN}"
else
    GHOST_URL="http://${MYIP}:2368"
fi

echo -e ${BLU} "Creating docker-compose.yml..." ${DEF}
cat > /opt/ghost/docker-compose.yml << EOFCOMPOSE
services:
  ghost:
    image: ghost:latest
    container_name: ghost
    restart: unless-stopped
    ports:
      - "2368:2368"
    environment:
      url: ${GHOST_URL}
      database__client: mysql
      database__connection__host: db
      database__connection__user: ghost
      database__connection__password: ${MYSQL_PASSWORD}
      database__connection__database: ghost
    volumes:
      - ghost_content:/var/lib/ghost/content
    depends_on:
      - db

  db:
    image: mysql:8
    container_name: ghost_db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ghost
      MYSQL_USER: ghost
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
    volumes:
      - ghost_db:/var/lib/mysql

volumes:
  ghost_content:
  ghost_db:
EOFCOMPOSE

echo -e ${BLU} "Creating environment file..." ${DEF}
cat > /opt/ghost/.env << EOFENV
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
GHOST_URL=${GHOST_URL}
EOFENV

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 2368 false
fi

echo -e ${BLU} "Starting Ghost..." ${DEF}
docker compose pull
docker compose up -d

sleep 30

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
    ADMIN_URL="https://${DOMAIN}/ghost"
else
    ACCESS_URL="http://${MYIP}:2368"
    ADMIN_URL="http://${MYIP}:2368/ghost"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                    GHOST INSTALLATION COMPLETE                         ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  BLOG URL:   ${GRN}${ACCESS_URL}${DEF}"
echo -e "${YEL}  ADMIN URL:  ${GRN}${ADMIN_URL}${DEF}"
echo
echo -e "${BLU}  Create your admin account at the admin URL.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Ghost - Professional Publishing Platform
=========================================

Blog: ${ACCESS_URL}
Admin: ${ADMIN_URL}

First-time setup:
  1. Go to ${ADMIN_URL}
  2. Create your admin account
  3. Start writing and publishing!

Features:
  - Modern, clean editor
  - Built-in SEO tools
  - Newsletter/email subscriptions
  - Member subscriptions and payments
  - Native commenting
  - Custom themes

Database Credentials (stored in /opt/ghost/.env):
  Host: db
  Database: ghost
  User: ghost
  Password: ${MYSQL_PASSWORD}

Manage Ghost:
  cd /opt/ghost
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Themes:
  Upload via Admin > Settings > Design > Change theme
  Or place in: docker exec -it ghost ls /var/lib/ghost/content/themes

Content Location:
  Docker volume: ghost_content

Backup:
  Database: docker exec ghost_db mysqldump -u root -p${MYSQL_ROOT_PASSWORD} ghost > backup.sql
  Content: docker cp ghost:/var/lib/ghost/content ./ghost-content-backup

Documentation: https://ghost.org/docs/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
