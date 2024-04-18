#!/bin/bash
LOG_FILE="/var/log/$(basename "$0").log"

# Log message function
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >>"$LOG_FILE"
}
# Export environment variables from configuration.ini
export $(grep '^env_' configuration.ini | sed 's/\[Variables\]//;s/^env_/env_/;s/ = /=/')

# Define Redis version
REDIS_VERSION=$env_REDIS_VERSION

log_message "########################################################################################3"
log_message $REDIS_VERSION
# Update package index
apt update -y

# Install essential packages
apt install -y build-essential tcl

# Download and extract Redis source code
wget http://download.redis.io/releases/redis-$REDIS_VERSION.tar.gz
tar xzf redis-$REDIS_VERSION.tar.gz
cd redis-$REDIS_VERSION

# Compile Redis
make

# Install Redis
make install

mkdir -p /etc/redis

# Rename configuration file to redis.conf
ln -s $env_USER_HOME_DIR/redis-$REDIS_VERSION/redis.conf /etc/redis/redis.conf
# Start Redis service
sed -i 's/^daemonize no$/daemonize yes/' /etc/redis/redis.conf
sed -i 's/^port 6379$/port 6379/' /etc/redis/redis.conf
sed -i 's|^logfile ""$|logfile /var/log/redis.log|' /etc/redis/redis.conf

if [[ $env_MULTI_APP == N ]]; then
    sed -i 's/^# requirepass foobared$/requirepass opencc/' /etc/redis/redis.conf
fi

sed -i 's/bind 127.0.0.1/bind 0.0.0.0/' /etc/redis/redis.conf

# Create symbolic link to Redis server binary
ln -s $env_USER_HOME_DIR/redis-$REDIS_VERSION/src/redis-server /usr/local/bin/redis-server

# Create systemd service file
cat >/etc/systemd/system/redis.service <<EOF
[Unit]
Description=Redis Datastore
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/bin/redis-server /etc/redis/redis.conf
Restart=always

[Install]
WantedBy=multi-user.target


EOF

# Reload systemd
systemctl daemon-reload

# Start Redis service
systemctl start redis

# Enable Redis service to start on boot
systemctl enable redis

# Verify Redis installation
redis-cli --version

# Clean up
cd ..
rm -rf redis-$REDIS_VERSION.tar.gz

log_message "Redis $REDIS_VERSION has been installed and configured."
