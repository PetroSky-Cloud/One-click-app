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
echo -e ${GRN} "# ${BLU}WELCOME TO RALLLY INSTALL SCRIPT                              ${GRN}#"
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

mkdir -p /opt/rallly
cd /opt/rallly

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 3000 false
fi

export POSTGRES_PASSWORD=`uuidgen`
export SECRET_PASSWORD=$(uuidgen | tr -d '-')

if [ -n "$DOMAIN" ]; then
    export BASE_URL="https://${DOMAIN}"
else
    export BASE_URL="http://${MYIP}:3000"
fi

cat > .env <<-EOF
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
SECRET_PASSWORD=${SECRET_PASSWORD}
BASE_URL=${BASE_URL}
EOF

cat > docker-compose.yml <<- EOF
version: '3.8'

volumes:
  db_storage:

services:
  rallly_db:
    image: postgres:14-alpine
    restart: always
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=rallly
    volumes:
      - db_storage:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -h localhost -U postgres -d rallly']
      interval: 5s
      timeout: 5s
      retries: 10

  rallly:
    image: lukevella/rallly:latest
    restart: always
    environment:
      - DATABASE_URL=postgres://postgres:${POSTGRES_PASSWORD}@rallly_db/rallly
      - SECRET_PASSWORD=${SECRET_PASSWORD}
      - NEXT_PUBLIC_BASE_URL=${BASE_URL}
      - ALLOWED_EMAILS=*
    ports:
      - '127.0.0.1:3000:3000'
    depends_on:
      rallly_db:
        condition: service_healthy
EOF

if [ -z "$DOMAIN" ]; then
    echo -e ${GRN} "Installing without TLS - exposing port 3000 directly" ${DEF}
    sed -i "s/127.0.0.1:3000:3000/3000:3000/" /opt/rallly/docker-compose.yml
fi

docker compose up -d

sleep 10

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:3000"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   RALLLY INSTALLATION COMPLETE                          ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Create polls and share them with participants.${DEF}"
echo -e "${BLU}  Configure SMTP in environment for email notifications.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Rallly - Meeting Poll & Scheduling
===================================

Access: ${ACCESS_URL}

Getting Started:
  1. Open the URL above
  2. Create a new poll
  3. Share the link with participants
  4. Participants vote on their preferred times

SMTP Configuration (for email notifications):
  Edit /opt/rallly/.env and add:
    SMTP_HOST=smtp.example.com
    SMTP_PORT=587
    SMTP_USER=your@email.com
    SMTP_PWD=your-password
    SUPPORT_EMAIL=your@email.com
    NOREPLY_EMAIL=noreply@example.com
  Then restart: cd /opt/rallly && docker compose up -d

Manage Rallly:
  cd /opt/rallly
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Documentation: https://support.rallly.co

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
