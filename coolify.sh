#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get -qqq -y install curl uuid-runtime net-tools > /dev/null 2>&1

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO COOLIFY INSTALL SCRIPT                            ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

printf "%s" "Please enter Domain Name, or hit enter for insecure installation: "
read DOMAIN

printf "%s" "Please enter Admin Email: "
read ADMIN_EMAIL

printf "%s" "Please enter Admin Password (or hit enter to generate one): "
read -s ADMIN_PASSWORD
echo

echo -e ${DEF}

if [ "$DOMAIN" = "" ]; then
    echo -e ${GRN} "Installing without certificates and proper TLS termination" ${DEF}
else
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/caddy.sh | bash -s -- $DOMAIN 8000 false
fi

if [ -z "$ADMIN_EMAIL" ]; then
    ADMIN_EMAIL="admin@localhost"
fi

if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | head -c 16)
    echo -e ${YEL} "Generated admin password: ${ADMIN_PASSWORD}" ${DEF}
fi

ADMIN_USERNAME=$(echo "$ADMIN_EMAIL" | cut -d'@' -f1 | tr -cd '[:alnum:]' | head -c 20)
if [ -z "$ADMIN_USERNAME" ]; then
    ADMIN_USERNAME="admin"
fi

echo -e ${BLU} "Running official Coolify installer (this may take several minutes)..." ${DEF}

export ROOT_USERNAME="$ADMIN_USERNAME"
export ROOT_USER_EMAIL="$ADMIN_EMAIL"
export ROOT_USER_PASSWORD="$ADMIN_PASSWORD"

curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

sleep 5

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:8000"
fi

cat > /root/README.txt << EOF
Coolify PaaS
============

Access Coolify: ${ACCESS_URL}

Admin Credentials:
  Email: ${ADMIN_EMAIL}
  Password: (provided during installation)

Manage Coolify:
  cd /data/coolify/source
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart services

Data Locations:
  /data/coolify/source/.env      # Main config (BACKUP THIS!)
  /data/coolify/applications/    # Deployed apps
  /data/coolify/databases/       # Database data
  /data/coolify/backups/         # Backups

Auto-updates: Enabled by default
  To disable: edit /data/coolify/source/.env and set AUTOUPDATE=false

Ports:
  8000    Web UI
  6001    WebSocket
  6002    Terminal

Documentation: https://coolify.io/docs

Installed: $(date)
EOF

cat > /root/coolify-credentials.txt << EOF
Coolify Installation Credentials
================================

Access URL: ${ACCESS_URL}

Admin Credentials:
  Username: ${ADMIN_USERNAME}
  Email: ${ADMIN_EMAIL}
  Password: ${ADMIN_PASSWORD}

Installation Date: $(date)
EOF

chmod 600 /root/coolify-credentials.txt

echo
echo
echo -e ${GRN} "Coolify installation complete!" ${DEF}
echo -e ${GRN} "Access: ${YEL}${ACCESS_URL}" ${DEF}
echo -e ${GRN} "Admin Email: ${YEL}${ADMIN_EMAIL}" ${DEF}
echo
echo -e ${BLU} "Credentials saved to: /root/coolify-credentials.txt" ${DEF}
echo -e ${BLU} "README saved to: /root/README.txt" ${DEF}
echo

rm -f /etc/profile.d/install.sh
