#!/bin/bash
# setup-ssl.sh
# Usage: ./setup-ssl.sh <domain> <project_root> [public_folder_OR_type] [type]

set -e

DOMAIN=$1
WEBROOT=$2
ARG3=$3
ARG4=$4

NGINX_AVAILABLE="/etc/nginx/sites-available/$DOMAIN"
NGINX_ENABLED="/etc/nginx/sites-enabled/$DOMAIN"
SSL_PATH="/etc/nginx/ssl/$DOMAIN"

if [[ -z "$DOMAIN" || -z "$WEBROOT" ]]; then
    echo "Usage: $0 <domain> <project_root> [subfolder] [type]"
    echo "Examples:"
    echo "  Laravel:  $0 api.com /var/www/api public"
    echo "  Vue Dist: $0 app.com /var/www/app dist spa"
    echo "  Vue Root: $0 app.com /var/www/app spa"
    exit 1
fi

# 🧠 Smart Argument Detection
# If the 3rd argument is "spa" or "php", treat it as the TYPE, and assume Root folder.
if [[ "$ARG3" == "spa" || "$ARG3" == "php" ]]; then
    SUBFOLDER=""
    APP_TYPE="$ARG3"
else
    SUBFOLDER="$ARG3"
    APP_TYPE="$ARG4"
fi

# 1️⃣ Determine Site Root
if [[ -n "$SUBFOLDER" && "$SUBFOLDER" != "null" ]]; then
    SUBFOLDER="${SUBFOLDER#/}" # Remove leading slash
    SITE_ROOT="$WEBROOT/$SUBFOLDER"
else
    SITE_ROOT="$WEBROOT"
fi

# 2️⃣ Determine Nginx Routing Logic
if [[ "$APP_TYPE" == "spa" ]]; then
    MODE_MSG="Single Page App (Vue/Angular/React)"
    # SPA falls back to index.html for client-side routing
    TRY_FILES="try_files \$uri \$uri/ /index.html;"
else
    MODE_MSG="PHP / Laravel"
    # PHP falls back to index.php
    TRY_FILES="try_files \$uri \$uri/ /index.php?\$query_string;"
fi

echo "🔹 Setting up website: $DOMAIN"
echo "📂 Project Path: $WEBROOT"
echo "🌍 Public Root:  $SITE_ROOT"
echo "⚙️  Mode:        $MODE_MSG"

# 3️⃣ Create Directories
sudo mkdir -p "$WEBROOT"
sudo chown -R $USER:www-data "$WEBROOT"
sudo chmod -R 755 "$WEBROOT"

if [[ "$SITE_ROOT" != "$WEBROOT" ]]; then
    sudo mkdir -p "$SITE_ROOT"
    sudo chown -R $USER:www-data "$SITE_ROOT"
    sudo chmod -R 755 "$SITE_ROOT"
fi

sudo mkdir -p "$SSL_PATH"
sudo chown -R $USER:root "$SSL_PATH"
sudo chmod -R 755 "$SSL_PATH"

# 4️⃣ HTTP Config
echo "🔹 Creating temporary Nginx HTTP config..."
sudo tee "$NGINX_AVAILABLE" > /dev/null <<EOL
server {
    listen 80;
    server_name $DOMAIN;
    root $SITE_ROOT;
    index index.html index.php;

    location / {
        $TRY_FILES
    }

    location ~ \.php\$ {
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* { deny all; }
}
EOL
sudo ln -sf "$NGINX_AVAILABLE" "$NGINX_ENABLED"

# 5️⃣ Test & Reload
if ! sudo nginx -t; then echo "❌ Nginx Config Error"; exit 1; fi
sudo systemctl reload nginx

# 6️⃣ SSL Issue
echo "🔹 Issuing certificate..."
HOME=/home/$USER ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
HOME=/home/$USER ~/.acme.sh/acme.sh --issue -d "$DOMAIN" -w "$SITE_ROOT" || true

# 7️⃣ Install Cert
echo "🔹 Installing certificate..."
~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --key-file       "$SSL_PATH/key.pem" \
    --fullchain-file "$SSL_PATH/fullchain.pem" \
    --reloadcmd      "sudo systemctl reload nginx"

# 8️⃣ HTTPS Config
echo "🔹 Updating Nginx config for HTTPS..."
sudo tee "$NGINX_AVAILABLE" > /dev/null <<EOL
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    root $SITE_ROOT;
    index index.html index.php;

    ssl_certificate     $SSL_PATH/fullchain.pem;
    ssl_certificate_key $SSL_PATH/key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    location / {
        $TRY_FILES
    }

    location ~ \.php\$ {
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
    location ~ /\.(?!well-known).* { deny all; }
}
EOL

# 9️⃣ Final Test
if ! sudo nginx -t; then echo "❌ HTTPS Config Error"; exit 1; fi
sudo systemctl reload nginx

echo "✅ $DOMAIN setup complete!"
