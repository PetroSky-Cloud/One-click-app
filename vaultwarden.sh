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
echo -e ${GRN} "# ${BLU}WELCOME TO VAULTWARDEN INSTALL SCRIPT                         ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

while true; do
    echo
    printf "${YEL}Please enter Domain Name, or hit enter for insecure installation: ${DEF}"
    read DOMAIN

    if [ -z "$DOMAIN" ]; then
        echo -e "${GRN}Proceeding without TLS (HTTP only)${DEF}"
        echo -e "${YEL}WARNING: Browser extensions require HTTPS. HTTP mode is for testing only.${DEF}"
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

if ! command -v docker &> /dev/null; then
    echo -e "${RED}ERROR: Docker installation failed. Aborting.${DEF}"
    rm -f /etc/profile.d/install.sh
    return 1 2>/dev/null || exit 1
fi

mkdir -p /opt/vaultwarden

echo -e ${BLU} "Generating admin token..." ${DEF}
ADMIN_TOKEN=$(openssl rand -base64 48 | tr -d '\n')

if [ -n "$DOMAIN" ]; then
    DOMAIN_ENV="https://${DOMAIN}"
    PUBLISH_FLAG="127.0.0.1:8000:80"
else
    DOMAIN_ENV="http://${MYIP}:8000"
    PUBLISH_FLAG="8000:80"
fi

echo -e ${BLU} "Pulling Vaultwarden..." ${DEF}
docker pull vaultwarden/server:latest

echo -e ${BLU} "Starting Vaultwarden..." ${DEF}
docker run -d --name vaultwarden \
  --env DOMAIN="${DOMAIN_ENV}" \
  --env ADMIN_TOKEN="${ADMIN_TOKEN}" \
  --volume /opt/vaultwarden/data/:/data/ \
  --restart unless-stopped \
  --publish ${PUBLISH_FLAG} \
  vaultwarden/server:latest

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8000 false
fi

sleep 5

if ! docker ps --format '{{.Names}}' | grep -q "^vaultwarden$"; then
    echo -e "${RED}WARNING: Vaultwarden container is not running. Check: docker logs vaultwarden${DEF}"
fi

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:8000"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                 VAULTWARDEN INSTALLATION COMPLETE                      ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:    ${GRN}${ACCESS_URL}${DEF}"
echo -e "${YEL}  ADMIN PANEL:   ${GRN}${ACCESS_URL}/admin${DEF}"
echo -e "${YEL}  ADMIN TOKEN:   ${GRN}${ADMIN_TOKEN}${DEF}"
echo
echo -e "${BLU}  Create your account at the main URL.${DEF}"
echo -e "${BLU}  Use the admin panel to configure settings.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Vaultwarden - Bitwarden Compatible Password Manager
====================================================

Access: ${ACCESS_URL}
Admin Panel: ${ACCESS_URL}/admin
Admin Token: ${ADMIN_TOKEN}

First-time setup:
  1. Open the URL above
  2. Create your account (email + master password)
  3. Install browser extension or mobile app
  4. Configure server URL to: ${ACCESS_URL}

Admin Panel:
  Access ${ACCESS_URL}/admin with the admin token above.
  Use it to:
  - Manage users and organizations
  - Configure SMTP for email
  - Enable/disable features
  - View diagnostics

Client Apps:
  - Browser: Bitwarden extension (Chrome, Firefox, Safari, Edge)
  - Desktop: Bitwarden desktop app
  - Mobile: Bitwarden (iOS/Android)
  - CLI: Bitwarden CLI

Important: In all clients, set the server URL to:
  ${ACCESS_URL}

Manage Vaultwarden:
  docker ps                      # Check status
  docker logs -f vaultwarden     # View logs
  docker restart vaultwarden     # Restart
  docker pull vaultwarden/server:latest && docker stop vaultwarden && docker rm vaultwarden  # Then re-run to update

Data Location: /opt/vaultwarden/data/

Backup:
  tar -czf vaultwarden-backup.tar.gz /opt/vaultwarden/data/

Documentation: https://github.com/dani-garcia/vaultwarden/wiki

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
