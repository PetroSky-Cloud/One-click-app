#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl uuid-runtime net-tools unzip bind9-host > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO JITSI MEET INSTALL SCRIPT                          ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

while true; do
    echo
    printf "${YEL}Please enter Domain Name (REQUIRED for Jitsi): ${DEF}"
    read DOMAIN

    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}Jitsi Meet requires a domain for WebRTC to work properly.${DEF}"
        echo -e "${YEL}Please enter a domain or press Ctrl+C to cancel.${DEF}"
        continue
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
    fi
done

echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8443 true

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

mkdir -p /opt/jitsi
cd /opt/jitsi

echo -e ${BLU} "Downloading Jitsi Docker Compose..." ${DEF}
wget -q -O jitsi.zip $(wget -q -O - https://api.github.com/repos/jitsi/docker-jitsi-meet/releases/latest | grep zip | cut -d\" -f4)
unzip -q jitsi.zip
cd jitsi-docker-jitsi-meet*

cat > .env <<- EOF
CONFIG=~/.jitsi-meet-cfg
HTTP_PORT=8000
HTTPS_PORT=8443
PUBLIC_URL=https://${DOMAIN}:443
JIBRI_RECORDER_PASSWORD=
JIBRI_XMPP_PASSWORD=
JICOFO_AUTH_PASSWORD=
JIGASI_TRANSCRIBER_PASSWORD=
JIGASI_XMPP_PASSWORD=
JVB_AUTH_PASSWORD=
TZ=UTC
ENABLE_XMPP_WEBSOCKET=1
EOF

echo -e ${BLU} "Generating passwords..." ${DEF}
./gen-passwords.sh
mkdir -p ~/.jitsi-meet-cfg/{web,transcripts,prosody/config,prosody/prosody-plugins-custom,jicofo,jvb,jigasi,jibri}

echo -e ${BLU} "Starting Jitsi Meet..." ${DEF}
docker compose -f docker-compose.yml -f jigasi.yml up -d

echo
echo -e ${BLU} "Waiting for containers to start..." ${DEF}
sleep 60

ACCESS_URL="https://${DOMAIN}"

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                  JITSI MEET INSTALLATION COMPLETE                      ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Start a meeting by visiting the URL above.${DEF}"
echo -e "${BLU}  No account required - just enter a room name!${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Jitsi Meet - Video Conferencing
================================

Access: ${ACCESS_URL}

Usage:
  1. Open the URL above
  2. Enter a room name (or generate one)
  3. Share the room link with participants
  4. No account required!

Features:
  - HD video and audio
  - Screen sharing
  - Chat messaging
  - Recording (requires Jibri)
  - Live streaming
  - Password protection for rooms
  - Lobby/waiting room
  - Raise hand feature

Mobile Apps:
  - iOS: Jitsi Meet on App Store
  - Android: Jitsi Meet on Play Store

Configuration:
  /opt/jitsi/jitsi-docker-jitsi-meet*/.env

Manage Jitsi:
  cd /opt/jitsi/jitsi-docker-jitsi-meet*
  docker compose ps                    # Check status
  docker compose logs -f               # View logs
  docker compose restart               # Restart
  docker compose pull && docker compose up -d  # Update

Enable Recording (Jibri):
  Edit .env and configure JIBRI settings
  Then: docker compose -f docker-compose.yml -f jibri.yml up -d

Documentation: https://jitsi.github.io/handbook/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
