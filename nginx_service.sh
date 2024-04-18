#!/bin/bash
LOG_FILE="/var/log/$(basename "$0").log"

# Log message function
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >>"$LOG_FILE"
}

if [ "$(lsb_release -is)" != "Debian" ]; then
    log_message "This script is designed for Debian-based systems only. Exiting."
    exit 1
fi

export $(grep '^env_' configuration.ini | sed 's/\[Variables\]//;s/^env_/env_/;s/ = /=/')
cd $env_USER_HOME_DIR
# Specify the Nginx version to install
nginx_version=$env_NGINX_VERSION

if [ -z "$nginx_version" ]; then
    log_message "No specific Nginx version provided. Installing the latest version."
else
    log_message "Installing Nginx version: $nginx_version"
fi

# Check if Nginx is already installed
if [ -x "$(command -v nginx)" ]; then
    installed_version=$(nginx -v 2>&1 | awk -F '/' '{print $2}')
    if [ "$installed_version" == "$nginx_version" ]; then
        log_message "Nginx $nginx_version is already installed"
        exit 0
    else
        log_message "Nginx is installed but not the desired version"
        exit 1
    fi
fi

# Update package index
log_message "Updating package index..."
apt install -y curl gnupg2 ca-certificates lsb-release debian-archive-keyring

# Download the Nginx signing key and add it to the keyring
curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

# Import the keyring
gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg

# Add the Nginx repository to the sources list
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/debian $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list

# Set package pinning
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx

# Update package index
apt update -y
apt-get install -y mariadb-client
apt-get  install -y $env_PHP_VERSION  dos2unix net-tools vim memcached libmemcached-tools
systemctl restart memcached
systemctl enable memcached
apt-get  install -y php-mysql php-xml  php-soap php-memcache  php-gd php-imap php-ldap wkhtmltopdf  php-redis php-curl
# Install the specific version of Nginx or the latest version
if [ -z "$nginx_version" ]; then
    log_message "Installing the latest version of Nginx..."
    apt install -y nginx
else
    log_message "Installing Nginx $nginx_version..."
    apt install -y nginx="$nginx_version"
fi

# Check if Nginx installation was successful
if [ $? -eq 0 ]; then
    log_message "Nginx installed successfully"
else
    log_message "Error: Nginx installation failed"
    exit 1
fi

# Start Nginx service
log_message "Starting Nginx service..."
systemctl start nginx

# Enable Nginx to start on boot
log_message "Enabling Nginx to start on boot..."
systemctl enable nginx


domain_name=$env_DOMAIN_NAME

# Copy and modify Nginx configuration for the new domain
cp intalk_nginx.conf /etc/nginx/conf.d/$domain_name.conf
sed -i "s/server_name qaint.intalk.cc;/server_name $domain_name;/g" /etc/nginx/conf.d/$domain_name.conf
echo "127.0.0.1 $domain_name" >> /etc/hosts
# Define the folder where OpenCC will be extracted
OPENCC_FOLDER="/var/www/html/"

# Check if the folder exists, and if not, create it
if [ ! -d "$OPENCC_FOLDER" ]; then
    mkdir -p "$OPENCC_FOLDER"
fi

# Locate the OpenCC code file
INTALK_CODE_FILE="intalk.io"
found_file=$(find . -type f -name "${INTALK_CODE_FILE}_v*.tgz")

# Extract the found file to the OpenCC directory
if [ -e "$found_file" ]; then
    tar -xvzf "$found_file" -C "$OPENCC_FOLDER"
    log_message "Contents of $found_file extracted to: $OPENCC_FOLDER"
else
    log_message "OpenCC code file not found: $found_file"
fi

mv "$OPENCC_FOLDER"/OpenCC "$OPENCC_FOLDER"/openpbx

# Create Freeswitch user and set permissions
if grep -q daemon /etc/group; then
    log_message "group exists"
else
    log_message "group does not exist"
    groupadd daemon
fi

useradd -M -s /usr/sbin/nologin -g daemon freeswitch

chown freeswitch:daemon -R "$OPENCC_FOLDER"

cp opencc* /etc/ssl/certs/

cd "$OPENCC_FOLDER" || { echo "No path found"; }

rm -f core/install/*.text
rm -f resources/config.php
rm -f tools

cd $env_USER_HOME_DIR

# Restart Nginx for changes to take effect
log_message "Restarting Nginx..."
systemctl restart nginx

# Navigate to OPENCC_FOLDER and perform cleanup if necessary
cd "$OPENCC_FOLDER" || { log_message "No path found"; }

rm -f core/install/*.text
rm -f resources/config.php
rm -f tools

# Create an .htaccess file for redirection
cat <<EOF >/var/www/html/.htaccess
RewriteEngine On
RewriteCond %{HTTPS} off
RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
EOF

if [ -f "$OPENCC_FOLDER"openpbx/resources/config.php ]; then
    mv "$OPENCC_FOLDER"openpbx/resources/config.php "$OPENCC_FOLDER"openpbx/resources/config.php_bkp
fi

log_message "Nginx installation and configuration completed"
