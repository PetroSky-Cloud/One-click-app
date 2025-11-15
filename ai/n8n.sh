#!/bin/bash
#
# n8n One-Click Install using Docker
# For ModulesGarden Proxmox VE VPS & Cloud
# Compatible with Ubuntu 24.04 LTS, Proxmox 8.4, WHMCS 8.13.1
#
# n8n is an extendable workflow automation tool
# Official docs: https://docs.n8n.io/
#

# ============================================================================
# CONFIGURATION - CORRECT SMARTY VARIABLES
# ============================================================================

# Service Information (from WHMCS)
SERVICE_ID="{$service.id}"
SERVICE_PASSWORD="{$service.password}"
SERVICE_DOMAIN="{$service.domain}"
SERVICE_IP="{$service.dedicatedip}"

# Config Information (Cloud-Init specific)
CONFIG_USER="{$config.ciuser}"
CONFIG_PASSWORD="{$config.password}"

# Client Information
CLIENT_EMAIL="{$client.email}"
CLIENT_NAME="{$client.companyname}"

# App Template Settings for n8n
# These should be configured in WHMCS App Template as text fields:
# - postgres_user (default: n8n_admin)
# - postgres_password (auto-generate recommended)
# - postgres_db_user (default: n8n_user)
# - postgres_db_password (auto-generate recommended)
POSTGRES_USER="{$config.postgres_user}"
POSTGRES_PASSWORD="{$config.postgres_password}"
POSTGRES_DB_USER="{$config.postgres_db_user}"
POSTGRES_DB_PASSWORD="{$config.postgres_db_password}"

# Custom Fields (if configured)
SSH_PUBLIC_KEY="{$params.customfields.sshkeys}"

# Order Information
ORDER_ID="{$order.id}"

{literal}
set -euo pipefail

# ============================================================================
# LOGGING SETUP
# ============================================================================

LOGFILE="/var/log/n8n-cloudinit-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=================================="
echo "n8n Workflow Automation Installation Started"
echo "Timestamp: $(date)"
echo "Service ID: $SERVICE_ID"
echo "Service Domain: $SERVICE_DOMAIN"
echo "Service IP: $SERVICE_IP"
echo "Client: $CLIENT_NAME"
echo "Order ID: $ORDER_ID"
echo "=================================="

# ============================================================================
# DISABLE AUTOMATIC UPDATES (TEMPORARY)
# ============================================================================

echo "[$(date)] Disabling automatic updates temporarily..."

systemctl stop unattended-upgrades.service 2>/dev/null || true
systemctl mask unattended-upgrades.service 2>/dev/null || true

pkill -9 unattended-upgr 2>/dev/null || true
sleep 1
pkill -9 apt-get 2>/dev/null || true
pkill -9 apt 2>/dev/null || true
sleep 1

rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
rm -f /var/lib/dpkg/lock 2>/dev/null || true
rm -f /var/cache/apt/archives/lock 2>/dev/null || true
rm -f /var/lib/apt/lists/lock 2>/dev/null || true

dpkg --configure -a 2>/dev/null || true
apt-get install -f -y 2>/dev/null || true

echo "[$(date)] System ready for package installation"

# ============================================================================
# INITIAL SYSTEM SETUP
# ============================================================================

echo "[$(date)] Setting hostname and passwords..."

if [ -n "$SERVICE_DOMAIN" ]; then
    hostnamectl set-hostname "$SERVICE_DOMAIN"
    echo "[$(date)] Hostname set to: $SERVICE_DOMAIN"
fi

PASSWORD_TO_USE=""
if [ -n "$CONFIG_PASSWORD" ] && [ "$CONFIG_PASSWORD" != "{config.password}" ]; then
    PASSWORD_TO_USE="$CONFIG_PASSWORD"
    echo "[$(date)] Using config password"
elif [ -n "$SERVICE_PASSWORD" ] && [ "$SERVICE_PASSWORD" != "{service.password}" ]; then
    PASSWORD_TO_USE="$SERVICE_PASSWORD"
    echo "[$(date)] Using service password"
fi

if [ -n "$PASSWORD_TO_USE" ]; then
    echo "root:$PASSWORD_TO_USE" | chpasswd > /dev/null 2>&1
    echo "[$(date)] Root password updated"
else
    echo "[$(date)] WARNING: No password configured!"
fi

if [ -n "$CONFIG_USER" ] && [ "$CONFIG_USER" != "{config.ciuser}" ] && [ "$CONFIG_USER" != "root" ]; then
    if [ -n "$PASSWORD_TO_USE" ]; then
        useradd -m -s /bin/bash "$CONFIG_USER" 2>/dev/null || true
        echo "$CONFIG_USER:$PASSWORD_TO_USE" | chpasswd > /dev/null 2>&1
        usermod -aG sudo "$CONFIG_USER"
        echo "[$(date)] Created user: $CONFIG_USER with sudo access"
    fi
fi

# ============================================================================
# SETUP SSH KEY (if provided)
# ============================================================================

if [ -n "$SSH_PUBLIC_KEY" ] && [ "$SSH_PUBLIC_KEY" != "{params.customfields.sshkeys}" ]; then
    echo "[$(date)] Setting up SSH key..."
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "[$(date)] SSH key configured"
fi

# ============================================================================
# VALIDATE DATABASE CREDENTIALS
# ============================================================================

echo "[$(date)] Validating database credentials..."

# Set defaults if not provided
if [ -z "$POSTGRES_USER" ] || [ "$POSTGRES_USER" = "{config.postgres_user}" ]; then
    POSTGRES_USER="n8n_admin"
    echo "[$(date)] Using default postgres admin user: $POSTGRES_USER"
fi

if [ -z "$POSTGRES_PASSWORD" ] || [ "$POSTGRES_PASSWORD" = "{config.postgres_password}" ]; then
    POSTGRES_PASSWORD="$(openssl rand -base64 32 | tr -d /=+ | head -c 24)"
    echo "[$(date)] Generated random postgres admin password"
fi

if [ -z "$POSTGRES_DB_USER" ] || [ "$POSTGRES_DB_USER" = "{config.postgres_db_user}" ]; then
    POSTGRES_DB_USER="n8n_user"
    echo "[$(date)] Using default postgres database user: $POSTGRES_DB_USER"
fi

if [ -z "$POSTGRES_DB_PASSWORD" ] || [ "$POSTGRES_DB_PASSWORD" = "{config.postgres_db_password}" ]; then
    POSTGRES_DB_PASSWORD="$(openssl rand -base64 32 | tr -d /=+ | head -c 24)"
    echo "[$(date)] Generated random postgres database password"
fi

POSTGRES_DB="n8n"

echo "[$(date)] Database credentials configured"

# ============================================================================
# UPDATE PACKAGE LISTS AND INSTALL DOCKER
# ============================================================================

echo "[$(date)] Updating package lists..."
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

echo "[$(date)] Installing Docker..."

# Install prerequisites
apt-get install -y -qq \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  ca-certificates curl gnupg

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
apt-get update -qq
apt-get install -y -qq \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify installation
if ! command -v docker >/dev/null 2>&1; then
    echo "[$(date)] ERROR: Docker installation failed"
    exit 1
fi

echo "[$(date)] Docker installed successfully"

# Enable and start Docker
systemctl enable docker > /dev/null 2>&1
systemctl start docker

# ============================================================================
# SETUP N8N WITH DOCKER COMPOSE
# ============================================================================

echo "[$(date)] Setting up n8n with Docker Compose..."

mkdir -p /opt/n8n
cd /opt/n8n

# Create .env file with credentials
cat > .env << 'EOFENV'
POSTGRES_USER=PLACEHOLDER_PG_USER
POSTGRES_PASSWORD=PLACEHOLDER_PG_PASS
POSTGRES_DB=PLACEHOLDER_PG_DB

POSTGRES_NON_ROOT_USER=PLACEHOLDER_DB_USER
POSTGRES_NON_ROOT_PASSWORD=PLACEHOLDER_DB_PASS
EOFENV

# Replace placeholders with actual values
sed -i "s|PLACEHOLDER_PG_USER|$POSTGRES_USER|g" .env
sed -i "s|PLACEHOLDER_PG_PASS|$POSTGRES_PASSWORD|g" .env
sed -i "s|PLACEHOLDER_PG_DB|$POSTGRES_DB|g" .env
sed -i "s|PLACEHOLDER_DB_USER|$POSTGRES_DB_USER|g" .env
sed -i "s|PLACEHOLDER_DB_PASS|$POSTGRES_DB_PASSWORD|g" .env

chmod 600 .env

echo "[$(date)] Environment file created"

# Create docker-compose.yml
cat > docker-compose.yml << 'EOFDOCKER'
version: '3.8'

volumes:
  db_storage:
  n8n_storage:

services:
  postgres:
    image: postgres:16
    restart: always
    environment:
      - POSTGRES_USER
      - POSTGRES_PASSWORD
      - POSTGRES_DB
      - POSTGRES_NON_ROOT_USER
      - POSTGRES_NON_ROOT_PASSWORD
    volumes:
      - db_storage:/var/lib/postgresql/data
      - ./init-data.sh:/docker-entrypoint-initdb.d/init-data.sh
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -h localhost -U ${POSTGRES_USER} -d ${POSTGRES_DB}']
      interval: 5s
      timeout: 5s
      retries: 10

  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: always
    environment:
      - N8N_SECURE_COOKIE=false
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_NON_ROOT_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_NON_ROOT_PASSWORD}
    ports:
      - 5678:5678
    links:
      - postgres
    volumes:
      - n8n_storage:/home/node/.n8n
    depends_on:
      postgres:
        condition: service_healthy
EOFDOCKER

echo "[$(date)] Docker Compose configuration created"

# Create PostgreSQL initialization script
cat > init-data.sh << 'EOFINIT'
#!/bin/bash
set -e

if [ -n "${POSTGRES_NON_ROOT_USER:-}" ] && [ -n "${POSTGRES_NON_ROOT_PASSWORD:-}" ]; then
	psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
		CREATE USER ${POSTGRES_NON_ROOT_USER} WITH PASSWORD '${POSTGRES_NON_ROOT_PASSWORD}';
		GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_NON_ROOT_USER};
		GRANT CREATE ON SCHEMA public TO ${POSTGRES_NON_ROOT_USER};
	EOSQL
else
	echo "SETUP INFO: No Environment variables given!"
fi
EOFINIT

chmod 755 init-data.sh

echo "[$(date)] PostgreSQL initialization script created"

# ============================================================================
# START N8N SERVICES
# ============================================================================

echo "[$(date)] Starting n8n services with Docker Compose..."

docker compose up -d

# Wait for services to start
echo "[$(date)] Waiting for services to initialize..."
sleep 10

# Check if containers are running
if docker ps | grep -q n8n-n8n; then
    echo "[$(date)] n8n container is running"
else
    echo "[$(date)] WARNING: n8n container may not be running properly"
    docker compose logs
fi

# ============================================================================
# DETECT ACCESS URL
# ============================================================================

echo "[$(date)] Detecting access URL..."

if [ -n "$SERVICE_IP" ] && [ "$SERVICE_IP" != "0.0.0.0" ] && [ "$SERVICE_IP" != "{service.dedicatedip}" ]; then
    ACCESS_URL="http://$SERVICE_IP:5678"
    echo "[$(date)] Access URL: $ACCESS_URL"
elif [ -n "$SERVICE_DOMAIN" ] && [ "$SERVICE_DOMAIN" != "{service.domain}" ]; then
    ACCESS_URL="http://$SERVICE_DOMAIN:5678"
    echo "[$(date)] Access URL: $ACCESS_URL"
else
    PUBLIC_IP=$(curl -4 -s --max-time 10 ifconfig.me 2>/dev/null || curl -4 -s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
    ACCESS_URL="http://$PUBLIC_IP:5678"
    echo "[$(date)] Access URL: $ACCESS_URL"
fi

# ============================================================================
# CREATE README AND CREDENTIALS FILE
# ============================================================================

cat > /root/README.txt << EOFREADME
n8n Workflow Automation Server

Access n8n:
$ACCESS_URL

First-time setup:
1. Open the URL above in your browser
2. Create your admin account
3. Start building workflows

Database credentials (saved in /opt/n8n/.env):
- PostgreSQL Admin: $POSTGRES_USER
- Database Name: $POSTGRES_DB
- n8n Database User: $POSTGRES_DB_USER

Manage services:
cd /opt/n8n
docker compose logs -f              # View logs
docker compose restart              # Restart services
docker compose down                 # Stop services
docker compose up -d                # Start services

Documentation:
https://docs.n8n.io/

Installed: $(date)
EOFREADME

# Create credentials file (secure)
cat > /root/n8n-credentials.txt << EOFCREDS
n8n Installation Credentials
============================

Access URL: $ACCESS_URL

Database Credentials:
--------------------
PostgreSQL Admin User: $POSTGRES_USER
PostgreSQL Admin Password: $POSTGRES_PASSWORD
Database Name: $POSTGRES_DB
n8n Database User: $POSTGRES_DB_USER
n8n Database Password: $POSTGRES_DB_PASSWORD

Service Information:
-------------------
Service ID: $SERVICE_ID
Service Domain: $SERVICE_DOMAIN
Client Email: $CLIENT_EMAIL
Order ID: $ORDER_ID

Installation Date: $(date)
EOFCREDS

chmod 600 /root/n8n-credentials.txt

echo "[$(date)] Documentation created in /root/README.txt"
echo "[$(date)] Credentials saved in /root/n8n-credentials.txt"

# ============================================================================
# RE-ENABLE AUTOMATIC UPDATES
# ============================================================================

echo "[$(date)] Re-enabling automatic updates..."
systemctl unmask unattended-upgrades.service 2>/dev/null || true
systemctl enable unattended-upgrades.service 2>/dev/null || true

echo "[$(date)] System will update automatically in the background"

# ============================================================================
# FINAL STATUS
# ============================================================================

echo "=================================="
echo "n8n Installation Completed Successfully!"
echo "Timestamp: $(date)"
echo "Access URL: $ACCESS_URL"
echo "README: /root/README.txt"
echo "Credentials: /root/n8n-credentials.txt"
echo "=================================="

# Display container status
docker compose ps

echo ""
echo "Next steps:"
echo "1. Open $ACCESS_URL in your browser"
echo "2. Create your admin account"
echo "3. Start building workflows"
echo ""
echo "NOTE: On first access, n8n will prompt you to create an owner account."
echo "Use $CLIENT_EMAIL as your email address."

# ============================================================================
# END OF SCRIPT
# ============================================================================
{/literal}
