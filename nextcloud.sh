#!/bin/bash

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
echo -e ${DEF}

printf "%s" "Please enter Domain Name, or hit enter for insecure installation: "
read DOMAIN

echo -e ${DEF}

if [ "$DOMAIN" = "" ]; then
    echo "installing without certificates and proper TLS termination"
else
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/caddy.sh | bash -s -- $DOMAIN 11000 false
fi

curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/docker.sh | bash

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

rm /etc/profile.d/install.sh
