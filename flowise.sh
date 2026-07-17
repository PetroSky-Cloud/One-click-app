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
echo -e ${GRN} "# ${BLU}WELCOME TO FLOWISE INSTALL SCRIPT                            ${GRN}#"
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

echo -e ${BLU} "Creating Flowise directories..." ${DEF}
mkdir -p /opt/flowise

echo -e ${BLU} "Generating secrets..." ${DEF}
FLOWISE_SECRETKEY_OVERWRITE=$(openssl rand -hex 16)
PASSPHRASE=$(openssl rand -hex 16)
JWT_AUTH_TOKEN_SECRET=$(openssl rand -hex 32)
JWT_REFRESH_TOKEN_SECRET=$(openssl rand -hex 32)
EXPRESS_SESSION_SECRET=$(openssl rand -hex 16)

if [ -z "$MYIP" ]; then
    MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
fi

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:3000"
fi

echo -e ${BLU} "Creating Docker Compose file..." ${DEF}
cat > /opt/flowise/docker-compose.yml << EOFCOMPOSE
services:
  flowise:
    image: flowiseai/flowise:latest
    container_name: flowise
    restart: unless-stopped
    ports:
      - '127.0.0.1:3000:3000'
    volumes:
      - flowise-data:/root/.flowise
    environment:
      - APP_URL=${ACCESS_URL}
      - FLOWISE_SECRETKEY_OVERWRITE=${FLOWISE_SECRETKEY_OVERWRITE}
      - PASSPHRASE=${PASSPHRASE}
      - JWT_AUTH_TOKEN_SECRET=${JWT_AUTH_TOKEN_SECRET}
      - JWT_REFRESH_TOKEN_SECRET=${JWT_REFRESH_TOKEN_SECRET}
      - EXPRESS_SESSION_SECRET=${EXPRESS_SESSION_SECRET}
      - DEBUG=false
      - LOG_LEVEL=info
    entrypoint: /bin/sh
    command:
      - -c
      - sleep 3 && flowise start

volumes:
  flowise-data:
EOFCOMPOSE

if [ "$DOMAIN" = "" ]; then
    echo -e ${GRN} "Installing without TLS - exposing port 3000 directly" ${DEF}
    sed -i "s/127.0.0.1:3000:3000/3000:3000/" /opt/flowise/docker-compose.yml
else
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 3000 false
fi

echo -e ${BLU} "Starting Flowise..." ${DEF}
cd /opt/flowise
docker compose pull
docker compose up -d

sleep 15

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   FLOWISE INSTALLATION COMPLETE                        ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${RED}  IMPORTANT: Open the URL NOW and create the admin account.${DEF}"
echo -e "${RED}  The first visitor to this URL becomes the administrator.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Flowise - LLM Workflow Builder
==============================

Access: ${ACCESS_URL}

IMPORTANT: Flowise has no pre-set credentials. The first visitor to the
URL creates the admin account - do this immediately after install.

Quick Start:
  1. Open the URL and create your admin account
  2. Create a new chatflow
  3. Drag and drop components
  4. Connect to your LLM provider (OpenAI, Anthropic, etc.)
  5. Deploy and embed in your apps

Features:
  - Visual drag-and-drop builder
  - LangChain components
  - RAG (Retrieval Augmented Generation)
  - Custom tools and agents
  - API endpoints for integration
  - Embed widgets for websites

Supported LLM Providers:
  - OpenAI (GPT-4, GPT-3.5)
  - Anthropic (Claude)
  - Azure OpenAI
  - HuggingFace
  - Local models (Ollama)

Manage Flowise:
  cd /opt/flowise
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart service
  docker compose pull && docker compose up -d  # Update

Data Location:
  Docker volume: flowise-data

Documentation: https://docs.flowiseai.com/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
