#!/bin/bash
LOG_FILE="/var/log/$(basename "$0").log"

# Log message function
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >>"$LOG_FILE"
}
# Load environment variables from config.ini
export $(grep '^env_' configuration.ini | sed 's/\[Variables\]//;s/^env_/env_/;s/ = /=/')
key=$env_KEY
intalk_src=$(find . -type f -name "intalk.io_v*.tgz")

ip_addr=$(ip route get 8.8.8.8 | awk '/src/ {print $7}')

do_connection() {
    local ip="$1"
    local pass="$2"
    local auth="$3"
    local key="$4"
    if [[ "$auth" == 'a' || "$auth" == 'A' ]]; then
        log_message "it's key based authentication"
        if [ "$ip" != "$ip_addr" ]; then
            log_message "ssh -i $key $env_USER_NAME@$ip"
            if ssh -i "$key" "$env_USER_NAME@$ip" 'sudo bash -s' -- "$ip" <coninit.sh; then
                log_message "Connection established with $ip"
            else
                log_message "Connection failed with $ip"
                read -p "Do you still want to continue (yes/no)? " yn
                if [[ "$yn" =~ ^[Nn][Oo]$ ]]; then
                    exit 1
                fi
            fi
        fi
    else
        if [ "$ip" != "$ip_addr" ]; then
            log_message "sshpass -p '$pass' ssh $env_USER_NAME@$ip"
            if sshpass -p "$pass" ssh "$env_USER_NAME@$ip" 'sudo bash -s' -- "$ip" <coninit.sh; then
                log_message "Connection established with $ip"
            else
                log_message "Connection failed with $ip"
                read -p "Do you still want to continue (yes/no)? " yn
                if [[ "$yn" =~ ^[Nn][Oo]$ ]]; then
                    exit 1
                fi
            fi
        fi
    fi
}

# install database service
db_service() {
    local ip="$1"
    local pass="$2"
    local auth="$3"
    local key="$4"
    if [[ "$auth" == 'a' || "$auth" == 'A' ]]; then
        if [ "$ip" != "$ip_addr" ]; then
            scp -i "$key" -r configuration.ini "$intalk_src" intalk_appointment_db.sql intalk_tiss_db.sql intalk_helpinbox_db.sql intalk_icici_db.sql intalk_db.sql intalk.io_extra_dialplans.sql lib64 db_service.sh post.sh "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if ssh -i "$key" "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/db_service.sh" | tee -a output.log; then
                log_message "Database service installation successful on $ip"
            else
                log_message "Error: Database service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/db_service.sh" | tee -a output.log
        fi
    else
        if [ "$ip" != "$ip_addr" ]; then
            sshpass -p "$pass" scp -r configuration.ini "$intalk_src" intalk_appointment_db.sql intalk_tiss_db.sql intalk_helpinbox_db.sql intalk_icici_db.sql intalk_db.sql intalk.io_extra_dialplans.sql lib64  db_service.sh post.sh "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if sshpass -p "$pass" ssh "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/db_service.sh" | tee -a output.log; then
                log_message "Database service installation successful on $ip"
            else
                log_message "Error: Database service installation failed on $ip"
            fi
        else
            sshpass -p "$pass" ssh "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/db_service.sh" | tee -a output.log
        fi
    fi
}

nginx_service() {
    local ip="$1"
    local pass="$2"
    local auth="$3"
    local key="$4"
    if [[ "$auth" == 'a' || "$auth" == 'A' ]]; then
        if [ "$ip" != "$ip_addr" ]; then
            scp -i "$key" -r configuration.ini opencc* intalk_nginx.conf nginx_service.sh intalk_db.sql intalk_tiss_db.sql intalk_appointment_db.sql "$intalk_src" post.sh "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if ssh -i "$key" "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/nginx_service.sh" | tee -a output.log; then
                log_message "App service installation successful on $ip"
            else
                log_message "Error: App service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/nginx_service.sh" | tee -a output.log
        fi
    else
        if [ "$ip" != "$ip_addr" ]; then
            sshpass -p "$pass" scp -r configuration.ini opencc* intalk_nginx.conf nginx_service.sh "$intalk_src" post.sh "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if sshpass -p "$pass" ssh "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/nginx_service.sh" | tee -a output.log; then
                log_message "App service installation successful on $ip"
            else
                log_message "Error: App service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/nginx_service.sh" | tee -a output.log
        fi
    fi
}

fpm_service() {
    local ip="$1"
    local pass="$2"
    local auth="$3"
    local key="$4"
    if [[ "$auth" == 'a' || "$auth" == 'A' ]]; then
        if [ "$ip" != "$ip_addr" ]; then
            scp -i "$key" -r configuration.ini www.conf www2.conf "$intalk_src" fpm_service.sh "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if ssh -i "$key" "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/fpm_service.sh" | tee -a output.log; then
                log_message "FPM service installation successful on $ip"
            else
                log_message "Error: FPM service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/fpm_service.sh" | tee -a output.log
        fi
    else
        if [ "$ip" != "$ip_addr" ]; then
            sshpass -p "$pass" scp -r configuration.iniwww.conf www2.conf "$intalk_src" fpm_service.sh "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if sshpass -p "$pass" ssh "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/fpm_service.sh" | tee -a output.log; then
                log_message "FPM service installation successful on $ip"
            else
                log_message "Error: FPM service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/fpm_service.sh" | tee -a output.log
        fi
    fi
}

# media service
media_service() {
    local ip="$1"
    local pass="$2"
    local auth="$3"
    local key="$4"
    if [[ "$auth" == 'a' || "$auth" == 'A' ]]; then
        if [ "$ip" != "$ip_addr" ]; then
            scp -i "$key" -r opencc* freeswitch.service media_service.sh configuration.ini lua-5.3.5 post.sh "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if ssh -i "$key" "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/media_service.sh" | tee -a output.log; then
                log_message "Media service installation successful on $ip"
            else
                log_message "Error: Media service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/media_service.sh" | tee -a output.log
        fi
    else
        if [ "$ip" != "$ip_addr" ]; then
            sshpass -p"$pass" scp -r opencc* freeswitch.service configuration.ini media_service.sh lua-5.3.5 post.sh "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if sshpass -p "$pass" ssh "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/media_service.sh" | tee -a output.log; then
                log_message "Media service installation successful on $ip"
            else
                log_message "Error: Media service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/media_service.sh" | tee -a output.log
        fi
    fi
}
redis_service() {
    local ip="$1"
    local pass="$2"
    local auth="$3"
    local key="$4"
    if [[ "$auth" == 'a' || "$auth" == 'A' ]]; then
        if [ "$ip" != "$ip_addr" ]; then
            scp -i "$key" -r configuration.ini redis_service.sh "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if ssh -i "$key" "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/redis_service.sh" | tee -a output.log; then
                log_message "Redis service installation successful on $ip"
            else
                log_message "Error: Redis service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/redis_service.sh" | tee -a output.log
        fi
    else
        if [ "$ip" != "$ip_addr" ]; then
            sshpass -p"$pass" scp -r configuration.ini redis_service.sh "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if sshpass -p "$pass" ssh "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/redis_service.sh" | tee -a output.log; then
                log_message "Redis service installation successful on $ip"
            else
                log_message "Error: Redis service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/redis_service.sh" | tee -a output.log
        fi
    fi
}

#kamaillio
kamailio_service() {
    local ip="$1"
    local pass="$2"
    local auth="$3"
    local key="$4"
    if [[ "$auth" == 'a' || "$auth" == 'A' ]]; then
        if [ "$ip" != "$ip_addr" ]; then
            scp -i "$key" -r configuration.ini kamailio_service.sh $env_KAMAILIO_SRC "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if ssh -i "$key" "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/kamailio_service.sh" | tee -a output.log; then
                log_message "kamailio service installation successful on $ip"
            else
                log_message "Error: kamailio service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/kamailio_service.sh" | tee -a output.log
        fi
    else
        if [ "$ip" != "$ip_addr" ]; then
            sshpass -p"$pass" scp -r configuration.ini kamailio_service.sh $env_KAMAILIO_SRC "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if sshpass -p "$pass" ssh "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/kamailio_service.sh" | tee -a output.log; then
                log_message "kamailio service installation successful on $ip"
            else
                log_message "Error: kamailio service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/kamailio_service.sh" | tee -a output.log
        fi
    fi
}


app_service() {
    local ip="$1"
    local pass="$2"
    local auth="$3"
    local key="$4"
    if [[ "$auth" == 'a' || "$auth" == 'A' ]]; then
        if [ "$ip" != "$ip_addr" ]; then
            scp -i "$key" -r opencc* app_service.sh "$intalk_src" post.sh default_ssl.conf "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if ssh -i "$key" "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/app_service.sh" | tee -a output.log; then
                log_message "app service installation successful on $ip"
            else
                log_message "Error: app service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/app_service.sh" | tee -a output.log
        fi
    else
        if [ "$ip" != "$ip_addr" ]; then
            sshpass -p"$pass" scp -r opencc* app_service.sh "$intalk_src" post.sh default_ssl.conf  "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if sshpass -p "$pass" ssh "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/app_service.sh" | tee -a output.log; then
                log_message "app service installation successful on $ip"
            else
                log_message "Error: app service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/app_service.sh" | tee -a output.log
        fi
    fi
}


# node service
node_service() {
    local ip="$1"
    local pass="$2"
    local auth="$3"
    local key="$4"
    if [[ "$auth" == 'a' || "$auth" == 'A' ]]; then
        if [ "$ip" != "$ip_addr" ]; then
            scp -i "$key" -r opencc* node_service.sh "$intalk_src" post.sh "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if ssh -i "$key" "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/node_service.sh" | tee -a output.log; then
                log_message "Node service installation successful on $ip"
            else
                log_message "Error: Node service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/node_service.sh" | tee -a output.log
        fi
    else
        if [ "$ip" != "$ip_addr" ]; then
            sshpass -p"$pass" scp -r opencc* node_service.sh "$intalk_src" post.sh "$env_USER_NAME@$ip":$env_USER_HOME_DIR
            if sshpass -p "$pass" ssh "$env_USER_NAME@$ip" "sudo bash $env_USER_HOME_DIR/node_service.sh" | tee -a output.log; then
                log_message "Node service installation successful on $ip"
            else
                log_message "Error: Node service installation failed on $ip"
            fi
        else
            sudo bash "$env_USER_HOME_DIR/node_service.sh" | tee -a output.log
        fi
    fi
}

apt update -y
apt-get install -y ansible
cat <<EOF >post.yml
---
- name: Copy and execute shell script
  hosts: nodes
  become: yes
  tasks:
    - name: Copy config.ini
      copy:
        src: /var/www/html/openpbx/config.ini
        dest: /var/www/html/openpbx/config.ini

    - name: Execute shell script on remote hosts
      command: /bin/bash ${env_USER_HOME_DIR}/post.sh | tee -a post_output.log
EOF

intalk_src=$(find . -type f -name "intalk.io_v*.tgz")

log_message "What are you using for authentication? Please select A or B...."
read -p "A. Key-based authentication  B. Password-based authentication " auth
log_message "How many instances do you have?"
read -r no_instance

# New part
declare -A instance_details
for ((i = 1; i <= no_instance; i++)); do
    read -p "Please give the IP of instance $i: " ip_input
    if [[ "$auth" == 'a' || "$auth" == 'A' ]]; then
        instance_details["$ip_input"]="hello"
    else
        read -p "Please give the password for $ip_input: " pass_input
        instance_details["$ip_input"]="$pass_input"
    fi

    do_connection "$ip_input" "${instance_details[$ip_input]}" "$auth" "$key"

    for service in fpm_service nginx_service db_service node_service redis_service media_service kamailio_service app_service; do
        read -p "Do you want to install $service on $ip_input? (y/n): " yn
        case $yn in
        [Yy]*)
            "$service" "$ip_input" "${instance_details[$ip_input]}" "$auth" "$key"
            ;;
        [Nn]*)
            log_message "User doesn't want to install $service on $ip_input"
            ;;
        esac
    done
done
