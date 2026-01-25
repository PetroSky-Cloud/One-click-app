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
echo -e ${GRN} "# ${BLU}WELCOME TO BESZEL INSTALL SCRIPT                              ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

printf "%s" "Please enter Domain Name, or hit enter for insecure installation: "
read DOMAIN

echo -e ${DEF}

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

echo -e ${BLU} "Creating Beszel directories..." ${DEF}
mkdir -p /opt/beszel

echo -e ${BLU} "Creating Docker Compose file..." ${DEF}
cat > /opt/beszel/docker-compose.yml << 'EOFCOMPOSE'
services:
  beszel:
    image: henrygd/beszel:latest
    container_name: beszel
    restart: unless-stopped
    ports:
      - "127.0.0.1:8090:8090"
    volumes:
      - ./data:/beszel_data

  beszel-agent:
    image: henrygd/beszel-agent:latest
    container_name: beszel-agent
    restart: unless-stopped
    network_mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - PORT=45876
      - KEY=
EOFCOMPOSE

if [ "$DOMAIN" = "" ]; then
    echo -e ${GRN} "Installing without TLS - exposing port 8090 directly" ${DEF}
    sed -i "s/127.0.0.1:8090:8090/8090:8090/" /opt/beszel/docker-compose.yml
else
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8090 false
fi

echo -e ${BLU} "Starting Beszel Hub..." ${DEF}
cd /opt/beszel
docker compose up -d beszel

sleep 10

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:8090"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                    BESZEL INSTALLATION COMPLETE                        ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  1. Create admin account at the URL above${DEF}"
echo -e "${BLU}  2. Add this server: click 'Add System' and copy the agent key${DEF}"
echo -e "${BLU}  3. Edit /opt/beszel/docker-compose.yml, add KEY= value${DEF}"
echo -e "${BLU}  4. Run: cd /opt/beszel && docker compose up -d beszel-agent${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Beszel - Lightweight Server Monitoring
======================================

Access: ${ACCESS_URL}

Setup Steps:
  1. Open URL and create admin account
  2. Click "Add System" to add this server
  3. Copy the agent KEY from the dialog
  4. Edit /opt/beszel/docker-compose.yml
     - Add the KEY value to beszel-agent service
  5. Start agent: cd /opt/beszel && docker compose up -d beszel-agent

Features:
  - CPU, Memory, Disk monitoring
  - Docker container stats
  - Network usage
  - Temperature sensors
  - Configurable alerts

Manage Beszel:
  cd /opt/beszel
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Agent Port: 45876 (allow in firewall for remote agents)

Documentation: https://beszel.dev/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
