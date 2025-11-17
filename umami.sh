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

printf "%s" "Please enter Domain Name, or hit enter for insecure installation: "
read DOMAIN

echo -e ${DEF}

if [ "$DOMAIN" = "" ]; then
    echo "installing without certificates and proper TLS termination"
else
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/caddy.sh | bash -s -- $DOMAIN 3000 false
fi

apt-get install -y postgresql-common git sudo curl ca-certificates uuid-runtime -y
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
wget https://nodejs.org/dist/v24.11.0/node-v24.11.0-linux-x64.tar.xz
tar -xvf node-v24.11.0-linux-x64.tar.xz
rm node-v24.11.0-linux-x64.tar.xz
ln -s node-v24.11.0-linux-x64 node
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
