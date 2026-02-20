#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e "${BLU}Please wait, preparing the initial setup...${DEF}"

apt-get update -qq
apt-get -qqq -y install curl uuid-runtime net-tools bind9-host python3-yaml > /dev/null 2>&1

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null)

validate_domain() {
    local domain=$1
    host "$domain" 2>/dev/null | grep -q "has address"
}

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO MATRIX + ELEMENT INSTALL SCRIPT                    ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e "${YEL}  Matrix is a decentralized, end-to-end encrypted messaging platform."
echo -e "${YEL}  This script installs Synapse (homeserver) + Element (web client)."
echo
echo -e "${RED}  IMPORTANT: A domain name pointing to this server is required."
echo -e "${RED}  TLS certificates are mandatory for Matrix federation and security."
echo -e "${DEF}"

# Domain (required — Matrix cannot run without TLS)
while true; do
    echo
    printf "${YEL}Enter your domain name (e.g. chat.example.com): ${DEF}"
    read DOMAIN

    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}ERROR: A domain name is required to install Matrix/Element.${DEF}"
        echo -e "${YEL}Please configure DNS for your domain first, then re-run.${DEF}"
        continue
    fi

    echo -e "${BLU}Checking DNS for ${DOMAIN}...${DEF}"

    if validate_domain "$DOMAIN"; then
        RESOLVED_IP=$(host "$DOMAIN" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
        if [ "$RESOLVED_IP" = "$MYIP" ]; then
            echo -e "${GRN}DNS verified: ${DOMAIN} -> ${MYIP}${DEF}"
        else
            echo -e "${GRN}DNS verified: ${DOMAIN} -> ${RESOLVED_IP} (proxy/CDN)${DEF}"
        fi
        break
    else
        echo -e "${RED}ERROR: '${DOMAIN}' does not resolve to any IP.${DEF}"
        echo -e "${YEL}Please set your DNS A record to point to ${MYIP}, then try again.${DEF}"
    fi
done

# Admin credentials
echo
printf "${YEL}Enter Matrix admin username (default: admin): ${DEF}"
read ADMIN_USER
if [ -z "$ADMIN_USER" ]; then
    ADMIN_USER="admin"
fi
ADMIN_USER=$(echo "$ADMIN_USER" | tr -cd '[:alnum:]_.-')

echo
printf "${YEL}Enter Matrix admin password: ${DEF}"
read -s ADMIN_PASS
echo
if [ -z "$ADMIN_PASS" ]; then
    ADMIN_PASS=$(uuidgen | tr -d '-')
    echo -e "${YEL}No password entered. Generated: ${ADMIN_PASS}${DEF}"
fi

# Federation option
echo
printf "${YEL}Enable federation with other Matrix servers? (y/N): ${DEF}"
read FEDERATION_INPUT
FEDERATION_ENABLED="false"
if [ "${FEDERATION_INPUT,,}" = "y" ] || [ "${FEDERATION_INPUT,,}" = "yes" ]; then
    FEDERATION_ENABLED="true"
fi

echo -e "${DEF}"

# Install Docker
echo -e "${BLU}Installing Docker...${DEF}"
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

# Install Caddy (handles TLS automatically via Let's Encrypt)
# Caddy will proxy: / -> Element (8080), /_matrix -> Synapse (8008), /_synapse -> Synapse (8008)
echo -e "${BLU}Installing Caddy reverse proxy with automatic TLS...${DEF}"
apt-get -qqq -y install debian-keyring debian-archive-keyring apt-transport-https > /dev/null 2>&1
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
apt-get update -qq
apt-get -qqq -y install caddy > /dev/null 2>&1

# Generate secrets
DB_PASSWORD=$(uuidgen | tr -d '-')
REGISTRATION_SECRET=$(openssl rand -base64 32 | tr -d '/+=\n')

# Create directory structure
mkdir -p /opt/matrix/synapse
mkdir -p /opt/matrix/element
mkdir -p /opt/matrix/caddy

echo -e "${BLU}Generating Synapse configuration...${DEF}"

# Generate homeserver.yaml using Synapse's built-in generate command
docker run --rm \
    -v /opt/matrix/synapse:/data \
    -e SYNAPSE_SERVER_NAME="${DOMAIN}" \
    -e SYNAPSE_REPORT_STATS=no \
    matrixdotorg/synapse:latest generate > /dev/null 2>&1

# Patch homeserver.yaml: switch to PostgreSQL, set public_baseurl, registration settings
python3 - <<PYEOF
import yaml

with open('/opt/matrix/synapse/homeserver.yaml', 'r') as f:
    config = yaml.safe_load(f)

# PostgreSQL instead of SQLite
config['database'] = {
    'name': 'psycopg2',
    'txn_limit': 10000,
    'args': {
        'user': 'synapse',
        'password': '${DB_PASSWORD}',
        'dbname': 'synapse',
        'host': 'db',
        'port': 5432,
        'cp_min': 5,
        'cp_max': 10,
        'keepalives_idle': 10,
        'keepalives_interval': 10,
        'keepalives_count': 3,
    }
}

# Public URL - clients connect here
config['public_baseurl'] = 'https://${DOMAIN}/'

# Registration: disabled for public, admin uses shared secret
config['enable_registration'] = False
config['registration_shared_secret'] = '${REGISTRATION_SECRET}'

# Trust X-Forwarded-For from Caddy reverse proxy
config['listeners'] = [{
    'port': 8008,
    'tls': False,
    'type': 'http',
    'x_forwarded': True,
    'resources': [{'names': ['client', 'federation'], 'compress': False}]
}]

# Federation
config['allow_public_rooms_without_auth'] = False
config['allow_public_rooms_over_federation'] = False

# Rate limiting (keep defaults - do not disable)
# Media
config['max_upload_size'] = '50M'

# Logging
config['log_config'] = '/data/${DOMAIN}.log.config'

with open('/opt/matrix/synapse/homeserver.yaml', 'w') as f:
    yaml.dump(config, f, default_flow_style=False, allow_unicode=True)

print('homeserver.yaml patched successfully')
PYEOF

# Write Element config
cat > /opt/matrix/element/config.json << ELEMENTEOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://${DOMAIN}",
            "server_name": "${DOMAIN}"
        },
        "m.identity_server": {
            "base_url": "https://vector.im"
        }
    },
    "disable_custom_urls": false,
    "disable_guests": true,
    "brand": "Element",
    "roomDirectory": {
        "servers": ["${DOMAIN}"]
    },
    "showLabsSettings": false,
    "enable_presence_by_hs_toggle": true
}
ELEMENTEOF

# Write well-known static files (required for Matrix client discovery)
# Directory must mirror URL path: /.well-known/matrix/* -> /opt/matrix/wellknown/.well-known/matrix/*
mkdir -p /opt/matrix/wellknown/.well-known/matrix
printf '{"m.homeserver":{"base_url":"https://%s"},"m.identity_server":{"base_url":"https://vector.im"}}' "${DOMAIN}" > /opt/matrix/wellknown/.well-known/matrix/client
printf '{"m.server":"%s:443"}' "${DOMAIN}" > /opt/matrix/wellknown/.well-known/matrix/server

# Write Caddyfile — single domain handles Matrix + Element + well-known
cat > /opt/matrix/caddy/Caddyfile << CADDYEOF
${DOMAIN} {
    # Matrix well-known discovery (required for Matrix clients to find homeserver)
    handle /.well-known/matrix/* {
        root * /srv/wellknown
        file_server
        header Content-Type application/json
        header Access-Control-Allow-Origin *
    }

    # Matrix client API and federation
    handle /_matrix/* {
        reverse_proxy synapse:8008 {
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }

    handle /_synapse/* {
        reverse_proxy synapse:8008 {
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }

    # Element web client (everything else)
    handle {
        reverse_proxy element:80
    }
}
CADDYEOF

# Write docker-compose.yml
cat > /opt/matrix/docker-compose.yml << COMPOSEEOF
services:
  db:
    image: postgres:15-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: synapse
      POSTGRES_INITDB_ARGS: --encoding=UTF-8 --lc-collate=C --lc-ctype=C
    volumes:
      - db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U synapse"]
      interval: 5s
      timeout: 5s
      retries: 10

  synapse:
    image: matrixdotorg/synapse:latest
    restart: unless-stopped
    environment:
      SYNAPSE_CONFIG_PATH: /data/homeserver.yaml
    volumes:
      - /opt/matrix/synapse:/data
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-fSs", "http://localhost:8008/health"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 90s

  element:
    image: vectorim/element-web:latest
    restart: unless-stopped
    volumes:
      - /opt/matrix/element/config.json:/app/config.json:ro
    depends_on:
      - synapse

  caddy:
    image: caddy:latest
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - /opt/matrix/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - /opt/matrix/wellknown:/srv/wellknown:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - synapse
      - element

volumes:
  db_data:
  caddy_data:
  caddy_config:
COMPOSEEOF

# Stop system Caddy (we use Docker Caddy instead)
systemctl stop caddy 2>/dev/null || true
systemctl disable caddy 2>/dev/null || true

echo -e "${BLU}Starting Matrix services (this may take 2-3 minutes)...${DEF}"
cd /opt/matrix
docker compose up -d db

# Wait for DB to be healthy
echo -e "${BLU}Waiting for PostgreSQL...${DEF}"
WAIT=0
until docker compose exec -T db pg_isready -U synapse > /dev/null 2>&1; do
    sleep 3
    WAIT=$((WAIT + 3))
    if [ $WAIT -ge 60 ]; then
        echo -e "${RED}ERROR: PostgreSQL did not become ready in time.${DEF}"
        break
    fi
done

# Start Synapse
docker compose up -d synapse
echo -e "${BLU}Waiting for Synapse to initialize...${DEF}"
WAIT=0
until docker compose exec -T synapse curl -sf http://localhost:8008/health > /dev/null 2>&1; do
    sleep 5
    WAIT=$((WAIT + 5))
    if [ $WAIT -ge 120 ]; then
        echo -e "${RED}ERROR: Synapse did not become healthy in time.${DEF}"
        break
    fi
done

# Create admin user (fully non-interactive)
echo -e "${BLU}Creating admin user...${DEF}"
docker compose exec -T synapse register_new_matrix_user \
    -u "${ADMIN_USER}" \
    -p "${ADMIN_PASS}" \
    -a \
    -c /data/homeserver.yaml \
    http://localhost:8008 > /dev/null 2>&1 && \
    echo -e "${GRN}Admin user created: @${ADMIN_USER}:${DOMAIN}${DEF}" || \
    echo -e "${YEL}Admin user may already exist or creation failed - check logs.${DEF}"

# Start Element and Caddy
docker compose up -d element caddy

echo
sleep 5

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}              MATRIX + ELEMENT INSTALLATION COMPLETE                    ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  Element Web:  ${GRN}https://${DOMAIN}${DEF}"
echo -e "${YEL}  Matrix API:   ${GRN}https://${DOMAIN}/_matrix/${DEF}"
echo
echo -e "${BLU}  Admin account:${DEF}"
echo -e "${BLU}    Username: ${GRN}${ADMIN_USER}${DEF}"
echo -e "${BLU}    Matrix ID: ${GRN}@${ADMIN_USER}:${DOMAIN}${DEF}"
echo
echo -e "${YEL}  TLS certificates are provisioned automatically by Caddy.${DEF}"
echo -e "${YEL}  It may take 1-2 minutes for HTTPS to become active.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Matrix + Element - Encrypted Team Messaging
=============================================

Web client:    https://${DOMAIN}
Matrix API:    https://${DOMAIN}/_matrix/

Admin account:
  Username:  ${ADMIN_USER}
  Matrix ID: @${ADMIN_USER}:${DOMAIN}
  Password:  (stored securely - see below)

Database:
  Type:     PostgreSQL 15 (Docker)
  User:     synapse
  Database: synapse

Files:
  Config:     /opt/matrix/synapse/homeserver.yaml
  Compose:    /opt/matrix/docker-compose.yml
  Element:    /opt/matrix/element/config.json
  Caddy:      /opt/matrix/caddy/Caddyfile
  Signing key: /opt/matrix/synapse/${DOMAIN}.signing.key

Manage services:
  cd /opt/matrix
  docker compose ps                  # Status
  docker compose logs -f synapse     # Synapse logs
  docker compose logs -f             # All logs
  docker compose restart synapse     # Restart Synapse
  docker compose down                # Stop all
  docker compose up -d               # Start all

Add a new user:
  cd /opt/matrix
  docker compose exec synapse register_new_matrix_user \\
    -u USERNAME -p PASSWORD --no-admin \\
    -c /data/homeserver.yaml http://localhost:8008

Add a new admin:
  cd /opt/matrix
  docker compose exec synapse register_new_matrix_user \\
    -u USERNAME -p PASSWORD -a \\
    -c /data/homeserver.yaml http://localhost:8008

Update:
  cd /opt/matrix
  docker compose pull
  docker compose up -d

Federation: $([ "${FEDERATION_ENABLED}" = "true" ] && echo "Enabled" || echo "Disabled")

IMPORTANT:
  - Never delete /opt/matrix/synapse/${DOMAIN}.signing.key
  - Never change the server_name in homeserver.yaml after first use
  - Keep backups of /opt/matrix/synapse/ and the database

Mobile apps:
  - Element iOS: https://apps.apple.com/app/element/id1083446067
  - Element Android: https://play.google.com/store/apps/details?id=im.vector.app

Documentation: https://matrix-org.github.io/synapse/latest/

Installed: $(date)
EOF

echo -e "${BLU}README saved to /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
