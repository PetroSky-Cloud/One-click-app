#!/bin/bash

apt-get update
apt-get -y install git bind9-host -y

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

clear

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

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

MYIP=`curl https://ipv4.icanhazip.com`

while : ; do
    if host $DOMAIN 1.1.1.1| grep $MYIP ; then
        echo CloudFlare Matched!
        break
    else
        echo CloudFlare: $DOMAIN not match $MYIP
        sleep 5
    fi
    if host $DOMAIN 8.8.8.8| grep $MYIP ; then
        echo Google Matched !
        break
    else
        echo Google    : $DOMAIN not match $MYIP
        sleep 5
    fi
    if host $DOMAIN| grep $MYIP ; then
        echo Local     : $DOMAIN not match $MYIP
        break
    else
        echo Local $DOMAIN not match $MYIP
        sleep 5
    fi
done

curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

cd /opt
git clone -b v3.0.1 --single-branch https://github.com/plausible/community-edition plausible-ce
cd plausible-ce

touch .env
echo "BASE_URL=https://${DOMAIN}" >> .env
echo "SECRET_KEY_BASE=$(openssl rand -base64 48)" >> .env

echo "HTTP_PORT=80" >> .env
echo "HTTPS_PORT=443" >> .env

cat > compose.override.yml << EOF
services:
  plausible:
    ports:
      - 80:80
      - 443:443
EOF

docker compose up -d

echo
echo -e ${BLU}
echo Sleeping 1 minute to let the containers to come up
echo -e ${DEF}
sleep 1m
echo

echo -e ${GRN}
echo Congratulation the installation completed successsfully
echo Open : https://${DOMAIN} in your browser
echo -e ${DEF}

rm -f /etc/profile.d/install.sh
