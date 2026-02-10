#!/bin/bash

clear

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl uuid-runtime net-tools bind9-host openssl > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO SUPABASE INSTALL SCRIPT                            ${GRN}#"
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

curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

if [ "$DOMAIN" = "" ]; then
    echo "installing without certificates and proper TLS termination"
else
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8000 false
fi

cd /opt
git clone --depth 1 https://github.com/supabase/supabase
mkdir supabase-project
cp -rf supabase/docker/* supabase-project
cp supabase/docker/.env.example supabase-project/.env
cd supabase-project

# Generate strong random credentials
# POSTGRES_PASSWORD - any length is fine
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
# DASHBOARD_PASSWORD - for web login
DASHBOARD_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
# JWT_SECRET - minimum 32 chars, we use 64
JWT_SECRET=$(openssl rand -hex 32)
# SECRET_KEY_BASE - for Rails encryption (128 hex chars)
SECRET_KEY_BASE=$(openssl rand -hex 64)
# VAULT_ENC_KEY - MUST be exactly 32 characters for AES-256
VAULT_ENC_KEY=$(openssl rand -hex 16)

# Update .env with secure credentials
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${POSTGRES_PASSWORD}/" .env
sed -i "s/^DASHBOARD_PASSWORD=.*/DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}/" .env
sed -i "s/^JWT_SECRET=.*/JWT_SECRET=${JWT_SECRET}/" .env
sed -i "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=${SECRET_KEY_BASE}/" .env
sed -i "s/^VAULT_ENC_KEY=.*/VAULT_ENC_KEY=${VAULT_ENC_KEY}/" .env

docker compose pull
docker compose up -d

sleep 10

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:8000"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                 SUPABASE INSTALLATION COMPLETE                         ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Dashboard Credentials:${DEF}"
echo -e "${YEL}    Username: ${GRN}supabase${DEF}"
echo -e "${YEL}    Password: ${GRN}${DASHBOARD_PASSWORD}${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Supabase - Firebase Alternative
===============================

Access: ${ACCESS_URL}

Dashboard Credentials:
  Username: supabase
  Password: ${DASHBOARD_PASSWORD}

Database:
  Host: localhost
  Port: 5432
  User: postgres
  Password: ${POSTGRES_PASSWORD}

Manage Supabase:
  cd /opt/supabase-project
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Configuration: /opt/supabase-project/.env

Documentation: https://supabase.com/docs

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
