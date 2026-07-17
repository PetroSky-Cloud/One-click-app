#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl uuid-runtime net-tools bind9-host git > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO DIFY INSTALL SCRIPT                                ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo

# RAM check
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')
if [ "$TOTAL_RAM_MB" -lt 4096 ]; then
    echo -e "${YEL}  WARNING: Dify recommends at least 4GB RAM.${DEF}"
    echo -e "${YEL}  Detected: ${TOTAL_RAM_MB}MB. Installation may fail or run slowly.${DEF}"
    echo
fi

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

echo -e ${BLU} "Cloning Dify docker setup..." ${DEF}
git clone --depth 1 https://github.com/langgenius/dify.git /opt/dify-repo
cp -r /opt/dify-repo/docker /opt/dify
rm -rf /opt/dify-repo
cd /opt/dify
cp .env.example .env

# Generate credentials
SECRET_KEY=$(uuidgen)$(uuidgen)
SECRET_KEY=$(echo "$SECRET_KEY" | tr -d '-')
INIT_PASSWORD=$(uuidgen | tr -d '-' | head -c 16)

echo -e ${BLU} "Configuring Dify..." ${DEF}

# Set secret key
sed -i "s/^SECRET_KEY=.*/SECRET_KEY=${SECRET_KEY}/" .env

# Set init password for admin setup
sed -i "s/^INIT_PASSWORD=.*/INIT_PASSWORD=${INIT_PASSWORD}/" .env

if [ -n "$DOMAIN" ]; then
    # Domain provided: configure URLs with HTTPS
    sed -i "s|^CONSOLE_API_URL=.*|CONSOLE_API_URL=https://${DOMAIN}|" .env
    sed -i "s|^CONSOLE_WEB_URL=.*|CONSOLE_WEB_URL=https://${DOMAIN}|" .env
    sed -i "s|^SERVICE_API_URL=.*|SERVICE_API_URL=https://${DOMAIN}|" .env
    sed -i "s|^APP_API_URL=.*|APP_API_URL=https://${DOMAIN}|" .env
    sed -i "s|^APP_WEB_URL=.*|APP_WEB_URL=https://${DOMAIN}|" .env

    # Bind Dify nginx to localhost only so Caddy owns 80/443 for TLS
    sed -i "s|^EXPOSE_NGINX_PORT=.*|EXPOSE_NGINX_PORT=127.0.0.1:8080|" .env
    sed -i "s|^EXPOSE_NGINX_SSL_PORT=.*|EXPOSE_NGINX_SSL_PORT=127.0.0.1:8443|" .env

    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8080 false
else
    # No domain: configure URLs with IP
    if [ -z "$MYIP" ]; then
        MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
    fi
    sed -i "s|^CONSOLE_API_URL=.*|CONSOLE_API_URL=http://${MYIP}|" .env
    sed -i "s|^CONSOLE_WEB_URL=.*|CONSOLE_WEB_URL=http://${MYIP}|" .env
    sed -i "s|^SERVICE_API_URL=.*|SERVICE_API_URL=http://${MYIP}|" .env
    sed -i "s|^APP_API_URL=.*|APP_API_URL=http://${MYIP}|" .env
    sed -i "s|^APP_WEB_URL=.*|APP_WEB_URL=http://${MYIP}|" .env
fi

echo -e ${BLU} "Starting Dify (this may take a few minutes)..." ${DEF}
docker compose up -d

NGINX_CHECK_PORT=80
[ -n "$DOMAIN" ] && NGINX_CHECK_PORT=8080
echo -e ${BLU} "Waiting for Dify to become ready..." ${DEF}
for i in $(seq 1 36); do
    curl -s -o /dev/null http://127.0.0.1:${NGINX_CHECK_PORT} && break
    sleep 5
done

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   DIFY INSTALLATION COMPLETE                            ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Initial Admin Password: ${GRN}${INIT_PASSWORD}${DEF}"
echo -e "${BLU}  Use this password when creating the first admin account.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Dify - AI Workflow & LLM App Platform
======================================

Access: ${ACCESS_URL}

Initial Admin Password: ${INIT_PASSWORD}

First-time setup:
  1. Open the URL above
  2. Create your admin account using the initial password
  3. Add your LLM API keys in Settings > Model Providers
  4. Start building AI workflows and apps

Manage Dify:
  cd /opt/dify
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Configuration: /opt/dify/.env

Documentation: https://docs.dify.ai

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
