#!/bin/bash
LOG_FILE="/var/log/$(basename "$0").log"

# Log message function
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >>"$LOG_FILE"
}

cd $env_USER_HOME_DIR

if [ "$(lsb_release -is)" != "Debian" ]; then
    log_message "This script is designed for Debian-based systems only. Exiting."
    exit 1
fi
apt update -y
apt-get install -y $env_PHP_VERSION 

OPENCC_FOLDER="/var/www/html/openpbx"
if [ ! -d "$OPENCC_FOLDER" ]; then
    mkdir -p /var/www/html/openpbx
    INTALK_CODE_FILE="intalk.io"
    found_file=$(find . -type f -name "${INTALK_CODE_FILE}_v*.tgz")
    # Extract the found file to the OpenCC directory
    if [ -e "$found_file" ]; then
        tar -xvzf "$found_file"
        log_message "Contents of $found_file extracted"
    else
        log_message "OpenCC code file not found: $found_file"
    fi
    cp -r OpenCC/DBDiff "$OPENCC_FOLDER"/

fi

export $(grep '^env_' configuration.ini | sed 's/\[Variables\]//;s/^env_/env_/;s/ = /=/')

# Define the desired MariaDB version
MARIADB_VERSION=$env_DB_VERSION

# Comment out CDROM sources in /etc/apt/sources.list
sed -i '/cdrom/s/^/#/' /etc/apt/sources.list

# Paths and service names
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
SERVICE_NAME="mariadb"

# Check if the daemon group exists; if not, create it
if grep -q daemon /etc/group; then
    echo "Group 'daemon' exists."
else
    echo "Creating group 'daemon'..."
    groupadd daemon
fi

# Create Freeswitch user if it doesn't exist
if id "freeswitch" >/dev/null 2>&1; then
    echo "User 'freeswitch' exists."
else
    echo "Creating user 'freeswitch'..."
    useradd -M -s /usr/sbin/nologin -g daemon freeswitch
fi

# Check for MariaDB service
# if systemctl --all --type service | grep -q "$SERVICE_NAME"; then
#     echo "$SERVICE_NAME service exists. Skipping MariaDB installation."
# else
echo "Installing MariaDB $MARIADB_VERSION..."

# Add MariaDB repository and key
apt-get install -y software-properties-common
apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc'
add-apt-repository "deb [arch=amd64] http://mirror.jaleco.com/mariadb/repo/$MARIADB_VERSION/debian buster main"

# Update package index and install MariaDB and dependencies
apt-get update -y
apt-get  install -y mariadb-server unixodbc unixodbc-dev odbcinst libreadline-dev libhiredis-dev uuid-dev libsndfile-dev libvpx-dev php-mysql

sed -i 's/^bind-address\s*=\s*127\.0\.0\.1/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf

# Set MariaDB root password
if mysqladmin -u root password 'agami210' 2>>"$LOG_FILE"; then
    log_message "MariaDB root password set successfully."
else
    log_message "Failed to set MariaDB root password. Check logs for details."
    exit 1
fi
# Create FreeSwitch database and user
mysql -u root -pagami210 -e "CREATE DATABASE IF NOT EXISTS freeswitch"
mysql -u root -pagami210 -e "GRANT ALL PRIVILEGES ON freeswitch.* TO opencc@localhost IDENTIFIED BY 'opencc'"
mysql -u root -pagami210 -e "FLUSH PRIVILEGES"
mysql -u root -pagami210 -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY 'agami210' WITH GRANT OPTION;"
# mysql -u root -pagami210 -e "GRANT CREATE ROUTINE ON *.* TO 'root'@'%' IDENTIFIED BY 'agami210';"
# mysql -u root -pagami210 -e "GRANT SUPER ON *.* TO 'root'@'%';"
echo "
CREATE USER 'opencc'@'%' IDENTIFIED BY 'opencc';
ALTER USER 'root'@'localhost' IDENTIFIED BY 'agami210';
GRANT ALL PRIVILEGES ON *.* TO 'opencc'@'%';
FLUSH PRIVILEGES;
" | mysql -u root -pagami210
systemctl restart mariadb
# fi


log_message "MariaDB installation finished."
