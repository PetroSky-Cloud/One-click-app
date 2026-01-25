#!/bin/bash

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

if [ "$DOMAIN" = "" ]; then
    echo "installing without certificates and proper TLS termination"
else
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 3000 false
fi

apt-get install -y postgresql-common git sudo curl ca-certificates uuid-runtime -y

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}
/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh  yes

install -d /usr/share/postgresql-common/pgdg
curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
. /etc/os-release
sh -c "echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $VERSION_CODENAME-pgdg main' > /etc/apt/sources.list.d/pgdg.list"

apt-get update
apt-get -y install postgresql-18 git sudo

PGUSER=umami
PGPASS=`uuidgen`

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

cd /opt
NODE_VERSION=$(curl -s https://nodejs.org/dist/index.json | grep -o '"version":"v[0-9.]*"' | head -1 | grep -o 'v[0-9.]*')
wget https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz
tar -xvf node-${NODE_VERSION}-linux-x64.tar.xz
rm node-${NODE_VERSION}-linux-x64.tar.xz
ln -sf node-${NODE_VERSION}-linux-x64 node
echo 'PATH=$PATH:/opt/node/bin/' >> /etc/profile
PATH=$PATH:/opt/node/bin/
npm install -g pnpm

cd /opt
git clone https://github.com/umami-software/umami.git
cd umami
pnpm install

cat > .env <<-EOF
DATABASE_URL=postgresql://${PGUSER}:${PGPASS}@localhost:5432/umami
EOF

pnpm build
npm install -g pm2
pm2 start pnpm --name umami -- start
pm2 startup
pm2 save

rm -f /etc/profile.d/install.sh
