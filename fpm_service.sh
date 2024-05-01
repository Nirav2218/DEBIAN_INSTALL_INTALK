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
# Install $env_PHP_VERSION-FPM and necessary extensions
apt update -y 
apt install -y $env_PHP_VERSION-fpm $env_PHP_VERSION-mysql $env_PHP_VERSION-gd $env_PHP_VERSION-xml $env_PHP_VERSION-mbstring

# Start $env_PHP_VERSION-FPM and enable it to start on boot
systemctl start $env_$env_PHP_VERSION_VERSION-fpm
systemctl enable $env_$env_PHP_VERSION_VERSION-fpm

if [[ "$env_MULTI_APP" == "n" || "$env_MULTI_APP" == "N" ]]; then
    cp $env_USER_HOME_DIR/www.conf /etc/php/7.4/fpm/pool.d/
else
    cp $env_USER_HOME_DIR/www2.conf /etc/php/7.4/fpm/pool.d/
    mv /etc/php/7.4/fpm/pool.d/www2.conf www.conf
fi

mkdir -p /var/www/html

INTALK_CODE_FILE="intalk.io"
found_file=$(find . -type f -name "${INTALK_CODE_FILE}_v*.tgz")
if [ -e "$found_file" ]; then
    tar -xvzf "$found_file"
    mv OpenCC "$OPENCC_FOLDER" -f
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

systemctl restart $env_PHP_VERSION_VERSION-fpm

log_message "PHP-FPM installed, configured successfully."
