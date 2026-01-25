#!/bin/bash

curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/docker.sh | bash

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
echo


printf "%s" "Please enter Domain Name, or hit enter for insecure installation: "
read DOMAIN
echo $fullname


if [ "$DOMAIN" = "" ]; then
    echo "installing without certificates and proper TLS termination"
else
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/caddy.sh | bash -s -- $DOMAIN 8000 false
fi


docker run -it --rm \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    --volume "$(pwd)"/appwrite:/usr/src/code/appwrite:rw \
    --entrypoint="install" \
    appwrite/appwrite:1.8.0


rm -f /etc/profile.d/install.sh
