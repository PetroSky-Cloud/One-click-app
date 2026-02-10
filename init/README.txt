init/ - Cloud-Init Bootstrap Scripts (WHMCS)
============================================

Two-stage installation for ModulesGarden Proxmox VE VPS & Cloud module.
These scripts are pasted into WHMCS App Template "User Data" field.

HOW IT WORKS
------------
Stage 1 - VM Boot (cloud-init):
  1. Installs wget, curl, net-tools
  2. Downloads interactive script to /etc/profile.d/install.sh
  3. Sets hostname from {$service.domain}
  4. Sets root password from {$config.password} or {$service.password}
  5. Creates non-root user from {$config.ciuser} (optional)

Stage 2 - First SSH Login:
  1. /etc/profile.d/install.sh runs automatically
  2. User sees welcome banner, answers prompts (domain, email, etc.)
  3. Application installs with user's input
  4. Script self-removes: rm -f /etc/profile.d/install.sh

WHY TWO-STAGE?
--------------
- Some apps need user input (domain for TLS, admin credentials)
- Cloud-init runs non-interactively at boot
- Two-stage lets user provide input on first SSH login
- Lightweight boot stage = fast VM provisioning

AVAILABLE WHMCS VARIABLES
-------------------------
Service:
  {$service.password}     Service password
  {$service.domain}       Service domain
  {$service.dedicatedip}  Dedicated IP
  {$service.id}           Service ID

Config (App Template fields):
  {$config.password}      Cloud-init password field
  {$config.ciuser}        Cloud-init username field
  {$config.FIELDNAME}     Custom App Template fields

Client:
  {$client.email}         Client email
  {$client.firstname}     Client first name
  {$client.companyname}   Client company

SCRIPT STRUCTURE
----------------
#!/bin/bash

apt-get update
apt-get install -y wget bash curl net-tools

wget -O /etc/profile.d/install.sh -q https://github.com/.../app.sh

SERVICE_PASSWORD="{$service.password}"
SERVICE_DOMAIN="{$service.domain}"
CONFIG_PASSWORD="{$config.password}"
CONFIG_USER="{$config.ciuser}"

{literal}
set -euo pipefail

echo "[$(date)] Installation Started"

# Set hostname
if [ -n "$SERVICE_DOMAIN" ] && [ "$SERVICE_DOMAIN" != "{service.domain}" ]; then
    hostnamectl set-hostname "$SERVICE_DOMAIN"
fi

# Password validation - check WITHOUT $ (Smarty strips it when undefined)
PASSWORD_TO_USE=""
if [ -n "$CONFIG_PASSWORD" ] && [ "$CONFIG_PASSWORD" != "{config.password}" ]; then
    PASSWORD_TO_USE="$CONFIG_PASSWORD"
elif [ -n "$SERVICE_PASSWORD" ] && [ "$SERVICE_PASSWORD" != "{service.password}" ]; then
    PASSWORD_TO_USE="$SERVICE_PASSWORD"
fi

if [ -n "$PASSWORD_TO_USE" ]; then
    echo "root:$PASSWORD_TO_USE" | chpasswd > /dev/null 2>&1
fi

# Create non-root user (optional)
if [ -n "$CONFIG_USER" ] && [ "$CONFIG_USER" != "{config.ciuser}" ] && [ "$CONFIG_USER" != "root" ]; then
    useradd -m -s /bin/bash "$CONFIG_USER" 2>/dev/null || true
    echo "$CONFIG_USER:$PASSWORD_TO_USE" | chpasswd > /dev/null 2>&1
    usermod -aG sudo "$CONFIG_USER"
fi
{/literal}

CRITICAL RULES
--------------
1. Variables use DOUBLE QUOTES: "{$service.password}" not '{$service.password}'
2. Variables declared BEFORE {literal} block
3. All bash code with braces inside {literal}...{/literal}
4. {/literal} MUST have trailing newline (blank line after)
5. Password check uses "{config.password}" WITHOUT $ in comparison
6. No ${VAR:-default} syntax (Smarty parses colons incorrectly)

COMMON MISTAKES
---------------
WRONG: {literal}PASSWORD="{$service.password}"{/literal}
RIGHT: PASSWORD="{$service.password}" then {literal}...{/literal}

WRONG: [ "$VAR" != "{$config.password}" ]
RIGHT: [ "$VAR" != "{config.password}" ]  (no $ in string)

WRONG: VAR="${X:-default}"
RIGHT: VAR="$X"; [ -z "$VAR" ] && VAR="default"

TESTING
-------
After VM deployment:
  cat /var/log/cloud-init-output.log       # See script output
  cat /var/lib/cloud/instance/user-data.txt # See processed script
  cloud-init status --long                  # Check status
