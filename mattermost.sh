#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl net-tools bind9-host postgresql-common git sudo ca-certificates uuid-runtime moreutils jq > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO MATTERMOST INSTALL SCRIPT                          ${GRN}#"
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

if [ -n "$DOMAIN" ]; then
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8065 false
fi

echo -e ${BLU} "Setting up PostgreSQL repository..." ${DEF}
/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh yes 2>/dev/null || true

install -d /usr/share/postgresql-common/pgdg
curl -so /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
. /etc/os-release
sh -c "echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $VERSION_CODENAME-pgdg main' > /etc/apt/sources.list.d/pgdg.list"

apt-get update -qq
apt-get -qqq -y install postgresql-16 > /dev/null 2>&1

PGUSER=mmuser
PGPASS=$(uuidgen)

cat > /tmp/user.sql <<-EOF
CREATE DATABASE mattermost WITH ENCODING 'UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8' TEMPLATE=template0;
CREATE USER ${PGUSER} WITH PASSWORD '${PGPASS}';
GRANT ALL PRIVILEGES ON DATABASE mattermost TO ${PGUSER};
GRANT CREATE ON SCHEMA public TO ${PGUSER};
GRANT ALL ON SCHEMA public TO ${PGUSER};
ALTER ROLE ${PGUSER} WITH SUPERUSER;
EOF

sudo -u postgres psql -f /tmp/user.sql > /dev/null 2>&1
rm /tmp/user.sql

systemctl restart postgresql

echo -e ${BLU} "Installing Mattermost..." ${DEF}
curl -so- https://deb.packages.mattermost.com/repo-setup.sh | bash -s mattermost > /dev/null 2>&1
apt-get update -qq
apt-get -qqq -y install mattermost > /dev/null 2>&1

jq '.SqlSettings.DataSource = "postgres://UUSSEERR:PPAASSWW@localhost/mattermost?sslmode=disable&connect_timeout=10&binary_parameters=yes"' /opt/mattermost/config/config.defaults.json \
| sed -e s/UUSSEERR:PPAASSWW/mmuser:${PGPASS}/g > /opt/mattermost/config/config.json

chmod 600 /opt/mattermost/config/config.json
mkdir -p /opt/mattermost/data
chown -R mattermost:mattermost /opt/mattermost/data
chown -R mattermost:mattermost /opt/mattermost/config/config.json

systemctl restart mattermost.service

sleep 10

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:8065"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                  MATTERMOST INSTALLATION COMPLETE                      ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Create your admin account on first visit.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Mattermost - Team Messaging Platform
=====================================

Access: ${ACCESS_URL}

First-time setup:
  1. Open the URL above
  2. Create your admin account
  3. Create or join a team
  4. Invite team members

Features:
  - Channels and direct messages
  - File sharing
  - Audio/video calls (with plugins)
  - Integrations (Slack-compatible webhooks)
  - Mobile apps (iOS/Android)
  - Desktop apps

Database:
  Host: localhost
  Database: mattermost
  User: ${PGUSER}
  Password: ${PGPASS}

Manage Mattermost:
  systemctl status mattermost     # Check status
  systemctl restart mattermost    # Restart
  journalctl -u mattermost -f     # View logs

Configuration: /opt/mattermost/config/config.json
Data: /opt/mattermost/data

Update Mattermost:
  apt update && apt upgrade mattermost

Documentation: https://docs.mattermost.com/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
