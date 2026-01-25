#!/bin/bash
# Test version - no Smarty syntax (for direct Proxmox testing)

apt-get update
apt-get install -y wget bash curl net-tools

wget -O /etc/profile.d/install.sh -q https://raw.githubusercontent.com/PetroSky-Cloud/One-click-app/refs/heads/main/stirling-pdf.sh

set -euo pipefail

echo "[$(date)] Stirling-PDF Installation Started"

# For testing, we use the cipassword/ciuser from Proxmox cloud-init
# In production WHMCS, these would be Smarty variables

echo "[$(date)] Stirling-PDF init complete - run install.sh on first SSH login"
