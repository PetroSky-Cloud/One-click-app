#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl net-tools bind9-host uuid-runtime git sudo ca-certificates > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO UMAMI INSTALL SCRIPT                               ${GRN}#"
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

echo -e ${BLU} "Installing PostgreSQL..." ${DEF}
apt-get install -y postgresql-common > /dev/null 2>&1

install -d /usr/share/postgresql-common/pgdg
curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
. /etc/os-release
sh -c "echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $VERSION_CODENAME-pgdg main' > /etc/apt/sources.list.d/pgdg.list"

apt-get update -qq
apt-get -y install postgresql-16 > /dev/null 2>&1

PGUSER=umami
PGPASS=$(uuidgen)

cat > /tmp/user.sql <<-EOF
CREATE DATABASE umami;
CREATE USER ${PGUSER} WITH ENCRYPTED PASSWORD '${PGPASS}';
GRANT ALL PRIVILEGES ON DATABASE umami TO ${PGUSER};
GRANT CREATE ON SCHEMA public TO ${PGUSER};
GRANT ALL ON SCHEMA public TO ${PGUSER};
ALTER ROLE ${PGUSER} WITH SUPERUSER;
EOF

sudo -u postgres psql -f /tmp/user.sql
rm /tmp/user.sql

echo -e ${BLU} "Installing Node.js..." ${DEF}
cd /opt
NODE_VERSION=$(curl -s https://nodejs.org/dist/index.json | grep -o '"version":"v[0-9.]*"' | head -1 | grep -o 'v[0-9.]*')
wget -q https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz
tar -xf node-${NODE_VERSION}-linux-x64.tar.xz
rm node-${NODE_VERSION}-linux-x64.tar.xz
ln -sf node-${NODE_VERSION}-linux-x64 node
echo 'PATH=$PATH:/opt/node/bin/' >> /etc/profile
PATH=$PATH:/opt/node/bin/
npm install -g pnpm

echo -e ${BLU} "Building Umami from source..." ${DEF}
cd /opt
git clone https://github.com/umami-software/umami.git
cd umami

cat > .env <<-EOF
DATABASE_URL=postgresql://${PGUSER}:${PGPASS}@localhost:5432/umami
EOF

pnpm install
pnpm build
npm install -g pm2
pm2 start pnpm --name umami -- start
pm2 startup
pm2 save

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 3000 false
fi

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:3000"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   UMAMI INSTALLATION COMPLETE                          ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Default credentials:${DEF}"
echo -e "${YEL}    Username: ${GRN}admin${DEF}"
echo -e "${YEL}    Password: ${GRN}umami${DEF}"
echo
echo -e "${BLU}  Change your password immediately after first login.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Umami - Website Analytics
=========================

Access: ${ACCESS_URL}

Default credentials:
  Username: admin
  Password: umami

First-time setup:
  1. Open the URL above
  2. Login with default credentials
  3. Change admin password immediately
  4. Add your website to start tracking

Manage Umami:
  pm2 status                    # Check status
  pm2 logs umami                # View logs
  pm2 restart umami             # Restart
  cd /opt/umami && git pull && pnpm install && pnpm build && pm2 restart umami  # Update

Database: PostgreSQL 16
  User: ${PGUSER}
  Database: umami

Configuration: /opt/umami/.env

Documentation: https://umami.is/docs

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
