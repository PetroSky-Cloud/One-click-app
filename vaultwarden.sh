#!/bin/bash

apt-get update
apt-get -qqq -y install curl uuid-runtime net-tools

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

printf "%s" "Please enter Domain Name, or hit enter for insecure installation: "
read DOMAIN

echo -e ${DEF}

if [ "$DOMAIN" = "" ]; then
    echo "installing without certificates and proper TLS termination"
else
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/caddy.sh | bash -s -- $DOMAIN 8000 false
fi

curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/docker.sh | bash

mkdir /opt/vaultwarden
cd /opt/vaultwarden


docker pull vaultwarden/server:latest
docker run --detach --name vaultwarden \
  --env DOMAIN="https://${DOMAIN}" \
  --volume /vw-data/:/data/ \
  --restart unless-stopped \
  --publish 127.0.0.1:8000:80 \
  vaultwarden/server:latest

echo
echo -e ${BLU}
echo Sleeping 1 minute to let the containers to come up
echo -e ${YEL}
sleep 1m
echo "You can now logint to https://{DOMAIN}"
echo -e ${DEF}
echo
