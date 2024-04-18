#!/bin/bash
export $(grep '^env_' configuration.ini | sed 's/\[Variables\]//;s/^env_/env_/;s/ = /=/')
cd $env_USER_HOME_DIR

# Set log_message file path
LOG_FILE="/var/log/$(basename "$0").log"

# Function to log_message messages with timestamps
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >>"$LOG_FILE"
}
if [ "$(lsb_release -is)" != "Debian" ]; then
    log_message "This script is designed for Debian-based systems only. Exiting."
    exit 1
fi

# Install dos2unix package
apt install -y dos2unix
log_message "dos2unix installed."

# Check if the daemon group exists; if not, create it
if grep -q daemon /etc/group; then
    log_message "Group 'daemon' exists."
else
    log_message "Creating group 'daemon'..."
    groupadd daemon || { log_message "Failed to create group 'daemon'."; }
fi

# Create Freeswitch user if it doesn't exist
if id "freeswitch" >/dev/null 2>&1; then
    log_message "User 'freeswitch' exists."
else
    log_message "Creating user 'freeswitch'..."
    useradd -M -s /usr/sbin/nolog_messagein -g daemon freeswitch || { log_message "Failed to create user 'freeswitch'."; }
fi

nodenode_version=$env_NODE_VERSION
apt remove nodejs npm -y
apt autoremove -y
apt purge nodejs npm -y
# log_message "Installing Node.js version $node_version..."
curl -sL https://deb.nodesource.com/setup_$env_NODE_VERSION.x | bash -
apt update -y
apt-get install -y nodejs

# Check Node.js and npm versions
node --version
npm --version

# Install PM2
log_message "Installing PM2..."
npm install -g pm2

# Check PM2 version
pm2 --version

# Log message for Node.js and PM2 installation
log_message "Node.js and PM2 installed successfully."

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
    cp -r OpenCC/nodejs "$OPENCC_FOLDER"/

    cp opencc.* /var/www/html/openpbx/nodejs
fi

dos2unix "$OPENCC_FOLDER"/nodejs/*.js

NODEJS_FILE="$OPENCC_FOLDER/nodejs/wsssl_opencc.js"
UCP_NODEJS_FILE="$OPENCC_FOLDER/ucp_node/wsssl.js"
# Create and move systemd service files
cat <<EOF >opencc_nodejs.service
[Unit]
Description=OpenCC NodeJS Module
[Service]
ExecStart=/usr/bin/node $NODEJS_FILE
Restart=always
RestartSec=30
User=freeswitch
Group=daemon
Environment=PATH=/usr/bin:/usr/local/bin
Environment=NODE_ENV=production
WorkingDirectory=$OPENCC_FOLDER/nodejs
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >ucp_nodejs.service
[Unit]
Description=UCP NodeJS Module
[Service]
ExecStart=/usr/bin/node $UCP_NODEJS_FILE
Restart=always
RestartSec=30
User=freeswitch
Group=daemon
Environment=PATH=/usr/bin:/usr/local/bin
Environment=NODE_ENV=production
WorkingDirectory=$OPENCC_FOLDER/ucp_node
[Install]
WantedBy=multi-user.target
EOF

mv opencc_nodejs.service /etc/systemd/system || { log_message "Failed to move opencc_nodejs.service."; }
mv ucp_nodejs.service /etc/systemd/system || { log_message "Failed to move ucp_nodejs.service."; }

systemctl daemon-reload || { log_message "Failed to reload systemd."; }
systemctl enable opencc_nodejs || { log_message "Failed to enable opencc_nodejs."; }

systemctl start opencc_nodejs
systemctl status opencc_nodejs

log_message "Installation and configuration completed successfully."
