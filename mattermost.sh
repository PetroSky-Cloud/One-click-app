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
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/caddy.sh | bash -s -- $DOMAIN 8065 false
fi

apt install -y postgresql-common git sudo curl ca-certificates uuid-runtime moreutils jq -y
/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh  yes

install -d /usr/share/postgresql-common/pgdg
curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
. /etc/os-release
sh -c "echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $VERSION_CODENAME-pgdg main' > /etc/apt/sources.list.d/pgdg.list"

apt update
apt -y install postgresql-18 git sudo

PGUSER=mmuser
PGPASS=`uuidgen`

cat > /tmp/user.sql <<-EOF
CREATE DATABASE mattermost WITH ENCODING 'UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8' TEMPLATE=template0;
CREATE USER ${PGUSER} WITH PASSWORD '${PGPASS}';
GRANT ALL PRIVILEGES ON DATABASE mattermost TO ${PGUSER};
GRANT CREATE ON SCHEMA public TO ${PGUSER};
GRANT ALL ON SCHEMA public TO ${PGUSER};
ALTER ROLE ${PGUSER} WITH SUPERUSER;
EOF

sudo -u postgres psql -f /tmp/user.sql
rm /tmp/user.sql


systemctl restart postgresql


curl -o- https://deb.packages.mattermost.com/repo-setup.sh | bash -s mattermost
apt update
apt install mattermost -y
jq '.SqlSettings.DataSource = "postgres://UUSSEERR:PPAASSWW@localhost/mattermost?sslmode=disable&connect_timeout=10&binary_parameters=yes"' /opt/mattermost/config/config.defaults.json \
| sed -e s/UUSSEERR:PPAASSWW/mmuser:${PGPASS}/g > /opt/mattermost/config/config.json

# sed -i s/UUSSEERR:PPAASSWW/mmuser:${PGPASS}/g /opt/mattermost/config/config.json

chmod 600 /opt/mattermost/config/config.json
mkdir -p /opt/mattermost/data
chown -R mattermost:mattermost /opt/mattermost/data
chown -R mattermost:mattermost /opt/mattermost/config/config.json

systemctl  restart  mattermost.service

echo
echo -e ${YEL}
echo "You can now logint to https://${DOMAIN}"
echo -e ${DEF}
echo


rm -f /etc/profile.d/install.sh
