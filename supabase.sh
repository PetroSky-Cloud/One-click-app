#!/bin/bash

sleep 30

apt-get update
apt-get install curl

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

curl -s https://netangels.net/utils/docker.sh | bash

if [ "$DOMAIN" = "" ]; then
    echo "installing without certificates and proper TLS termination"
else
    curl -s https://netangels.net/utils/caddy.sh | bash -s -- $DOMAIN 9001 false
fi

cd /opt
git clone --depth 1 https://github.com/supabase/supabase
mkdir supabase-project
cp -rf supabase/docker/* supabase-project
cp supabase/docker/.env.example supabase-project/.env
cd supabase-project
docker compose pull
docker compose up -d

echo -e ${GRN}
echo Congratulation the installation completed successsfully
echo Open : https://${DOMAIN} in your browser
echo Username: supabase
echo Password: this_password_is_insecure_and_should_be_updated
echo -e ${DEF}


rm -f /etc/profile.d/supabase.sh
