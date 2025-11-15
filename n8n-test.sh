#!/bin/bash

apt-get update
apt-get install -y wget

wget -O /etc/profile.d/install.sh  -q  https://netangels.net/utils/n8n.sh
