#!/bin/bash
# setup-ssl.sh

set -e

DOMAIN=$1
WEBROOT=$2
ARG3=$3
ARG4=$4

# 🔍 Auto-detect PHP version to avoid hardcoding 8.2
PHP_V=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.2")
PHP_SOCK="/var/run/php/php$PHP_V-fpm.sock"

NGINX_AVAILABLE="/etc/nginx/sites-available/$DOMAIN"
NGINX_ENABLED="/etc/nginx/sites-enabled/$DOMAIN"
SSL_PATH="/etc/nginx/ssl/$DOMAIN"
ACME_BIN="$HOME/.acme.sh/acme.sh"

if [[ -z "$DOMAIN" || -z "$WEBROOT" ]]; then
    echo "Usage: $0 <domain> <project_root> [subfolder] [type]"
    exit 1
fi

# ... [Your Smart Argument Detection Logic is excellent, keep it] ...

# 3️⃣ Create Directories (Adding a check for acme.sh)
if [ ! -f "$ACME_BIN" ]; then
    echo "❌ acme.sh not found at $ACME_BIN. Please install it first."
    exit 1
fi

# ... [Sections 4 & 5] ...

# 6️⃣ SSL Issue (Refined with --ecc for modern security)
echo "🔹 Issuing certificate (ECDSA)..."
$ACME_BIN --set-default-ca --server letsencrypt
$ACME_BIN --issue -d "$DOMAIN" -w "$SITE_ROOT" --keylength ec-256 || true

# 7️⃣ Install Cert
echo "🔹 Installing certificate..."
$ACME_BIN --install-cert -d "$DOMAIN" --ecc \
    --key-file       "$SSL_PATH/key.pem" \
    --fullchain-file "$SSL_PATH/fullchain.pem" \
    --reloadcmd      "sudo systemctl reload nginx"

# 8️⃣ HTTPS Config (Using the detected PHP_SOCK)
# Inside your EOL block, replace the hardcoded sock with:
# fastcgi_pass unix:$PHP_SOCK;
