#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl net-tools bind9-host apache2-utils > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO PORTAINER INSTALL SCRIPT                           ${GRN}#"
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

echo -e ${BLU} "Creating Portainer volume..." ${DEF}
docker volume create portainer_data

echo -e ${BLU} "Generating admin credentials..." ${DEF}
ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -d /=+ | head -c 16)
HASH=$(htpasswd -nbB admin "$ADMIN_PASSWORD" | cut -d: -f2)

if [ -n "$DOMAIN" ]; then
    PUBLISH_FLAG="127.0.0.1:9000:9000"
else
    PUBLISH_FLAG="9000:9000"
fi

echo -e ${BLU} "Starting Portainer..." ${DEF}
docker run -d \
    --name portainer \
    --restart=always \
    -p ${PUBLISH_FLAG} \
    -p 8000:8000 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest \
    --admin-password="$HASH"

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 9000 false
fi

sleep 10

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:9000"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                  PORTAINER INSTALLATION COMPLETE                       ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Admin Login:${DEF}"
echo -e "${BLU}    Username: admin${DEF}"
echo -e "${BLU}    Password: ${ADMIN_PASSWORD}${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Portainer - Docker Management GUI
==================================

Access: ${ACCESS_URL}

Admin Credentials:
  Username: admin
  Password: ${ADMIN_PASSWORD}

First-time setup:
  1. Open the URL above
  2. Log in with the admin credentials above
  3. Choose "Get Started" for local Docker management
  4. Start managing your containers!

Features:
  - Visual container management
  - Docker Compose stack deployment
  - Container logs and stats
  - Image management
  - Network configuration
  - Volume management

Manage Portainer:
  docker ps                      # Check status
  docker logs -f portainer       # View logs
  docker restart portainer       # Restart
  docker pull portainer/portainer-ce:latest && docker stop portainer && docker rm portainer  # Update (re-run install)

Edge Agent (for remote management):
  Port 8000 is exposed for Portainer Edge Agent connections

Documentation: https://docs.portainer.io/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
