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

echo -e ${BLU} "Downloading and installing Caddy Server (latest version)" ${DEF}
mkdir -p /opt/caddy
cd  /opt/caddy
CADDY_VERSION=$(curl -s https://api.github.com/repos/caddyserver/caddy/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
wget -q https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz
tar -zxf caddy_${CADDY_VERSION}_linux_amd64.tar.gz


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
reverse_proxy 127.0.0.1:${PORT}
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
ExecReload=/bin/kill -HUP \$MAINPID
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
