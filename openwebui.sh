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
echo -e ${GRN} "# ${BLU}WELCOME TO OPEN WEBUI INSTALL SCRIPT                          ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

printf "%s" "Please enter Domain Name, or hit enter for insecure installation: "
read DOMAIN

echo -e ${DEF}

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/docker.sh | bash

echo -e ${BLU} "Creating Open WebUI directories..." ${DEF}
mkdir -p /opt/openwebui

echo -e ${BLU} "Creating Docker Compose file..." ${DEF}
cat > /opt/openwebui/docker-compose.yml << 'EOFCOMPOSE'
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    ports:
      - '127.0.0.1:3000:8080'
    volumes:
      - open-webui-data:/app/backend/data
    environment:
      - WEBUI_NAME=Open WebUI
      - ENABLE_SIGNUP=true
      - DEFAULT_USER_ROLE=user
      - WEBUI_SECRET_KEY=
    restart: unless-stopped

volumes:
  open-webui-data:
EOFCOMPOSE

# Generate secret key
SECRET_KEY=$(openssl rand -hex 32)
sed -i "s/WEBUI_SECRET_KEY=/WEBUI_SECRET_KEY=${SECRET_KEY}/" /opt/openwebui/docker-compose.yml

if [ "$DOMAIN" = "" ]; then
    echo -e ${GRN} "Installing without TLS - exposing port 3000 directly" ${DEF}
    sed -i "s/127.0.0.1:3000:8080/3000:8080/" /opt/openwebui/docker-compose.yml
else
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/caddy.sh | bash -s -- $DOMAIN 3000 false
fi

echo -e ${BLU} "Starting Open WebUI..." ${DEF}
cd /opt/openwebui
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
echo -e "${GRN}                   OPEN WEBUI INSTALLATION COMPLETE                     ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  First user to register becomes admin.${DEF}"
echo -e "${BLU}  Add your OpenAI/Anthropic API keys in Settings > Connections.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Open WebUI
==========

Access: ${ACCESS_URL}

First-time setup:
  1. Open the URL above
  2. Register your account (first user becomes admin)
  3. Go to Settings > Connections
  4. Add your API keys (OpenAI, Anthropic, etc.)

Supported Providers:
  - OpenAI (GPT-4, GPT-3.5)
  - Anthropic (Claude)
  - Ollama (local models)
  - Any OpenAI-compatible API

Manage Open WebUI:
  cd /opt/openwebui
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart service
  docker compose pull && docker compose up -d  # Update

Data Location:
  Docker volume: open-webui-data

Documentation: https://docs.openwebui.com/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
