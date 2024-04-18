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

domain_name=$env_DOMAIN_NAME
log_message "Public Domain Name: $domain_name"
log_message "127.0.0.1 $domain_name" >>/etc/hosts
log_message -e "\e[32mIntalk\e[0m"

# Get the script directory
SCRIPTPATH="$(cd "$(dirname "$0")" && pwd)"
OPENCC_FOLDER="/var/www/html/openpbx"

# Check file existence function
check_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        log_message "ERROR: $file does not exist. Please ensure it's available."
    fi
}

# Check if Apache2 service exists and install it if not
# serviceName="apache2"
# if ! systemctl --all --type service | grep -q "$serviceName"; then
log_message "Installing $serviceName..."
apt-get install -y apache2 $env_PHP_VERSION libapache2-mod-$env_PHP_VERSION dos2unix net-tools vim memcached libmemcached-tools
systemctl restart memcached
systemctl enable memcached
apt-get install -y php-mysql
apt-get install -y php-xml
apt-get install -y php-mcrypt
apt-get install -y php-soap
apt-get install -y php-memcache
apt-get install -y php-devel
apt-get install -y php-gd
apt-get install -y php-imap
apt-get install -y php-ldap
apt-get install -y wkhtmltopdf
apt-get install -y Xvfb
apt-get install -y php-redis
apt-get install -y php-curl
a2enmod $env_PHP_VERSION rewrite ssl
systemctl enable apache2
systemctl restart apache2

# Configure php.ini settings
PHPINI="/etc/php/7.4/cli/php.ini"
check_file "$PHPINI"
sed -i "/;date.timezone/s/^;//" "$PHPINI"
sed -i "/date.timezone/s|.*|date.timezone=Asia/Kolkata|" "$PHPINI"
sed -i "/;max_input_vars/s/^;//" "$PHPINI"
sed -i "/max_input_vars/s|.*|max_input_vars=1000|" "$PHPINI"
sed -i "/upload_max_filesize/s|.*|upload_max_filesize=256M|" "$PHPINI"
sed -i "/post_max_size/s|.*|post_max_size=256M|" "$PHPINI"
sed -i "/max_execution_time/s|.*|max_execution_time=1800|" "$PHPINI"
sed -i "/default_socket_timeout/s|.*|default_socket_timeout=60|" "$PHPINI"
sed -i "/memory_limit/s|.*|memory_limit=512M|" "$PHPINI"
sed -i "/display_errors/s|.*|display_errors=On|" "$PHPINI"
sed -i "/log_errors/s|.*|log_errors=On|" "$PHPINI"

cd "$SCRIPTPATH" || { log_message "No path found: $SCRIPTPATH"; }

# Copy default_ssl.conf and configure Apache
cp -rf default_ssl.conf /etc/apache2/sites-enabled/
sed -i '11 b; s/AllowOverride None\b/AllowOverride All/' /etc/apache2/apache2.conf
sed -i 's/^User.*/User freeswitch/' /etc/apache2/apache2.conf
sed -i 's/^Group.*/Group daemon/' /etc/apache2/apache2.conf
sed -i "s/amol_debian.intalk.io/$domain_name/g" /etc/apache2/sites-enabled/default_ssl.conf

systemctl restart apache2
# fi

# Check if OPENPBX directory exists or not
if [[ ! -d "$OPENCC_FOLDER" && ! -L "$OPENCC_FOLDER" ]]; then
    log_message "OPENPBX directory not found: $OPENCC_FOLDER"
fi

log_message "Status OPENPBX: Found"

# Get OpenCC code
INTALK_CODE_FILE="intalk.io"
found_file=$(find . -type f -name "${INTALK_CODE_FILE}_v*.tgz")
if [ -e "$found_file" ]; then
    tar -xvzf "$found_file"
    rm -rf /var/www/html/openpbx
    cp -r OpenCC /var/www/html
    mv /var/www/html/OpenCC /var/www/html/openpbx
else
    log_message "OpenCC code file not found: $found_file"
fi

# Create Freeswitch user and set permissions
if grep -q daemon /etc/group; then
    log_message "group exists"
else
    log_message "group does not exist"
    groupadd daemon
fi

useradd -M -s /usr/sbin/nologin -g daemon freeswitch

chown freeswitch:daemon /var/www/html/openpbx
chown freeswitch:daemon -R /var/www/html/openpbx
chown freeswitch:daemon -R "$OPENCC_FOLDER"

cp opencc* /etc/ssl/certs/

# Navigate to OPENCC_FOLDER and perform cleanup if necessary
cd "$OPENCC_FOLDER" || { log_message "No path found"; }

rm -f core/install/*.text
rm -f resources/config.php
rm -f tools

# Set permissions for directories and files
chown freeswitch:daemon -R /var/www/html/openpbx

# Create an .htaccess file for redirection
cat <<EOF >/var/www/html/.htaccess
RewriteEngine On
RewriteCond %{HTTPS} off
RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
EOF
