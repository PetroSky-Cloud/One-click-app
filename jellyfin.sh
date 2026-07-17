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
echo -e ${GRN} "# ${BLU}WELCOME TO JELLYFIN INSTALL SCRIPT                            ${GRN}#"
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

echo -e ${BLU} "Creating Jellyfin directories..." ${DEF}
mkdir -p /opt/jellyfin/{config,cache}
mkdir -p /media/{movies,tvshows,music}

DEVICE_ARGS=""
if [ -e /dev/dri ]; then
    DEVICE_ARGS="--device /dev/dri:/dev/dri"
fi

cat > /opt/jellyfin/run.sh << EOF
#!/bin/bash
docker run -d \\
    --name jellyfin \\
    --restart=unless-stopped \\
    -p 8096:8096 \\
    -v /opt/jellyfin/config:/config \\
    -v /opt/jellyfin/cache:/cache \\
    -v /media:/media \\
    ${DEVICE_ARGS} \\
    jellyfin/jellyfin:latest
EOF
chmod +x /opt/jellyfin/run.sh

echo -e ${BLU} "Starting Jellyfin..." ${DEF}
bash /opt/jellyfin/run.sh

if [ -n "$DOMAIN" ]; then
    echo -e ${BLU} "Setting up Caddy reverse proxy with TLS..." ${DEF}
    curl -s https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/main/caddy.sh | bash -s -- $DOMAIN 8096 false
fi

sleep 15

MYIP=$(curl -4s --max-time 10 ifconfig.me 2>/dev/null || curl -4s --max-time 10 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

if [ -n "$DOMAIN" ]; then
    ACCESS_URL="https://${DOMAIN}"
else
    ACCESS_URL="http://${MYIP}:8096"
fi

echo
echo -e "${GRN}========================================================================${DEF}"
echo -e "${GRN}                   JELLYFIN INSTALLATION COMPLETE                       ${DEF}"
echo -e "${GRN}========================================================================${DEF}"
echo
echo -e "${YEL}  ACCESS URL:  ${GRN}${ACCESS_URL}${DEF}"
echo
echo -e "${BLU}  Complete the setup wizard to create admin account.${DEF}"
echo
echo -e "${GRN}========================================================================${DEF}"
echo

cat > /root/README.txt << EOF
Jellyfin - Free Media Server
=============================

Access: ${ACCESS_URL}

First-time setup:
  1. Open the URL above
  2. Select language and complete wizard
  3. Create admin account
  4. Add media libraries (Movies, TV, Music)

Media Directories (upload your content here):
  /media/movies    - Movies
  /media/tvshows   - TV Shows
  /media/music     - Music

Upload media via:
  - SFTP/SCP to /media/
  - Mount network shares to /media/
  - Use rclone for cloud storage

Client Apps:
  - Web browser (built-in)
  - Android/iOS: Jellyfin app
  - TV: Android TV, Fire TV, Roku, webOS
  - Desktop: Jellyfin Media Player

Manage Jellyfin:
  docker ps                      # Check status
  docker logs -f jellyfin        # View logs
  docker restart jellyfin        # Restart

Update Jellyfin:
  docker pull jellyfin/jellyfin:latest
  docker stop jellyfin && docker rm jellyfin
  bash /opt/jellyfin/run.sh

Hardware Transcoding:
  /dev/dri is mounted automatically when the host has a GPU
  Enable in Dashboard > Playback > Transcoding

Configuration: /opt/jellyfin/config
Cache: /opt/jellyfin/cache

Documentation: https://jellyfin.org/docs/

Installed: $(date)
EOF

echo -e "${BLU}README: /root/README.txt${DEF}"
echo

rm -f /etc/profile.d/install.sh
