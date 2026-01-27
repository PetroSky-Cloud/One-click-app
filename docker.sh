#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e "${BLU} Please wait preparing the initial setup ${DEF}"
apt-get remove --purge docker.io docker-doc docker-compose podman-docker containerd runc > /dev/null  2>&1

sudo apt-get update > /dev/null  2>&1
sudo apt-get install -y ca-certificates curl > /dev/null  2>&1
sudo install -m 0755 -d /etc/apt/keyrings > /dev/null  2>&1

if grep -qio id=debian /etc/os-release ; then
    echo -e ${BLU} "Debian Detected" ${DEF}
    echo -e ${GRN} "Add Docker's official GPG key:" ${DEF}
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo -e ${GRN} "Add the repository to Apt sources:" ${DEF}
    cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
elif grep -qio id=ubuntu /etc/os-release ; then
    echo -e ${BLU} "Ubuntu Detected" ${DEF}
    echo -e ${GRN} "Add Docker's official GPG key:" ${DEF}
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo -e ${GRN} "Add the repository to Apt sources:" ${DEF}
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" > /etc/apt/sources.list.d/docker.list
else
    echo "Unsupported OS"
    exit 2
fi


apt-get update > /dev/null  2>&1
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin  -y > /dev/null  2>&1

echo -e ${BLU} Docker is installed succesfully ${DEF}
