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

echo -e ${BLU} "Ensuring SSH root login is configured (required by Coolify)..." ${DEF}
if grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
else
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
fi
systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null

echo -e ${BLU} "Running official Coolify installer (this may take several minutes)..." ${DEF}

curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

echo -e ${BLU} "Waiting for Coolify to start (this may take 2-3 minutes)..." ${DEF}
TIMEOUT=180
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8000 2>/dev/null | grep -q "200\|302"; then
        echo -e "${GRN}Coolify is running!${DEF}"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -e "${BLU}  Still waiting... (${ELAPSED}s)${DEF}"
done

if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "coolify"; then
    echo -e "${RED}WARNING: Coolify containers may not have started properly.${DEF}"
    echo -e "${YEL}Check logs: cd /data/coolify/source && docker compose logs${DEF}"
fi

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Configuring domain ${DOMAIN} in Coolify..." ${DEF}
    sleep 5
    docker exec coolify php artisan tinker --execute="\$s = App\Models\InstanceSettings::first(); \$s->fqdn = 'https://${DOMAIN}'; \$s->save();" 2>/dev/null

    FQDN_CHECK=$(docker exec coolify php artisan tinker --execute="echo App\Models\InstanceSettings::first()->fqdn;" 2>/dev/null | grep -o "https://${DOMAIN}" || true)
    if [ -n "$FQDN_CHECK" ]; then
        echo -e "${GRN}Domain configured: ${FQDN_CHECK}${DEF}"
        echo -e "${BLU}Traefik will automatically obtain a TLS certificate for ${DOMAIN}${DEF}"
    else
        echo -e "${YEL}WARNING: Domain auto-configuration may have failed.${DEF}"
        echo -e "${YEL}Configure manually: Coolify Settings > Configuration > Instance's Domain${DEF}"
    fi
fi

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
    echo -e "${BLU}  TLS certificate will be obtained automatically by Traefik.${DEF}"
    echo -e "${BLU}  It may take a minute for HTTPS to become active.${DEF}"
else
    echo -e "${BLU}  To add a custom domain with HTTPS:${DEF}"
    echo -e "${BLU}    1. Log in to Coolify at the URL above${DEF}"
    echo -e "${BLU}    2. Go to Settings > Configuration${DEF}"
    echo -e "${BLU}    3. Set your domain under Instance's Domain${DEF}"
    echo -e "${BLU}    4. Coolify handles TLS/SSL automatically via Traefik${DEF}"
fi
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Coolify PaaS
============

Access Coolify: ${ACCESS_URL}

First-time setup:
  1. Open the URL above
  2. Register your admin account (first user becomes admin)

Custom Domain:
  Coolify includes Traefik as its built-in reverse proxy.
  Domain: ${DOMAIN:-Not configured}
  To change the domain: Settings > Configuration > Instance's Domain

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
  8000    Web UI (dashboard, always accessible)
  80/443  Traefik reverse proxy (custom domain + deployed apps)
  6001    WebSocket
  6002    Terminal
  22      SSH (keep open)

Documentation: https://coolify.io/docs

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
