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
printf "%s" "Please enter SUPER USER email: "
read USER
printf "%s" "Please enter SUPER USER password: "
read PASS

MYIP=`curl -s https://ipv4.icanhazip.com`

while : ; do
    if host $DOMAIN 1.1.1.1| grep $MYIP ; then
        echo CloudFlare Matched!
        break
    else
        echo CloudFlare: $DOMAIN not match $MYIP
        sleep 5
    fi
    if host $DOMAIN 8.8.8.8| grep $MYIP ; then
        echo Google Matched !
        break
    else
        echo Google    : $DOMAIN not match $MYIP
        sleep 5
    fi
    if host $DOMAIN| grep $MYIP ; then
        echo Local     : $DOMAIN not match $MYIP
        break
    else
        echo Local $DOMAIN not match $MYIP
        sleep 5
    fi
done


echo -e ${DEF}

apt-get -y install unzip wget curl

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}
mkdir -p /opt/pocketbase
cd /opt/pocketbase
PB_VERSION=$(curl -s https://api.github.com/repos/pocketbase/pocketbase/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
wget -qO pocketbase.zip https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip
unzip pocketbase.zip

./pocketbase superuser upsert  $USER $PASS

cat > /etc/systemd/system/pocketbase.service <<- EOF
[Unit]
Description=Pocketbase
Documentation=https://github.com/pocketbase/pocketbase
Wants=network-online.target
After=network-online.target

[Service]
WorkingDirectory = /opt/pocketbase/
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/opt/pocketbase/pocketbase serve ${DOMAIN}
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
EOF

systemctl  daemon-reload
systemctl  enable pocketbase.service
systemctl  restart pocketbase.service

echo -e ${GRN}
echo Congratulation the installation completed successsfully
echo Open your dashboerd at: https://${DOMAIN}/_/ in your browser
echo API is available at: https://${DOMAIN}/api/ in your browser
echo -e ${DEF}

rm -f /etc/profile.d/install.sh
