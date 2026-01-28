#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl uuid-runtime net-tools bind9-host > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO OUR INSTALL SCRIPT, PLEASE ANSWER TO FEW QUESTIONS ${GRN}#"
echo -e ${GRN}  "# ------------------------------------------------------------- #"
echo
echo -e ${DEF}

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
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 11000 false
fi

curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

mkdir -p /etc/systemd/system/docker.service.d/
cat > /etc/systemd/system/docker.service.d/override.conf <<-EOF
[Service]
Environment=DOCKER_MIN_API_VERSION=1.24
EOF

systemctl  daemon-reload
systemctl  restart  docker.service

sudo docker run -d \
    --init \
    --sig-proxy=false \
    --name nextcloud-aio-mastercontainer \
    --restart always \
    --publish 8080:8080 \
    --env APACHE_PORT=11000 \
    --env APACHE_IP_BINDING=0.0.0.0 \
    --env APACHE_ADDITIONAL_NETWORK="" \
    --env SKIP_DOMAIN_VALIDATION=true \
    --volume nextcloud_aio_mastercontainer:/mnt/docker-aio-config \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
ghcr.io/nextcloud-releases/all-in-one:latest

sleep 20

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
    AIO_URL="https://${MYIP}:8080"
else
    ACCESS_URL="http://${MYIP}:11000"
    AIO_URL="https://${MYIP}:8080"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                  NEXTCLOUD INSTALLATION COMPLETE                       ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  AIO ADMIN:   ${GRN}${AIO_URL}${DEF}"
echo -e "${YEL}  NEXTCLOUD:   ${GRN}${ACCESS_URL}${DEF} (after AIO setup)"
echo
echo -e "${BLU}  1. Open the AIO admin URL above${DEF}"
echo -e "${BLU}  2. Accept the self-signed certificate warning${DEF}"
echo -e "${BLU}  3. Follow the setup wizard${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Nextcloud All-in-One
====================

AIO Admin Panel: ${AIO_URL}
  (Accept the self-signed certificate warning)

After AIO Setup: ${ACCESS_URL}

First-time setup:
  1. Open the AIO Admin URL above
  2. Accept the self-signed certificate warning
  3. Copy the initial password shown
  4. Follow the setup wizard to configure Nextcloud
  5. Set your domain and start containers

Features:
  - File sync and sharing
  - Office document editing (Collabora/OnlyOffice)
  - Calendar and contacts
  - Talk (video calls)
  - Photos with AI recognition
  - Automatic backups

Manage Nextcloud AIO:
  Access the AIO admin panel to:
  - Start/stop/update containers
  - Configure optional features
  - Create backups
  - View logs

Docker Management:
  docker ps                      # Check containers
  docker logs nextcloud-aio-mastercontainer -f  # AIO logs

Data Location:
  Docker volumes (managed by AIO)

Documentation: https://github.com/nextcloud/all-in-one

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
