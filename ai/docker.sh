#!/bin/bash
{literal}

set -euo pipefail

# Remove old Docker packages
apt-get remove --purge -y docker.io docker-doc docker-compose podman-docker containerd runc 2>/dev/null || true

# Install prerequisites
apt-get update -qq
apt-get install -y -qq ca-certificates curl

# Detect OS before downloading GPG key
if grep -qio id=debian /etc/os-release; then
    OS_TYPE="debian"
    echo "Debian detected"
elif grep -qio id=ubuntu /etc/os-release; then
    OS_TYPE="ubuntu"
    echo "Ubuntu detected"
else
    echo "Unsupported OS. Only Debian and Ubuntu are supported."
    exit 2
fi

# Download correct GPG key for detected OS
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/$OS_TYPE/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository based on OS
if [ "$OS_TYPE" = "debian" ]; then
    tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
elif [ "$OS_TYPE" = "ubuntu" ]; then
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
fi

# Install Docker
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify installation
if command -v docker >/dev/null 2>&1; then
    echo "Docker installed successfully: $(docker --version)"
else
    echo "ERROR: Docker installation failed"
    exit 1
fi
{/literal}
