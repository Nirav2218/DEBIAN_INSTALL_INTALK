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
#install docker
# Add Docker's official GPG key:
apt-get update -y
apt-get install ca-certificates curl -y
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    tee /etc/apt/sources.list.d/docker.list >/dev/null
apt-get update -y

apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y


# kamailio

# wget $env_KAMAILIO_URL
kamailio=$env_KAMAILIO_SRC
cp $kamailio /etc
cd /etc
tar -xvf "$kamailio"
mv "$kamailio" /opt
cd /etc/kamailio*

ip_addr=$(ip route get 8.8.8.8 | awk '/src/ {print $7}')
sed -i.bak "s/192.168.1.69/$ip_addr/g" kamailio.cfg
echo "##########################################################################################"

db_server=$env_KAMAILIO_DB
sed -i "s/192.168.1.68:3306/$db_server/g" kamailio.cfg

redis_server=$env_KAMAILIO_REDIS
sed -i "s/addr=192.168.1.68;port=6379/addr=$redis_server;port=6379/g" kamailio.cfg

docker build -t kamailio .
docker run -d --restart always --name kamailio --network host kamailio
docker exec -d kamailio kamcmd -s tcp:$ip_addr:2046 domain.reload
docker exec -d kamailio kamcmd -s tcp:$ip_addr:2046 domain.dump

docker ps