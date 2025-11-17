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
printf "%s" "Please enter EMAIL for first user: "
read EMAIL
printf "%s" "Please enter PASSWORD for first user: "
read PASSWORD
printf "%s" "Please enter FULLNAME for first user: "
read FULLNAME

echo -e ${DEF}

if [ "$DOMAIN" = "" ]; then
    echo "installing without certificates and proper TLS termination"
else
    curl -s https://netangels.net/utils/caddy.sh | bash -s -- $DOMAIN 9001 false
fi

curl -s https://netangels.net/utils/docker.sh | bash

mkdir /opt/penpot
cd /opt/penpot
curl -o docker-compose.yaml https://raw.githubusercontent.com/penpot/penpot/main/docker/images/docker-compose.yaml

docker compose -p penpot -f docker-compose.yaml up -d

echo
echo -e ${BLU}
echo Sleeping 1 minute to let the containers to come up
echo -e ${DEF}
sleep 1m
echo

cat > /tmp/createuser.sh <<-EOF
#!/bin/bash
docker exec -ti penpot-penpot-backend-1 python3 manage.py create-profile -e ${EMAIL} -p "${PASSWORD}" -n "${FULLNAME}"
EOF

echo
echo

chmod 755 /tmp/createuser.sh
/tmp/createuser.sh
rm /tmp/createuser.sh
rm -f /etc/profile.d/penpot.sh


echo -e ${GRN}
echo Congratulation the installation completed successsfully
echo Open : https://${DOMAIN} in your browser and login withusername: ${EMAIL} and ${PASSWORD}
echo -e ${DEF}

rm -f /etc/profile.d/install.sh
