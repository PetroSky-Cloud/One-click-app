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
echo -e ${GRN} "# ${BLU}WELCOME TO PENPOT INSTALL SCRIPT                               ${GRN}#"
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

echo
printf "${YEL}Please enter EMAIL for first user: ${DEF}"
read EMAIL
printf "${YEL}Please enter PASSWORD for first user: ${DEF}"
read PASSWORD
printf "${YEL}Please enter FULLNAME for first user: ${DEF}"
read FULLNAME

echo -e ${DEF}

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 9001 false
fi

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

mkdir -p /opt/penpot
cd /opt/penpot
curl -o docker-compose.yaml https://raw.githubusercontent.com/penpot/penpot/main/docker/images/docker-compose.yaml

echo -e ${BLU} "Starting Penpot..." ${DEF}
docker compose -p penpot -f docker-compose.yaml up -d

echo -e ${BLU} "Waiting for containers to start..." ${DEF}
sleep 60

echo -e ${BLU} "Creating admin user..." ${DEF}
docker exec penpot-penpot-backend-1 python3 manage.py create-profile -e "$EMAIL" -p "$PASSWORD" -n "$FULLNAME" 2>/dev/null || true

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:9001"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   PENPOT INSTALLATION COMPLETE                         ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Login with: ${GRN}${EMAIL}${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Penpot - Design & Prototyping
==============================

Access: ${ACCESS_URL}

Login:
  Email: ${EMAIL}

Manage Penpot:
  cd /opt/penpot
  docker compose -p penpot ps              # Check status
  docker compose -p penpot logs -f         # View logs
  docker compose -p penpot restart         # Restart
  docker compose -p penpot pull && docker compose -p penpot up -d  # Update

Documentation: https://help.penpot.app/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/penpot.sh
rm -f /etc/profile.d/install.sh
