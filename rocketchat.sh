#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e "${BLU}Please wait preparing the initial setup${DEF}"

apt-get update > /dev/null 2>&1
apt-get -qqq -y install curl uuid-runtime net-tools unzip bind9-host git > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO ROCKET.CHAT INSTALL SCRIPT                          ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

while true; do
    echo
    printf "${YEL}Please enter Domain Name, or hit enter for insecure installation: ${DEF}"
    read DOMAIN

    if [ -z "$DOMAIN" ]; then
        echo -e "${GRN}Proceeding without TLS (HTTP only)${DEF}"
        break
    fi

    echo -e "${BLU}Checking DNS for ${DOMAIN}...${DEF}"

    if validate_domain "$DOMAIN"; then
        RESOLVED_IP=$(host "$DOMAIN" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
        if [ "$RESOLVED_IP" = "$MYIP" ]; then
            echo -e "${GRN}DNS verified: ${DOMAIN} -> ${MYIP} (direct)${DEF}"
        else
            echo -e "${GRN}DNS verified: ${DOMAIN} -> ${RESOLVED_IP} (CDN/proxy)${DEF}"
        fi
        break
    else
        echo -e "${RED}ERROR: Domain '${DOMAIN}' does not resolve to any IP address.${DEF}"
        echo -e "${YEL}Please ensure DNS is configured correctly, then try again.${DEF}"
        echo -e "${YEL}Or press Enter to skip TLS and use HTTP only.${DEF}"
    fi
done

echo
printf "${YEL}Please enter your e-mail address: ${DEF}"
read EMAIL
printf "${YEL}Please enter password for Grafana: ${DEF}"
read GRAFANA_PASS

echo -e ${DEF}

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8000 false
fi

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

cd /opt
git clone --depth 1 https://github.com/RocketChat/rocketchat-compose.git
cd rocketchat-compose

if [ -z "$MYIP" ]; then
    MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
fi

# Traefik routes by Host header - with no domain, route by the server IP
if [ -n "$DOMAIN" ]; then
    TRAEFIK_DOMAIN="${DOMAIN}"
    ROOT_URL="https://${DOMAIN}"
else
    TRAEFIK_DOMAIN="${MYIP}"
    ROOT_URL="http://${MYIP}:8000"
fi

cat > .env <<- EOF
# Change these
REG_TOKEN=
DOMAIN=${TRAEFIK_DOMAIN}
ROOT_URL=${ROOT_URL}
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

GRAFANA_ADMIN_PASSWORD=${GRAFANA_PASS}
GRAFANA_HOST_PORT=5050

# Traefik ports
TRAEFIK_HTTP_PORT=8000
TRAEFIK_DASHBOARD_PORT=8080
TRAEFIK_HTTPS_PORT=8443

# Rocket.Chat and metrics ports stay local - traefik handles external traffic
BIND_IP=127.0.0.1

# MongoDB
MONGODB_BIND_IP=127.0.0.1
MONGODB_PORT_NUMBER=27017
EOF

docker compose -f compose.database.yml -f compose.monitoring.yml -f compose.traefik.yml -f compose.yml up -d

echo
echo -e ${BLU} "Waiting for containers to start..." ${DEF}
sleep 60

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:8000"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}               ROCKET.CHAT INSTALLATION COMPLETE                        ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Complete the setup wizard on first visit.${DEF}"
echo -e "${BLU}  Grafana: ${GRN}http://${MYIP}:5050${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Rocket.Chat - Team Communication
==================================

Access: ${ACCESS_URL}

Grafana: http://${MYIP}:5050
  Username: admin
  Password: ${GRAFANA_PASS}

First-time setup:
  1. Open the URL above
  2. Complete the setup wizard
  3. Create your admin account

Manage Rocket.Chat:
  cd /opt/rocketchat-compose
  docker compose -f compose.database.yml -f compose.monitoring.yml -f compose.traefik.yml -f compose.yml ps
  docker compose -f compose.database.yml -f compose.monitoring.yml -f compose.traefik.yml -f compose.yml logs -f
  docker compose -f compose.database.yml -f compose.monitoring.yml -f compose.traefik.yml -f compose.yml restart

Configuration: /opt/rocketchat-compose/.env

Documentation: https://docs.rocket.chat/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
