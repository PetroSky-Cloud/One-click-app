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
echo -e ${GRN} "# ${BLU}WELCOME TO GRAFANA + PROMETHEUS INSTALL SCRIPT               ${GRN}#"
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

echo -e ${BLU} "Creating directories..." ${DEF}
mkdir -p /opt/monitoring/prometheus
mkdir -p /opt/monitoring/grafana

echo -e ${BLU} "Creating Prometheus configuration..." ${DEF}
cat > /opt/monitoring/prometheus/prometheus.yml << 'EOFPROM'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
EOFPROM

echo -e ${BLU} "Generating Grafana password..." ${DEF}
GRAFANA_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=')

echo -e ${BLU} "Creating Docker Compose file..." ${DEF}
cat > /opt/monitoring/docker-compose.yml << EOFCOMPOSE
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
    ports:
      - '127.0.0.1:9090:9090'
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - '127.0.0.1:3000:3000'
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana-data:/var/lib/grafana
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    command:
      - '--path.rootfs=/host'
    volumes:
      - '/:/host:ro,rslave'
    pid: host
    restart: unless-stopped

volumes:
  prometheus-data:
  grafana-data:
EOFCOMPOSE

if [ "$DOMAIN" = "" ]; then
    echo -e ${GRN} "Installing without TLS - exposing port 3000 directly" ${DEF}
    sed -i "s/127.0.0.1:3000:3000/3000:3000/" /opt/monitoring/docker-compose.yml
    sed -i "s/127.0.0.1:9090:9090/9090:9090/" /opt/monitoring/docker-compose.yml
else
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 3000 false
fi

echo -e ${BLU} "Starting monitoring stack..." ${DEF}
cd /opt/monitoring
docker compose pull
docker compose up -d

sleep 10

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    GRAFANA_URL="https://${DOMAIN}"
    PROMETHEUS_URL="https://${DOMAIN}:9090"
else
    GRAFANA_URL="http://${MYIP}:3000"
    PROMETHEUS_URL="http://${MYIP}:9090"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}             GRAFANA + PROMETHEUS INSTALLATION COMPLETE                 ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  GRAFANA URL:     ${GRN}${GRAFANA_URL}${DEF}"
echo -e "${YEL}  PROMETHEUS URL:  ${GRN}${PROMETHEUS_URL}${DEF}"
echo
echo -e "${BLU}  Grafana Login:${DEF}"
echo -e "${YEL}    Username: ${GRN}admin${DEF}"
echo -e "${YEL}    Password: ${GRN}${GRAFANA_PASSWORD}${DEF}"
echo
echo -e "${BLU}  Add Prometheus as data source: http://prometheus:9090${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Grafana + Prometheus Monitoring Stack
=====================================

Grafana:    ${GRAFANA_URL}
Prometheus: ${PROMETHEUS_URL}

Credentials:
  Username: admin
  Password: ${GRAFANA_PASSWORD}

Quick Start:
  1. Log into Grafana
  2. Go to Configuration > Data Sources > Add
  3. Select Prometheus
  4. URL: http://prometheus:9090
  5. Click Save & Test
  6. Import dashboards (1860 for Node Exporter)

Components:
  - Grafana: Visualization and dashboards
  - Prometheus: Metrics collection and storage
  - Node Exporter: System metrics (CPU, memory, disk, network)

Manage Stack:
  cd /opt/monitoring
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart services
  docker compose pull && docker compose up -d  # Update

Configuration:
  Prometheus config: /opt/monitoring/prometheus/prometheus.yml
  Data volumes: prometheus-data, grafana-data

Add more targets to prometheus.yml and restart Prometheus.

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
