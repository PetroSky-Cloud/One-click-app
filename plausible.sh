#!/bin/bash

apt-get update
apt-get -y install git bind9-host -y

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

curl -s https://netangels.net/utils/docker.sh | bash

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

rm -f /etc/profile.d/plausible.sh
