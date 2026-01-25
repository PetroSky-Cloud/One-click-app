#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e "${BLU} Please wait preparing the initial setup ${DEF}"

apt update > /dev/null  2>&1
apt -qqq -y install curl uuid-runtime net-tools unzip > /dev/null  2>&1

clear

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO OUR INSTALL SCRIPT, PLEASE ANSWER TO FEW QUESTIONS ${GRN}#"
echo -e ${GRN}  "# ------------------------------------------------------------- #"
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

if [ "$DOMAIN" = "" ]; then
    echo "installing without certificates and proper TLS termination"
else
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8443 true
fi

curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

mkdir /opt/jitsi
cd /opt/jitsi

wget -q -O jistsi.zip $(wget -q -O - https://api.github.com/repos/jitsi/docker-jitsi-meet/releases/latest | grep zip | cut -d\" -f4)
unzip -q jistsi.zip
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

./gen-passwords.sh
mkdir -p ~/.jitsi-meet-cfg/{web,transcripts,prosody/config,prosody/prosody-plugins-custom,jicofo,jvb,jigasi,jibri}

docker compose -f docker-compose.yml -f jigasi.yml up -d

echo
echo -e ${BLU}
echo Sleeping 1 minute to let the containers to come up
echo -e ${YEL}
sleep 1m
echo "You can now logint to https://${DOMAIN}"
echo -e ${DEF}
echo

rm /etc/profile.d/install.sh
