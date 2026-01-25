One-Click App Scripts
=====================

Self-hosted app installers for VPS deployment.
Target: Ubuntu 24.04 LTS

FOLDER STRUCTURE
----------------
/*.sh        Interactive scripts (user runs after SSH, prompts for domain/email)
/init/       Cloud-init bootstrap (WHMCS Smarty templates, two-stage install)

UTILITIES
---------
docker.sh    Install Docker CE (auto-detects Debian/Ubuntu)
             Usage: curl -s https://...docker.sh | bash

caddy.sh     Reverse proxy + automatic Let's Encrypt TLS
             Usage: curl -s https://...caddy.sh | bash -s -- DOMAIN PORT SECURE
             - DOMAIN: your domain (must point to server IP)
             - PORT: upstream app port (e.g., 5678 for n8n)
             - SECURE: true if upstream uses HTTPS, false for HTTP
             Waits for DNS propagation before requesting certificate.

AVAILABLE APPS
--------------
App            Type              Port   Install Path         Data Location
-----------    ---------------   ----   -----------------    -------------------
n8n            Docker Compose    5678   /opt/n8n             Docker volumes
vaultwarden    Docker            8000   /opt/vaultwarden     /vw-data/
uptime-kuma    Docker Compose    3001   /opt/uptime-kuma     Docker volumes
pocketbase     Binary+systemd    8090   /opt/pocketbase      /opt/pocketbase/pb_data
gitea          Binary+systemd    3003   /opt/gitea           /opt/gitea/repos
mattermost     apt package       8065   /opt/mattermost      /opt/mattermost/data
nextcloud      Docker AIO        11000  Docker volumes       Docker volumes
umami          Node.js+pm2       3000   /opt/umami           PostgreSQL
supabase       Docker Compose    9001   /opt/supabase-proj   Docker volumes
plausible      Docker Compose    80/443 /opt/plausible-ce    Docker volumes
rocketchat     Docker Compose    8000   /opt/rocketchat      Docker volumes
meilisearch    Binary+systemd    7700   /opt/meilisearch     /opt/meilisearch/data
jitsi          Docker Compose    443    /opt/jitsi           Docker volumes
penpot         Docker Compose    9001   /opt/penpot          Docker volumes
appwrite       Docker            80     Docker managed       Docker volumes
coolify        Official          8000   /data/coolify        /data/coolify/source/.env

UPDATE COMMANDS (per app)
-------------------------
n8n:
  cd /opt/n8n && docker compose pull && docker compose up -d

vaultwarden:
  docker pull vaultwarden/server:latest
  docker stop vaultwarden && docker rm vaultwarden
  docker run -d --name vaultwarden --env DOMAIN="https://YOURDOMAIN" \
    -v /vw-data/:/data/ --restart unless-stopped -p 127.0.0.1:8000:80 \
    vaultwarden/server:latest

uptime-kuma:
  cd /opt/uptime-kuma && docker compose pull && docker compose up -d

pocketbase:
  systemctl stop pocketbase
  cd /opt/pocketbase
  wget https://github.com/pocketbase/pocketbase/releases/download/vX.X.X/pocketbase_X.X.X_linux_amd64.zip
  unzip -o pocketbase_*.zip && rm pocketbase_*.zip
  systemctl start pocketbase

gitea:
  systemctl stop gitea
  cd /opt/gitea
  wget -O gitea https://dl.gitea.com/gitea/X.X.X/gitea-X.X.X-linux-amd64
  chmod 755 gitea && chown gitea:gitea gitea
  systemctl start gitea

mattermost (auto-update via apt):
  apt update && apt upgrade mattermost -y

nextcloud (auto-update built-in):
  Access https://YOURDOMAIN:8080 for AIO management interface

umami:
  cd /opt/umami && git pull && pnpm install && pnpm build
  pm2 restart umami

supabase:
  cd /opt/supabase-project && docker compose pull && docker compose up -d

plausible:
  cd /opt/plausible-ce && git pull && docker compose pull && docker compose up -d

rocketchat:
  cd /opt/rocketchat-compose && docker compose pull && docker compose up -d

meilisearch:
  systemctl stop meilisearch
  curl -s https://raw.githubusercontent.com/meilisearch/meilisearch/main/download-latest.sh | bash
  systemctl start meilisearch

coolify (auto-update built-in):
  Managed automatically. Disable: set AUTOUPDATE=false in /data/coolify/source/.env

APPS WITH BUILT-IN AUTO-UPDATE
------------------------------
- Coolify: Updates automatically (can disable)
- Nextcloud AIO: Update button in management UI
- Mattermost: Via apt package manager

BACKUP LOCATIONS
----------------
Always backup these before updates:

App            Backup These
-----------    ------------------------------------------
n8n            /opt/n8n/.env, Docker volumes (db_storage, n8n_storage)
vaultwarden    /vw-data/
pocketbase     /opt/pocketbase/pb_data/
gitea          /opt/gitea/repos/, /opt/gitea/custom/, MySQL dump
mattermost     /opt/mattermost/data/, PostgreSQL dump
umami          PostgreSQL dump, /opt/umami/.env
supabase       /opt/supabase-project/.env, Docker volumes
plausible      /opt/plausible-ce/.env, Docker volumes (ClickHouse data)
rocketchat     /opt/rocketchat-compose/.env, Docker volumes (MongoDB)
meilisearch    /opt/meilisearch/data/
coolify        /data/coolify/source/.env (CRITICAL - backup externally!)

COMMON PORTS
------------
22      SSH
80/443  HTTP/HTTPS (Caddy reverse proxy)
8080    Management interfaces (Nextcloud AIO, Traefik)
3306    MySQL/MariaDB
5432    PostgreSQL
27017   MongoDB

TROUBLESHOOTING
---------------
Docker not starting:
  systemctl status docker
  journalctl -u docker -f

App container not running:
  cd /opt/APP && docker compose ps
  docker compose logs -f

Caddy certificate issues:
  Check DNS: host DOMAIN 1.1.1.1
  Check Caddy logs: journalctl -u caddy -f

Service not starting:
  systemctl status SERVICE
  journalctl -u SERVICE -f

Source: https://github.com/PetroSky-Cloud/One-click-app
