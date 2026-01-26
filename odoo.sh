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
echo -e ${GRN} "# ${BLU}WELCOME TO ODOO INSTALL SCRIPT                                ${GRN}#"
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

echo -e ${BLU} "Creating Odoo directories..." ${DEF}
mkdir -p /opt/odoo/{addons,config}
cd /opt/odoo

echo -e ${BLU} "Generating secrets..." ${DEF}
POSTGRES_PASSWORD=$(openssl rand -hex 16)

echo -e ${BLU} "Creating Odoo config..." ${DEF}
cat > /opt/odoo/config/odoo.conf << EOFCONF
[options]
addons_path = /mnt/extra-addons
data_dir = /var/lib/odoo
admin_passwd = $(openssl rand -hex 16)
db_host = db
db_port = 5432
db_user = odoo
db_password = ${POSTGRES_PASSWORD}
EOFCONF

echo -e ${BLU} "Creating docker-compose.yml..." ${DEF}
cat > /opt/odoo/docker-compose.yml << EOFCOMPOSE
services:
  odoo:
    image: odoo:17
    container_name: odoo
    restart: unless-stopped
    ports:
      - "8069:8069"
    environment:
      HOST: db
      USER: odoo
      PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - odoo_data:/var/lib/odoo
      - ./config:/etc/odoo
      - ./addons:/mnt/extra-addons
    depends_on:
      - db

  db:
    image: postgres:15
    container_name: odoo_db
    restart: unless-stopped
    environment:
      POSTGRES_DB: postgres
      POSTGRES_USER: odoo
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - odoo_db:/var/lib/postgresql/data/pgdata

volumes:
  odoo_data:
  odoo_db:
EOFCOMPOSE

echo -e ${BLU} "Creating environment file..." ${DEF}
cat > /opt/odoo/.env << EOFENV
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
EOFENV

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8069 false
fi

echo -e ${BLU} "Starting Odoo..." ${DEF}
docker compose pull
docker compose up -d

sleep 30

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:8069"
fi

ADMIN_PASSWD=$(grep admin_passwd /opt/odoo/config/odoo.conf | cut -d= -f2 | tr -d ' ')

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                     ODOO INSTALLATION COMPLETE                         ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:      ${GRN}${ACCESS_URL}${DEF}"
echo -e "${YEL}  MASTER PASSWORD: ${GRN}${ADMIN_PASSWD}${DEF}"
echo
echo -e "${BLU}  Use the master password to create your first database.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Odoo - Business Management Suite
================================

Access: ${ACCESS_URL}
Master Password: ${ADMIN_PASSWD}

First-time setup:
  1. Open the URL above
  2. Click "Manage Databases" or wait for database creation prompt
  3. Enter Master Password above
  4. Create a new database with admin email/password
  5. Select apps to install (Sales, CRM, Inventory, etc.)

Available Apps (Community Edition):
  - CRM: Customer relationship management
  - Sales: Quotations and orders
  - Inventory: Stock management
  - Accounting: Invoicing and payments
  - Website: Website builder
  - eCommerce: Online store
  - HR: Human resources
  - Project: Project management
  - Manufacturing: MRP
  - And many more...

Database Credentials (stored in /opt/odoo/.env):
  Host: db
  Database: Created via UI
  User: odoo
  Password: ${POSTGRES_PASSWORD}

Custom Addons:
  Place custom modules in: /opt/odoo/addons
  Then restart Odoo and update apps list

Manage Odoo:
  cd /opt/odoo
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart
  docker compose pull && docker compose up -d  # Update

Configuration: /opt/odoo/config/odoo.conf

Backup Database:
  docker exec odoo_db pg_dump -U odoo DATABASE_NAME > backup.sql

Restore Database:
  docker exec -i odoo_db psql -U odoo DATABASE_NAME < backup.sql

Enterprise Edition:
  Replace image with your Enterprise image and add license

Documentation: https://www.odoo.com/documentation/17.0/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
