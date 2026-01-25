#!/bin/bash

echo -e "${BLU} Please wait preparing the initial setup ${DEF}"

apt-get update > /dev/null  2>&1
apt-get -qqq -y install curl uuid-runtime net-tools unzip > /dev/null  2>&1

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
printf "%s" "Please enter your e-mail address: "
read EMAIL
printf "%s" "Please enter password for Grafana: "
read GRAFANA_PASS

echo -e ${DEF}

if [ "$DOMAIN" = "" ]; then
    echo "installing without certificates and proper TLS termination"
else
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/caddy.sh | bash -s -- $DOMAIN 8000 false
fi

curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/docker.sh | bash

cd /opt
git clone --depth 1 https://github.com/RocketChat/rocketchat-compose.git
cd rocketchat-compose
cat > .env <<- EOF
#!/bin/sh

# Change these
REG_TOKEN=
DOMAIN=${DOMAIN}
ROOT_URL=http://${DOMAIN}
RELEASE=latest
# Change to true after you set your domain and valid lets encrypt email
LETSENCRYPT_ENABLED=false
LETSENCRYPT_EMAIL=${EMAIL}
TRAEFIK_PROTOCOL=http

# Prometheus
PROMETHEUS_RETENTION_SIZE=15GB
PROMETHEUS_RETENTION_TIME=15d
# default prometheus port (9090) conflicts with cockpit in centos
PROMETHEUS_PORT=9000
# Grafana
# Set to empty string to use a subpath
GRAFANA_DOMAIN=
# set to /grafana to use from a subpath
GRAFANA_PATH=/grafana

#GRAFANA_ADMIN_PASSWORD=rc-admin
GRAFANA_ADMIN_PASSWORD=${GRAFANA_PASS}
GRAFANA_HOST_PORT=5050

# Traefik ports
TRAEFIK_HTTP_PORT=8000
TRAEFIK_DASHBOARD_PORT=8080
TRAEFIK_HTTPS_PORT=8443
# Port for Grafana to be accessed externally
GRAFANA_HOST_PORT=5050

# MongoDB
MONGODB_BIND_IP=127.0.0.1
MONGODB_PORT_NUMBER=27017
EOF

docker compose -f compose.database.yml -f compose.monitoring.yml -f compose.traefik.yml -f compose.yml up -d

echo
echo -e ${BLU}
echo Sleeping 1 minute to let the containers to come up
echo -e ${YEL}
sleep 1m
echo "You can now logint to https://${DOMAIN}"
echo -e ${DEF}
echo

rm /etc/profile.d/install.sh


# Please enter Domain Name, or hit enter for insecure installation: grp.matyan.org
# Please enter your e-mail address: valod@grp.com
# Please enter password for Grafana: Val0d
