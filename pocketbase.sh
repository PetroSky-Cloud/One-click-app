#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install unzip wget curl net-tools bind9-host > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO POCKETBASE INSTALL SCRIPT                           ${GRN}#"
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
printf "${YEL}Please enter SUPER USER email: ${DEF}"
read ADMIN_EMAIL
printf "${YEL}Please enter SUPER USER password: ${DEF}"
read ADMIN_PASS

echo -e ${BLU} "Installing PocketBase..." ${DEF}
mkdir -p /opt/pocketbase
cd /opt/pocketbase
PB_VERSION=$(curl -s https://api.github.com/repos/pocketbase/pocketbase/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
wget -qO pocketbase.zip https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip
unzip -o pocketbase.zip
rm -f pocketbase.zip

./pocketbase superuser upsert "$ADMIN_EMAIL" "$ADMIN_PASS"

SERVE_ARGS="--http=0.0.0.0:8090"

cat > /etc/systemd/system/pocketbase.service << 'EOFSVC'
[Unit]
Description=PocketBase
Documentation=https://pocketbase.io/docs
Wants=network-online.target
After=network-online.target

[Service]
WorkingDirectory=/opt/pocketbase/
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/opt/pocketbase/pocketbase serve --http=0.0.0.0:8090
KillMode=process
KillSignal=SIGINT
LimitNOFILE=infinity
LimitNPROC=infinity
Restart=on-failure
RestartSec=2
StartLimitBurst=3
StartLimitIntervalSec=10
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOFSVC

systemctl daemon-reload
systemctl enable pocketbase.service
systemctl restart pocketbase.service

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8090 false
fi

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:8090"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                POCKETBASE INSTALLATION COMPLETE                        ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  DASHBOARD:   ${GRN}${ACCESS_URL}/_/${DEF}"
echo -e "${YEL}  API:         ${GRN}${ACCESS_URL}/api/${DEF}"
echo
echo -e "${BLU}  Admin Email: ${GRN}${ADMIN_EMAIL}${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
PocketBase - Backend as a Service
==================================

Dashboard: ${ACCESS_URL}/_/
API: ${ACCESS_URL}/api/

Admin Email: ${ADMIN_EMAIL}

Manage PocketBase:
  systemctl status pocketbase    # Check status
  systemctl restart pocketbase   # Restart
  journalctl -u pocketbase -f    # View logs

Data: /opt/pocketbase/pb_data
Configuration: /opt/pocketbase/

Update PocketBase:
  cd /opt/pocketbase
  systemctl stop pocketbase
  # Download new version and replace binary
  systemctl start pocketbase

Documentation: https://pocketbase.io/docs

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
