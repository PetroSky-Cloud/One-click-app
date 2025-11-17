#!/bin/bash


apt-get update
apt-get install -y wget bash curl net-tools

wget -O /etc/profile.d/install.sh  -q  https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/nextcloud.sh

curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/init/setpassword.sh | bash
