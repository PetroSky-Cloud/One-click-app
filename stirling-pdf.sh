#!/bin/bash

RED='\e[31m'
BLU='\e[34m'
GRN='\e[32m'
YEL='\033[0;33m'
DEF='\e[0m'

echo -e ${GRN} "Installing system utils" ${DEF}
apt-get -qqq -y install curl net-tools > /dev/null 2>&1

echo
echo
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo -e ${GRN} "# ${BLU}WELCOME TO STIRLING-PDF INSTALL SCRIPT                        ${GRN}#"
echo -e ${GRN} "# ------------------------------------------------------------- #"
echo
echo -e ${YEL}

printf "%s" "Please enter Domain Name, or hit enter for insecure installation: "
read DOMAIN

echo -e ${DEF}

echo -e ${BLU} "Installing Docker..." ${DEF}
curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/docker.sh | bash

echo -e ${BLU} "Creating Stirling-PDF directories..." ${DEF}
mkdir -p /opt/stirling-pdf/{configs,logs,pipeline}

echo -e ${BLU} "Creating Docker Compose file..." ${DEF}
cat > /opt/stirling-pdf/docker-compose.yml << 'EOFCOMPOSE'
services:
  stirling-pdf:
    image: stirlingtools/stirling-pdf:latest
    container_name: stirling-pdf
    ports:
      - '127.0.0.1:8080:8080'
    volumes:
      - ./configs:/configs
      - ./logs:/logs
      - ./pipeline:/pipeline
    environment:
      - DOCKER_ENABLE_SECURITY=false
      - SECURITY_ENABLELOGIN=false
      - LANGS=en_GB
    restart: unless-stopped
EOFCOMPOSE

if [ "$DOMAIN" = "" ]; then
    echo -e ${GRN} "Installing without TLS - exposing port 8080 directly" ${DEF}
    sed -i "s/127.0.0.1:8080:8080/8080:8080/" /opt/stirling-pdf/docker-compose.yml
else
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8080 false
fi

echo -e ${BLU} "Starting Stirling-PDF..." ${DEF}
cd /opt/stirling-pdf
docker compose pull
docker compose up -d

sleep 10

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:8080"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                  STIRLING-PDF INSTALLATION COMPLETE                    ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  No login required - PDF tools available immediately.${DEF}"
echo
if [ -n "$DOMAIN" ]; then
    echo -e "${BLU}  TIP: Port 8080 is bound to localhost only (secure).${DEF}"
    echo
fi
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Stirling-PDF
============

Access: ${ACCESS_URL}

No login required - all PDF tools available immediately.

Features:
  - Merge, split, rotate, compress PDFs
  - Convert to/from images, Word, Excel
  - OCR, watermarks, signatures
  - 60+ PDF operations

Manage Stirling-PDF:
  cd /opt/stirling-pdf
  docker compose ps              # Check status
  docker compose logs -f         # View logs
  docker compose restart         # Restart service
  docker compose pull && docker compose up -d  # Update

Data Location:
  /opt/stirling-pdf/configs/     # Settings
  /opt/stirling-pdf/logs/        # Logs
  /opt/stirling-pdf/pipeline/    # Automation configs

Enable Login (optional):
  Edit docker-compose.yml and set:
    SECURITY_ENABLELOGIN=true
  Then: docker compose up -d

Documentation: https://docs.stirlingpdf.com/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
