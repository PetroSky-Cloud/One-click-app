#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl net-tools bind9-host mariadb-server uuid-runtime git rsyslog ccze > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO GITEA INSTALL SCRIPT                               ${GRN}#"
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

printf "${YEL}Please enter Admin Full Name: ${DEF}"
read ADMIN_FULLNAME

printf "${YEL}Please enter Admin User Name: ${DEF}"
read ADMIN_USERNAME

printf "${YEL}Please enter Admin Password: ${DEF}"
read ADMIN_PASSWORD

printf "${YEL}Please enter Admin E-Mail: ${DEF}"
read ADMIN_EMAIL

if [ -n "$DOMAIN" ]; then
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 3003 false
fi

MYPASSWD=$(uuidgen)
SECRET_KEY=$(uuidgen)
INTERNAL_TOKEN=$(uuidgen)

useradd -r -s /bin/false -d /dev/null gitea
mkdir -p /opt/gitea/custom/conf/
touch /opt/gitea/custom/conf/app.ini
cd /opt/gitea
echo -e ${BLU} "Downloading Gitea (latest version)" ${DEF}
GITEA_VERSION=$(curl -s https://api.github.com/repos/go-gitea/gitea/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
wget -q -O gitea https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64
chmod 755 gitea
chown -R gitea:gitea /opt/gitea

# Determine URLs based on domain
if [ -n "$DOMAIN" ]; then
    ROOT_URL="https://${DOMAIN}/"
    SSH_DOMAIN="${DOMAIN}"
else
    ROOT_URL="http://${MYIP}:3003/"
    SSH_DOMAIN="${MYIP}"
fi

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
DOMAIN = ${SSH_DOMAIN}
HTTP_PORT = 3003
ROOT_URL = ${ROOT_URL}
DISABLE_SSH = false
SSH_PORT = 2222
OFFLINE_MODE = true
START_SSH_SERVER = true
SSH_DOMAIN = ${SSH_DOMAIN}
SSH_LISTEN_PORT = %(SSH_PORT)s
SSH_ROOT_PATH = /opt/gitea/repos

[mailer]
ENABLED = false
HOST = 127.0.0.1:25
FROM = gitea@${SSH_DOMAIN}
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

cat > /tmp/gitea.sql <<-EOF
create database gitea ;
GRANT ALL PRIVILEGES ON gitea.* TO 'gitea'@'%' IDENTIFIED BY "${MYPASSWD}";
GRANT ALL PRIVILEGES ON gitea.* TO 'gitea'@'%' IDENTIFIED BY "${MYPASSWD}";
GRANT ALL PRIVILEGES ON gitea.* TO 'git'@'%' IDENTIFIED BY "${MYPASSWD}";
EOF

mysql < /tmp/gitea.sql
rm /tmp/gitea.sql

cat > /etc/systemd/system/gitea.service <<-EOF
[Unit]
Description=GITEA
Documentation=https://gitea.io
Wants=network-online.target
After=network-online.target

[Service]
User=gitea
Group=gitea
Environment="START_SSH_SERVER=true"
Environment="SSH_PORT=2222"
PIDFile=/var/run/gitea.pid
ExecReload=/bin/kill -HUP \$MAINPID
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

systemctl daemon-reload
systemctl enable gitea.service
systemctl restart gitea.service

sleep 2
echo -e ${YEL} "Migrating database" ${DEF}
sudo -u gitea ./gitea migrate > /dev/null 2>&1
sleep 2

sudo -u gitea ./gitea admin user create --name "${ADMIN_FULLNAME}" --username ${ADMIN_USERNAME} --password ${ADMIN_PASSWORD} --email ${ADMIN_EMAIL} --admin

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:3003"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                     GITEA INSTALLATION COMPLETE                        ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo -e "${YEL}  GIT SSH:     ${GRN}${SSH_DOMAIN}:2222${DEF}"
echo
echo -e "${BLU}  Admin Credentials:${DEF}"
echo -e "${YEL}    Username: ${GRN}${ADMIN_USERNAME}${DEF}"
echo -e "${YEL}    Password: ${GRN}${ADMIN_PASSWORD}${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Gitea - Lightweight Git Server
==============================

Access: ${ACCESS_URL}
Git SSH: ${SSH_DOMAIN}:2222

Admin Credentials:
  Username: ${ADMIN_USERNAME}
  Password: ${ADMIN_PASSWORD}

Database:
  Host: localhost
  Database: gitea
  User: gitea
  Password: ${MYPASSWD}

Clone via SSH:
  git clone ssh://git@${SSH_DOMAIN}:2222/username/repo.git

Clone via HTTP:
  git clone ${ACCESS_URL}/username/repo.git

Manage Gitea:
  systemctl status gitea      # Check status
  systemctl restart gitea     # Restart
  journalctl -u gitea -f      # View logs

Configuration: /opt/gitea/custom/conf/app.ini
Repositories: /opt/gitea/repos

Update Gitea:
  systemctl stop gitea
  cd /opt/gitea
  wget -O gitea https://dl.gitea.com/gitea/VERSION/gitea-VERSION-linux-amd64
  chmod 755 gitea
  systemctl start gitea

Documentation: https://docs.gitea.io/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
