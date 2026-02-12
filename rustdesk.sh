#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl net-tools > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO RUSTDESK SERVER INSTALL SCRIPT                      ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e "${BLU}  RustDesk is a self-hosted remote desktop server.${DEF}"
echo -e "${BLU}  No domain or web interface needed - clients connect${DEF}"
echo -e "${BLU}  directly using your server IP and encryption key.${DEF}"
echo

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

echo -e ${BLU} "Setting up RustDesk server..." ${DEF}
mkdir -p /opt/rustdesk
cd /opt/rustdesk

cat > /opt/rustdesk/docker-compose.yml << EOF
services:
  rustdesk-server:
    container_name: rustdesk-server
    image: rustdesk/rustdesk-server-s6:latest
    network_mode: "host"
    environment:
      - RELAY=${MYIP}:21117
      - ENCRYPTED_ONLY=1
    volumes:
      - ./data:/data
    restart: unless-stopped
EOF

echo -e ${BLU} "Pulling and starting RustDesk server..." ${DEF}
docker compose pull
docker compose up -d

echo -e ${BLU} "Waiting for RustDesk server to start..." ${DEF}
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if docker ps --format '{{.Names}}' | grep -q "rustdesk-server"; then
        HEALTH=$(docker inspect --format='{{.State.Health.Status}}' rustdesk-server 2>/dev/null || echo "none")
        if [ "$HEALTH" = "healthy" ]; then
            echo -e "${GRN}RustDesk server is running!${DEF}"
            break
        fi
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -e "${BLU}  Still waiting... (${ELAPSED}s)${DEF}"
done

if ! docker ps --format '{{.Names}}' | grep -q "rustdesk-server"; then
    echo -e "${RED}WARNING: RustDesk container may not have started.${DEF}"
    echo -e "${YEL}Check: cd /opt/rustdesk && docker compose logs${DEF}"
fi

echo -e ${BLU} "Waiting for encryption key generation..." ${DEF}
PUBLIC_KEY=""
KEY_WAIT=0
while [ $KEY_WAIT -lt 30 ]; do
    if [ -f /opt/rustdesk/data/id_ed25519.pub ]; then
        PUBLIC_KEY=$(cat /opt/rustdesk/data/id_ed25519.pub)
        if [ -n "$PUBLIC_KEY" ]; then
            echo -e "${GRN}Encryption key generated!${DEF}"
            break
        fi
    fi
    sleep 2
    KEY_WAIT=$((KEY_WAIT + 2))
done

if [ -z "$PUBLIC_KEY" ]; then
    echo -e "${RED}WARNING: Could not read public key. Check /opt/rustdesk/data/${DEF}"
    PUBLIC_KEY="(key not yet generated - check /opt/rustdesk/data/id_ed25519.pub)"
fi

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}              RUSTDESK SERVER INSTALLATION COMPLETE                     ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  SERVER IP:   ${GRN}${MYIP}${DEF}"
echo
echo -e "${YEL}  PUBLIC KEY:  ${GRN}${PUBLIC_KEY}${DEF}"
echo
echo -e "${BLU}  CLIENT SETUP:${DEF}"
echo -e "${BLU}    1. Open RustDesk client on your computer/phone${DEF}"
echo -e "${BLU}    2. Click the menu (three dots) > Network${DEF}"
echo -e "${BLU}    3. Unlock Network Settings${DEF}"
echo -e "${BLU}    4. Set ID Server to: ${GRN}${MYIP}${DEF}"
echo -e "${BLU}    5. Set Key to: ${GRN}${PUBLIC_KEY}${DEF}"
echo -e "${BLU}    6. Click Apply and restart RustDesk${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
RustDesk Server - Self-Hosted Remote Desktop
=============================================

Server IP: ${MYIP}
Public Key: ${PUBLIC_KEY}

Client Setup (Desktop - Windows/Mac/Linux):
  1. Download RustDesk from https://rustdesk.com
  2. Open RustDesk
  3. Click the menu (three dots) next to your ID
  4. Go to Network > Unlock Network Settings
  5. Set "ID Server" to: ${MYIP}
  6. Set "Key" to: ${PUBLIC_KEY}
  7. Leave "Relay Server" empty (auto-detected)
  8. Click Apply and restart RustDesk

Client Setup (Mobile - iOS/Android):
  1. Install RustDesk from App Store / Play Store
  2. Open RustDesk
  3. Tap the menu icon > Settings > Network
  4. Set "ID Server" to: ${MYIP}
  5. Set "Key" to: ${PUBLIC_KEY}
  6. Save and restart the app

Security:
  - All connections are encrypted (Ed25519 + NaCl)
  - Only clients with the correct public key can connect
  - P2P connections when possible, relay through your server otherwise

Ports Used:
  - 21115/tcp: NAT type test
  - 21116/tcp+udp: ID registration, heartbeat, hole punching
  - 21117/tcp: Relay connections
  - 21118/tcp: WebSocket (web client)
  - 21119/tcp: WebSocket relay (web client)

Manage RustDesk Server:
  cd /opt/rustdesk
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

View Public Key:
  cat /opt/rustdesk/data/id_ed25519.pub

Backup (IMPORTANT - if keys are lost, all clients must be reconfigured):
  cp -r /opt/rustdesk/data /root/rustdesk-backup

Data Directory: /opt/rustdesk/data
  - id_ed25519      : Server private key (keep secure!)
  - id_ed25519.pub  : Server public key (distribute to clients)
  - db_v2.sqlite3   : Peer registration database

Documentation: https://rustdesk.com/docs

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
