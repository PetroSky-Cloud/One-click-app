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
echo -e ${GRN} "# ${BLU}WELCOME TO APPWRITE INSTALL SCRIPT                           ${GRN}#"
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

echo
printf "${YEL}Please enter your e-mail address (used for TLS certificates): ${DEF}"
read EMAIL

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

echo -e ${BLU} "Installing Appwrite..." ${DEF}

# Appwrite terminates TLS itself (Let's Encrypt on 80/443) - no Caddy needed
cd /opt
docker run --rm \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    --volume /opt/appwrite:/usr/src/code/appwrite:rw \
    --entrypoint="install" \
    appwrite/appwrite:1.9.5 \
    --http-port 80 --https-port 443 --interactive=n --no-start

if [ -z "$MYIP" ]; then
    MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
fi

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
    APP_DOMAIN="${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}"
    APP_DOMAIN="${MYIP}"
fi

cd /opt/appwrite

set_env() {
    if grep -q "^$1=" .env; then
        sed -i "s|^$1=.*|$1=$2|" .env
    else
        echo "$1=$2" >> .env
    fi
}
set_env _APP_ENV production
set_env _APP_DOMAIN "${APP_DOMAIN}"
set_env _APP_DOMAIN_TARGET_A "${MYIP}"
if [ -n "$EMAIL" ]; then
    set_env _APP_SYSTEM_SECURITY_EMAIL_ADDRESS "${EMAIL}"
fi

echo -e ${BLU} "Starting Appwrite (this may take a few minutes)..." ${DEF}
docker compose up -d

echo -e ${BLU} "Waiting for Appwrite to become ready..." ${DEF}
for i in $(seq 1 36); do
    curl -s -o /dev/null http://127.0.0.1:80 && break
    sleep 5
done

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   APPWRITE INSTALLATION COMPLETE                       ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Complete setup at the URL above.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Appwrite - Backend as a Service
================================

Access: ${ACCESS_URL}

First-time setup:
  Open the URL above and create your admin account immediately -
  the first visitor to the console can register as administrator.

Manage Appwrite:
  cd /opt/appwrite
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart

Configuration: /opt/appwrite/.env
  Apply changes with: cd /opt/appwrite && docker compose up -d

Documentation: https://appwrite.io/docs

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
