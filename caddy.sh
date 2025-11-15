#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'


if [ -z "$2" ]; then
    echo -e ${RED} Parameters DOMAIN and PORT are required
    exit 2
fi


DOMAIN=$1
PORT=$2
SECURE=$3

MYIP=`curl -s https://ipv4.icanhazip.com`

apt-get update > /dev/null  2>&1
apt-get install bind9-host -y > /dev/null  2>&1


while : ; do
    if host $DOMAIN 1.1.1.1| grep $MYIP ; then
        echo -e ${GRN} CloudFlare Matched! ${DEF}
        break
    else
        echo -e ${BLU} CloudFlare: $DOMAIN not match $MYIP ${DEF}
        sleep 5
    fi
    if host $DOMAIN 8.8.8.8| grep $MYIP ; then
        echo -e ${GRN} Google Matched ! ${DEF}
        break
    else
        echo -e ${BLU} Google    : $DOMAIN not match $MYIP ${DEF}
        sleep 5
    fi
    if host $DOMAIN| grep $MYIP ; then
        echo -e ${GRN} Local DNS Matched! ${DEF}
        break
    else
        echo -e ${BLU} Local DNS  : $DOMAIN not match $MYIP ${DEF}
        sleep 5
    fi
done

echo -e ${BLU}"Downloading and installing Caddy Server" ${DEF}
mkdir /opt/caddy
cd  /opt/caddy
wget -q  https://github.com/caddyserver/caddy/releases/download/v2.10.2/caddy_2.10.2_linux_amd64.tar.gz
tar -zxf caddy_2.10.2_linux_amd64.tar.gz


if $SECURE ;
  then
cat > /opt/caddy/caddyfile <<- EOF
${DOMAIN} {
reverse_proxy 127.0.0.1:${PORT} {
    transport http {
    tls_insecure_skip_verify
    }
}
}
EOF
  else
cat > /opt/caddy/caddyfile <<- EOF
${DOMAIN} {
reverse_proxy 127.0.0.1:${PORT} {
}
}
EOF
    fi

cat > /etc/systemd/system/caddy.service <<- EOF
[Unit]
Description=caddy
Documentation=https://github.com/caddy/caddy
Wants=network-online.target
After=network-online.target

[Service]
WorkingDirectory = /opt/caddy/
Environment=XDG_DATA_HOME=/opt/caddy/storage
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/opt/caddy/caddy run --config /opt/caddy/caddyfile
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

systemctl  daemon-reload > /dev/null  2>&1
systemctl  enable caddy.service > /dev/null  2>&1
systemctl  restart caddy.service > /dev/null  2>&1

echo -e ${BLU} Caddy server is sucessfully installed on $DOMAIN with upstream 127.0.0.1:${PORT} ${DEF}
