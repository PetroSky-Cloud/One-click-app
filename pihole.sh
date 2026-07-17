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
echo -e ${GRN} "# ${BLU}WELCOME TO PI-HOLE INSTALL SCRIPT                             ${GRN}#"
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

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

echo -e ${BLU} "Disabling systemd-resolved (conflicts with Pi-hole DNS)..." ${DEF}
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf

echo -e ${BLU} "Creating Pi-hole directories..." ${DEF}
mkdir -p /opt/pihole/{etc-pihole,etc-dnsmasq.d}
cd /opt/pihole

echo -e ${BLU} "Generating admin password..." ${DEF}
WEBPASSWORD=$(openssl rand -hex 12)

echo -e ${BLU} "Creating docker-compose.yml..." ${DEF}
cat > /opt/pihole/docker-compose.yml << EOFCOMPOSE
services:
  pihole:
    image: pihole/pihole:latest
    container_name: pihole
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "8080:80/tcp"
    environment:
      TZ: 'UTC'
      FTLCONF_webserver_api_password: '${WEBPASSWORD}'
      FTLCONF_dns_upstreams: '1.1.1.1;8.8.8.8'
    volumes:
      - ./etc-pihole:/etc/pihole
      - ./etc-dnsmasq.d:/etc/dnsmasq.d
    cap_add:
      - NET_ADMIN
EOFCOMPOSE

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8080 false
fi

echo -e ${BLU} "Starting Pi-hole..." ${DEF}
docker compose pull
docker compose up -d

sleep 20

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}/admin"
else
    ACCESS_URL="http://${MYIP}:8080/admin"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   PI-HOLE INSTALLATION COMPLETE                        ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ADMIN URL:     ${GRN}${ACCESS_URL}${DEF}"
echo -e "${YEL}  PASSWORD:      ${GRN}${WEBPASSWORD}${DEF}"
echo -e "${YEL}  DNS SERVER:    ${GRN}${MYIP}${DEF}"
echo
echo -e "${BLU}  Configure your devices/router to use ${MYIP} as DNS server.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Pi-hole - Network-wide Ad Blocking
===================================

Admin Panel: ${ACCESS_URL}
Password: ${WEBPASSWORD}
DNS Server: ${MYIP}

Setup Instructions:
  1. Login to admin panel with password above
  2. Configure your devices to use ${MYIP} as DNS server

Option A - Per Device:
  Set DNS server to ${MYIP} in network settings of each device

Option B - Router (recommended):
  Set ${MYIP} as the primary DNS in your router's DHCP settings
  All devices on your network will automatically use Pi-hole

Features:
  - Blocks ads on all devices
  - Blocks trackers and telemetry
  - Query logging and statistics
  - Custom blocklists
  - Local DNS records
  - DHCP server (optional)

Change Password:
  Edit FTLCONF_webserver_api_password in /opt/pihole/docker-compose.yml
  then: cd /opt/pihole && docker compose up -d

Manage Pi-hole:
  cd /opt/pihole
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Update Gravity (blocklists):
  docker exec -it pihole pihole -g

Allow/Deny domains:
  Use the admin panel (Domains section)

Configuration: /opt/pihole/etc-pihole
DNS Config: /opt/pihole/etc-dnsmasq.d

Documentation: https://docs.pi-hole.net/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
