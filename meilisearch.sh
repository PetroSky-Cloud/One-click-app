#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install unzip wget curl uuid-runtime net-tools bind9-host > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO MEILISEARCH INSTALL SCRIPT                          ${GRN}#"
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

MASTERKEY=$(uuidgen)-$(uuidgen)

echo -e ${BLU} "Installing Meilisearch..." ${DEF}
useradd -r -s /bin/false -d /opt/meilisearch meilisearch 2>/dev/null || true
mkdir -p /opt/meilisearch/{data,dumps,snapshots}
cd /opt/meilisearch

curl -s https://raw.githubusercontent.com/meilisearch/meilisearch/main/download-latest.sh | bash > /dev/null 2>&1
chown -R meilisearch:meilisearch /opt/meilisearch

cat > config.toml <<-EOF
db_path = "/opt/meilisearch/data"
env = "production"
http_addr = "0.0.0.0:7700"
master_key = "${MASTERKEY}"
http_payload_size_limit = "100 MB"
log_level = "INFO"
dump_dir = "/opt/meilisearch/"
ignore_missing_dump = false
ignore_dump_if_db_exists = false
schedule_snapshot = false
snapshot_dir = "/opt/meilisearch/snapshots"
ignore_missing_snapshot = false
ignore_snapshot_if_db_exists = false
ssl_require_auth = false
ssl_resumption = false
ssl_tickets = false
experimental_enable_metrics = false
experimental_reduce_indexing_memory_usage = false
EOF

cat > /etc/systemd/system/meilisearch.service << 'EOFSVC'
[Unit]
Description=meilisearch
Documentation=https://github.com/meilisearch/meilisearch
Wants=network-online.target
After=network-online.target

[Service]
User=meilisearch
Group=meilisearch
WorkingDirectory=/opt/meilisearch/
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/opt/meilisearch/meilisearch
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
systemctl enable meilisearch.service
systemctl restart meilisearch.service

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 7700 false
fi

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:7700"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                MEILISEARCH INSTALLATION COMPLETE                       ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Master Key:  ${GRN}${MASTERKEY}${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Meilisearch - Search Engine
============================

Access: ${ACCESS_URL}
Master Key: ${MASTERKEY}

Usage:
  All API requests require the master key in the Authorization header:
    curl -H "Authorization: Bearer ${MASTERKEY}" ${ACCESS_URL}/indexes

Manage Meilisearch:
  systemctl status meilisearch    # Check status
  systemctl restart meilisearch   # Restart
  journalctl -u meilisearch -f    # View logs

Configuration: /opt/meilisearch/config.toml
Data: /opt/meilisearch/data

Documentation: https://www.meilisearch.com/docs

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
