#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install git bind9-host curl net-tools openssl > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO PLAUSIBLE ANALYTICS INSTALL SCRIPT                  ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

echo -e "${YEL}Plausible requires a domain name for HTTPS.${DEF}"
echo

while true; do
    printf "${YEL}Please enter Domain Name: ${DEF}"
    read DOMAIN

    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}A domain name is required for Plausible.${DEF}"
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

echo -e ${BLU} "Setting up Plausible CE..." ${DEF}
cd /opt
git clone --depth 1 https://github.com/plausible/community-edition plausible-ce
cd plausible-ce

touch .env
echo "BASE_URL=https://${DOMAIN}" >> .env
echo "SECRET_KEY_BASE=$(openssl rand -base64 48)" >> .env
echo "HTTP_PORT=80" >> .env
echo "HTTPS_PORT=443" >> .env

cat > compose.override.yml << EOF
services:
  plausible:
    ports:
      - 80:80
      - 443:443
EOF

echo -e ${BLU} "Starting Plausible..." ${DEF}
docker compose up -d

sleep 30

ACCESS_URL="https://${DOMAIN}"

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}              PLAUSIBLE ANALYTICS INSTALLATION COMPLETE                 ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${RED}  IMPORTANT: Open the URL NOW and register the admin account.${DEF}"
echo -e "${RED}  The first visitor to this URL becomes the administrator.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Plausible Analytics - Privacy-Friendly Web Analytics
=====================================================

Access: ${ACCESS_URL}

First-time setup:
  1. Open the URL IMMEDIATELY - the first visitor can claim the admin account
  2. Create your admin account
  3. After registering, add DISABLE_REGISTRATION=true to /opt/plausible-ce/.env
     then restart: cd /opt/plausible-ce && docker compose up -d
  4. Add your website
  5. Install the tracking snippet

Manage Plausible:
  cd /opt/plausible-ce
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Configuration: /opt/plausible-ce/.env

Documentation: https://plausible.io/docs

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
