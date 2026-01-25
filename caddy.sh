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


MAX_WAIT=120
WAITED=0

echo -e ${BLU} "Checking DNS for $DOMAIN..." ${DEF}

while [ $WAITED -lt $MAX_WAIT ]; do
    RESOLVED=$(host $DOMAIN 2>/dev/null | grep "has address" | head -1)

    if [ -n "$RESOLVED" ]; then
        RESOLVED_IP=$(echo "$RESOLVED" | awk '{print $NF}')

        if [ "$RESOLVED_IP" = "$MYIP" ]; then
            echo -e ${GRN} "DNS verified: $DOMAIN -> $MYIP (direct)" ${DEF}
        else
            echo -e ${GRN} "DNS verified: $DOMAIN -> $RESOLVED_IP (CDN/proxy)" ${DEF}
        fi
        break
    fi

    echo -e ${BLU} "Waiting for DNS propagation... ${WAITED}s" ${DEF}
    sleep 10
    WAITED=$((WAITED + 10))
done

if [ $WAITED -ge $MAX_WAIT ]; then
    echo -e ${YEL} "DNS check timed out after ${MAX_WAIT}s - proceeding anyway" ${DEF}
fi

echo -e ${BLU}"Downloading and installing Caddy Server (latest version)" ${DEF}
mkdir /opt/caddy
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
