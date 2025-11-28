#!/bin/bash

apt update
apt install -y wget bash curl net-tools

wget -O /etc/profile.d/install.sh  -q  https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/mattermost.sh
