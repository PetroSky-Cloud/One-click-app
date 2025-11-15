#!/bin/bash
{literal}


USER=$1
PASS=$2
DOMAIN=$3

if [ -z "$3" ]; then
    echo USERNAME and PASSWORD are required
    exit 2
fi


apt-get -y install unzip wget curl
mkdir -p /opt/pocketbase
cd /opt/pocketbase
wget -O pocketbase.zip https://github.com/pocketbase/pocketbase/releases/download/v0.31.0/pocketbase_0.31.0_linux_amd64.zip
unzip pocketbase.zip


./pocketbase superuser upsert  $USER $PASS

# ./pocketbase serve $DOMAIN

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
{/literal}
