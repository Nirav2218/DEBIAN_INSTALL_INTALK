#!/bin/bash
LOG_FILE="/var/log/$(basename "$0").log"

# Log message function
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >>"$LOG_FILE"
}
export $(grep '^env_' configuration.ini | sed 's/\[Variables\]//;s/^env_/env_/;s/ = /=/')

cd $env_USER_HOME_DIR
# Install essential packages
apt update -y
apt install -y cmake make net-tools shc vim
apt-get install -y liblua5.3-dev
apt-get install -y lua5.3
apt-get install unixodbc-bin
apt install -y libmariadb3 libmariadb-dev
apt install -y odbc-mariadb



# Check for unsupported OS versions
if grep -qi "ERROR" /var/log/common.log; then
    log_message "Only Debian 11 is supported. Please install Debian 11."
    exit 1
fi

# Install git if not already installed
if ! command -v git &>/dev/null; then
    apt install -y git
else
    log_message "Git is already installed."
fi

# Install MariaDB and dependencies
apt install -y mariadb-server unixodbc unixodbc-dev odbcinst libreadline-dev libhiredis-dev software-properties-common uuid-dev libsndfile-dev libvpx-dev php-mysql

# Update package index and install coturn
apt install -y coturn

# Start and enable coturn service
systemctl enable coturn && systemctl start coturn

# Install sox for merging WAV files
apt install -y sox

# Set MariaDB root password
mysqladmin -u root password 'agami210'

# Create FreeSwitch database and user
mysql -h$env_FS_DB_HOST -u root -pagami210 -e "CREATE DATABASE IF NOT EXISTS freeswitch"
mysql -h$env_FS_DB_HOST -u root -pagami210 -e "GRANT ALL PRIVILEGES ON freeswitch.* TO opencc@localhost IDENTIFIED BY 'opencc'"
mysql -h$env_FS_DB_HOST -u root -pagami210 -e "FLUSH PRIVILEGES"

cat <<EOF >/etc/odbc.ini
[freeswitch]
Driver   = MySQL
SERVER   = ${env_FS_DB_HOST}
PORT    = 3306
DATABASE = freeswitch
OPTION  = 67108864
Socket   = /var/lib/mysql/mysql.sock
threading=0
MaxLongVarcharSize=65536

[opencc]
Driver   =  MariaDB Unicode
SERVER   = ${env_OPENCC_DB_HOST}
PORT    = 3306
DATABASE = opencc
OPTION  = 67108864
Socket   = /var/lib/mysql/mysql.sock
threading=0
EOF

# Install FreeSwitch dependencies
apt install -yq gnupg2 wget lsb-release build-essential libjpeg-dev libpng-dev yasm libvpx-dev libopus-dev libsndfile1-dev
apt-get build-dep -y freeswitch

# Add SignalWire repository
TOKEN="pat_7w1ESBGwWh791eHY1FwZmSVr"
apt-get update -y && apt-get install -yq gnupg2 wget lsb-release
wget --http-user=signalwire --http-password=$TOKEN -O /usr/share/keyrings/signalwire-freeswitch-repo.gpg https://freeswitch.signalwire.com/repo/deb/debian-release/signalwire-freeswitch-repo.gpg

echo "machine freeswitch.signalwire.com login signalwire password $TOKEN" >/etc/apt/auth.conf
chmod 600 /etc/apt/auth.conf
echo "deb [signed-by=/usr/share/keyrings/signalwire-freeswitch-repo.gpg] https://freeswitch.signalwire.com/repo/deb/debian-release/ $(lsb_release -sc) main" >/etc/apt/sources.list.d/freeswitch.list
echo "deb-src [signed-by=/usr/share/keyrings/signalwire-freeswitch-repo.gpg] https://freeswitch.signalwire.com/repo/deb/debian-release/ $(lsb_release -sc) main" >>/etc/apt/sources.list.d/freeswitch.list

apt-get update -y

# Install dependencies required for the build
apt-get build-dep freeswitch -y

# then let's get the source. Use the -b flag to get a specific branch
cd /usr/src/
git clone https://github.com/signalwire/freeswitch.git -bv1.10 freeswitch
cd freeswitch

# ... and do the build
./bootstrap.sh -j
./configure
make
make install

cd $env_USER_HOME_DIR
# Create Freeswitch user and set permissions
groupadd -f daemon
useradd -M -s /usr/sbin/nologin -g daemon freeswitch

wget $env_MEDIA_SOURCE
tar -xvf "$(basename "$env_MEDIA_SOURCE")"
cd Install_MediaServer
tar -xvzf freeswitch*.tgz
cd usr/local/src/freeswitch_*
scp -r conf scripts /usr/local/freeswitch/
cd $env_USER_HOME_DIR

ln -s /usr/local/freeswitch/bin/freeswitch /usr/bin/freeswitch
ln -s /usr/local/freeswitch/bin/fs_cli /usr/bin/fs_cli
chown -R freeswitch:daemon /usr/local/freeswitch/
chmod -R ug=rwX,o= /usr/local/freeswitch/
chmod -R u=rwx,g=rx /usr/local/freeswitch/bin/
chown freeswitch:daemon /usr/local/freeswitch -R
chmod g+w /usr/local/freeswitch -R

systemctl start freeswitch.service

cd $env_USER_HOME_DIR/lua-5.3.5
make linux test
make install
cd $env_USER_HOME_DIR

# Create symbolic links and enable FreeSwitch service
ln -sf /usr/src/freeswitch/build/freeswitch.service /etc/systemd/system/freeswitch.service
systemctl daemon-reload
systemctl enable freeswitch.service
systemctl restart freeswitch.service

# Check FreeSWITCH service status
if systemctl is-active --quiet freeswitch; then
    # Print log message if service is running
    log_message "Installation and configuration completed successfully."
else
    log_message "FreeSWITCH service is not running."
fi

cp /usr/local/freeswitch/conf/vanilla/freeswitch.xml /usr/local/freeswitch/conf
sed -i 's/vanilla\///' /usr/local/freeswitch/conf/freeswitch.xml

app_ip_addr=$env_APP_IP_FOR_ACL_IN_MEDIA

sed -i '3i\<list name="loopback.auto" default="deny">' /usr/local/freeswitch/conf/autoload_configs/acl.conf.xml
sed -i '4i\  <!-- Add a node to allow IP address 192.168.1.41 -->' /usr/local/freeswitch/conf/autoload_configs/acl.conf.xml
sed -i "5i\\  <node type=\"allow\" cidr=\"$app_ip_addr\/32\"\/>" /usr/local/freeswitch/conf/autoload_configs/acl.conf.xml
sed -i '6i\</list>' /usr/local/freeswitch/conf/autoload_configs/acl.conf.xml

sed -i 's/<param name="listen-ip" value="::"\/>/<param name="listen-ip" value="0.0.0.0"\/>/g' /usr/local/freeswitch/conf/autoload_configs/event_socket.conf.xml
sed -i 's/^\s*<!--<param name="apply-inbound-acl" value="loopback.auto"\/>-->/    <param name="apply-inbound-acl" value="lan"\/>/g' /usr/local/freeswitch/conf/autoload_configs/event_socket.conf.xml

cp freeswitch.service /etc/systemd/system/

systemctl daemon-reload
systemctl enable freeswitch.service
#systemctl enable freeswitch
systemctl start freeswitch.service
