#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl net-tools > /dev/null 2>&1

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO FLOWISE INSTALL SCRIPT                            ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

printf "%s" "Please enter Domain Name, or hit enter for insecure installation: "
read DOMAIN

echo -e ${DEF}

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

echo -e ${BLU} "Creating Flowise directories..." ${DEF}
mkdir -p /opt/flowise

echo -e ${BLU} "Generating secrets..." ${DEF}
FLOWISE_PASSWORD=$(openssl rand -base64 12 | tr -d /=+ | head -c 12)
FLOWISE_SECRETKEY_OVERWRITE=$(openssl rand -hex 16)
PASSPHRASE=$(openssl rand -hex 16)

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
      - FLOWISE_USERNAME=admin
      - FLOWISE_PASSWORD=${FLOWISE_PASSWORD}
      - FLOWISE_SECRETKEY_OVERWRITE=${FLOWISE_SECRETKEY_OVERWRITE}
      - PASSPHRASE=${PASSPHRASE}
      - DEBUG=false
      - LOG_LEVEL=info
    command: /bin/sh -c "sleep 3; flowise start"

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

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:3000"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   FLOWISE INSTALLATION COMPLETE                        ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Login Credentials:${DEF}"
echo -e "${BLU}    Username: admin${DEF}"
echo -e "${BLU}    Password: ${FLOWISE_PASSWORD}${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Flowise - LLM Workflow Builder
==============================

Access: ${ACCESS_URL}

Login Credentials:
  Username: admin
  Password: ${FLOWISE_PASSWORD}

Quick Start:
  1. Log in with credentials above
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
