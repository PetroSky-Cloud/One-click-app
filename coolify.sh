#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get update -qq
apt-get -qqq -y install curl net-tools bind9-host > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO COOLIFY INSTALL SCRIPT                            ${GRN}#"
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

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8000 false
fi

echo -e ${BLU} "Running official Coolify installer (this may take several minutes)..." ${DEF}

curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

sleep 5

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:8000"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                     COOLIFY INSTALLATION COMPLETE                      ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${YEL}  Register your admin account at the URL above.${DEF}"
echo
if [ -n "$DOMAIN" ]; then
    echo -e "${BLU}  TIP: After registering, you can close ports 8000, 6001, 6002${DEF}"
    echo -e "${BLU}       from external access. Domain uses Caddy (port 443) only.${DEF}"
    echo
fi
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Coolify PaaS
============

Access Coolify: ${ACCESS_URL}

First-time setup:
  1. Open the URL above
  2. Register your admin account (first user becomes admin)

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
  8000    Web UI (can close if using domain)
  6001    WebSocket (can close if using domain)
  6002    Terminal (can close if using domain)
  443     HTTPS (Caddy - keep open)
  22      SSH (keep open)

Security Tip:
  If using a custom domain with Caddy reverse proxy, you can close
  ports 8000, 6001, 6002 from external access for better security.
  Use your cloud provider's firewall (UFW may not block Docker ports).

Documentation: https://coolify.io/docs

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
