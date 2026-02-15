#!/bin/bash
# setup-ssl.sh - Professional Nginx & SSL Provisioner
# Usage: ./setup-ssl.sh <domain> <project_root> [public_folder_OR_type] [type]

set -e

DOMAIN=$1
WEBROOT=$2
ARG3=$3
ARG4=$4

# 🔍 Auto-detect PHP version and Socket path
PHP_V=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.2")
PHP_SOCK="/var/run/php/php$PHP_V-fpm.sock"

NGINX_AVAILABLE="/etc/nginx/sites-available/$DOMAIN"
NGINX_ENABLED="/etc/nginx/sites-enabled/$DOMAIN"
SSL_PATH="/etc/nginx/ssl/$DOMAIN"
ACME_BIN="$HOME/.acme.sh/acme.sh"

# 🛑 Basic Validation
if [[ -z "$DOMAIN" || -z "$WEBROOT" ]]; then
    echo "❌ Missing arguments!"
    echo "Usage: $0 <domain> <project_root> [subfolder] [type]"
    echo "Examples:"
    echo "  Laravel:  $0 api.com /var/www/api public"
    echo "  Vue Dist: $0 app.com /var/www/app dist spa"
    echo "  Vue Root: $0 app.com /var/www/app spa"
    exit 1
fi

if [ ! -f "$ACME_BIN" ]; then
    echo "❌ acme.sh not found at $ACME_BIN. Please install it first."
    exit 1
fi

# 🧠 Smart Argument Detection
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
    TRY_FILES="try_files \$uri \$uri/ /index.html;"
else
    MODE_MSG="PHP / Laravel (Detecting PHP $PHP_V)"
    TRY_FILES="try_files \$uri \$uri/ /index.php?\$query_string;"
fi

echo "------------------------------------------------"
echo "🔹 Website:    $DOMAIN"
echo "📂 Root Path:  $WEBROOT"
echo "🌍 Site Root:  $SITE_ROOT"
echo "⚙️  Mode:       $MODE_MSG"
echo "------------------------------------------------"

# 3️⃣ Create Directories & Set Permissions
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

# 4️⃣ HTTP Config (Challenge Mode)
echo "🔹 Creating temporary HTTP config..."
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
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_SOCK;
    }

    location ~ /\.(?!well-known).* { deny all; }
}
EOL
sudo ln -sf "$NGINX_AVAILABLE" "$NGINX_ENABLED"

# 5️⃣ Test & Reload
sudo nginx -t && sudo systemctl reload nginx

# 6️⃣ SSL Issue (Using ECC for better performance)
echo "🔹 Issuing certificate (Let's Encrypt ECC)..."
$ACME_BIN --set-default-ca --server letsencrypt
$ACME_BIN --issue -d "$DOMAIN" -w "$SITE_ROOT" --keylength ec-256 || true

# 7️⃣ Install Cert
echo "🔹 Installing certificate to $SSL_PATH..."
$ACME_BIN --install-cert -d "$DOMAIN" --ecc \
    --key-file       "$SSL_PATH/key.pem" \
    --fullchain-file "$SSL_PATH/fullchain.pem" \
    --reloadcmd      "sudo systemctl reload nginx"

# 8️⃣ Final HTTPS Config
echo "🔹 Updating Nginx config for HTTPS & Security..."
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

    # SSL Config
    ssl_certificate      $SSL_PATH/fullchain.pem;
    ssl_certificate_key  $SSL_PATH/key.pem;
    ssl_protocols        TLSv1.2 TLSv1.3;
    ssl_ciphers          ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "no-referrer-when-downgrade";

    location / {
        $TRY_FILES
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_SOCK;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
    location ~ /\.(?!well-known).* { deny all; }
}
EOL

# 9️⃣ Final Test
sudo nginx -t && sudo systemctl reload nginx

echo "✅ $DOMAIN setup complete with HTTPS!"
