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

printf "%s" "Please enter Admin Full Name: "
read ADMIN_FULLNAME

printf "%s" "Please enter Admin User Name: "
read ADMIN_USERNAME
printf "%s" "Please enter Admin Password: "
read ADMIN_PASSWORD
printf "%s" "Please enter Admin E-Mail: "
read ADMIN_EMAIL


if [ "$DOMAIN" = "" ]; then
    echo "installing without certificates and proper TLS termination"
else
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/caddy.sh | bash -s -- $DOMAIN 3003 false
fi

MYPASSWD=`uuidgen`
SECRET_KEY=`uuidgen`
INTERNAL_TOKEN=`uuidgen`

useradd -s /bin/false -d /dev/null -r gitea
mkdir -p /opt/gitea/custom/conf/
touch /opt/gitea/custom/conf/app.ini
cd /opt/gitea
echo -e ${BLU} "Downloading Gitea" ${DEF}
wget -q  -O gitea  https://dl.gitea.com/gitea/1.25.1/gitea-1.25.1-linux-amd64
chmod 755 gitea
chown -R gitea:gitea /opt/gitea

echo -e ${BLU} "Installing MariaDB Server, may take some time" ${DEF}
apt-get -y install mariadb-server uuid-runtime git rsyslog ccze net-tools  > /dev/null  2>&1

cat > /opt/gitea/custom/conf/app.ini <<-EOF
APP_NAME = Gitea: Go Git Service
RUN_USER = gitea
RUN_MODE = prod
WORK_PATH = /opt/gitea

[database]
DB_TYPE = mysql
HOST = 127.0.0.1:3306
NAME = gitea
USER = gitea
PASSWD = ${MYPASSWD}
SSL_MODE = disable
PATH = data/gogs.db

[repository]
ROOT = /opt/gitea/repos

[server]
DOMAIN = ${DOMAIN}
HTTP_PORT = 3003
ROOT_URL = https://${DOMAIN}/
DISABLE_SSH = false
SSH_PORT = 2222
OFFLINE_MODE = true
START_SSH_SERVER = true
SSH_DOMAIN = ${DOMAIN}
SSH_LISTEN_PORT = %(SSH_PORT)s
SSH_ROOT_PATH = /opt/gitea/repos

[mailer]
ENABLED = false
HOST = 127.0.0.1:25
FROM = gitea@${DOMAIN}
SKIP_VERIFY = true
USER =
PASSWD =

[service]
REGISTER_EMAIL_CONFIRM = false
ENABLE_NOTIFY_MAIL = false
DISABLE_REGISTRATION = true
ENABLE_CAPTCHA = false
REQUIRE_SIGNIN_VIEW = true

[picture]
DISABLE_GRAVATAR = false

[session]
PROVIDER = file

[log]
MODE = file
LEVEL = Notice

[security]
INSTALL_LOCK = true
SECRET_KEY = ${SECRET_KEY}

[attachment]
ENABLE = true
PATH = data/attachments
ALLOWED_TYPES = image/jpeg|image/png|application/pdf|application/zip|application/json|application/gz|application/octet-stream
MAX_SIZE = 32
MAX_FILES = 10

[registry]
ENABLED = true
STORAGE_TYPE = local
PATH = /opt/gitea/docker
SERVE_DATA = true

EOF

cat > /tmp/giteq.sql <<-EOF
create database gitea ;
GRANT ALL PRIVILEGES ON gitea.* TO 'gitea'@'%' IDENTIFIED BY "${MYPASSWD}";
GRANT ALL PRIVILEGES ON gitea.* TO 'gitea'@'%' IDENTIFIED BY "${MYPASSWD}";
GRANT ALL PRIVILEGES ON gitea.* TO 'git'@'%' IDENTIFIED BY "${MYPASSWD}";
EOF

mysql < /tmp/giteq.sql
rm /tmp/giteq.sql



cat > /etc/systemd/system/gitea.service <<-EOF
[Unit]
Description=GITEA
Documentation=https://${DOMAIN}
Wants=network-online.target
After=network-online.target

[Service]
User=gitea
Group=gitea
Environment="START_SSH_SERVER=true"
Environment="SSH_PORT=2222"
PIDFile=/var/run/gitea.pid
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/opt/gitea/gitea web
WorkingDirectory=/opt/gitea
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=2
StartLimitBurst=3
TasksMax=infinity

[Install]
WantedBy=multi-user.target

EOF

systemctl  daemon-reload
systemctl  enable gitea.service
systemctl  restart gitea.service

sleep 2
echo -e ${YEL} "Migrating database"
sudo -u gitea ./gitea  migrate  > /dev/null  2>&1
sleep 2

sudo -u gitea ./gitea admin user create --name "${ADMIN_FULLNAME}" --username ${ADMIN_USERNAME} --password ${ADMIN_PASSWORD} --email ${ADMIN_EMAIL} --admin
echo -e ${DEF}

echo -e ${BLU} "Please visit: ${YEL} https://${DOMAIN} ${BLU}to complete the installation" ${DEF}
echo -e ${BLU} "MySQL datase   is: ${YEL} gitea" ${DEF}
echo -e ${BLU} "MySQL username is: ${YEL} gitea" ${DEF}
echo -e ${BLU} "MySQL password is: ${YEL} ${MYPASSWD}" ${DEF}
echo -e ${BLU} "Your GIT SSH Is running on: ${YEL} ${DOMAIN}:2222" ${DEF}

echo

echo -e ${BLU} "Site Admin name is: ${ADMIN_FULLNAME}" ${DEF}
echo -e ${BLU} "Site Admin user is: ${ADMIN_USERNAME}" ${DEF}
echo -e ${BLU} "Site Admin pass is: ${ADMIN_PASSWORD}" ${DEF}

echo
