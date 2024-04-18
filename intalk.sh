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

INTALK_CODE_FILE=intalk.io
HTTPD_CONF=/etc/apache2/apache2.conf
PHPINI=/etc/php/7.4/cli/php.ini
HTML_FOLDER=/var/www/html
OPENCC_FOLDER=/var/www/html/openpbx
LOG_FILE="/var/log/intalk_sh.log"

today=$(date +"%Y-%m-%d")

sed -i /cdrom/s/^/#/ /etc/apt/sources.list

DEBIAN_VERSION=$(cat /etc/debian_version)
DEBIAN_VERSION=${DEBIAN_VERSION%%.*}
if [[ $DEBIAN_VERSION == "11" ]]; then
  log_message "Debian 11"
else
  log_message "Only support debian 11....Please Install Debian 11.***  version OS in Server"
  exit
fi

if [ ! -f /usr/local/init.txt ]; then
  apt-get install -y gdev
  apt-get install -y openssl
  apt-get install -y shc
  apt-get install -y xterm
  apt-get install -y jq
  apt update -y
  add-apt-repository ppa:rock-core/qt4
  add-apt-repository ppa:ubuntuhandbook1/ppa
  log_message "init" >/usr/local/init.txt
  apt install -y sshpass
fi
ip_addr=$(ip route get 8.8.8.8 | awk '/src/ {print $7}')
clear
INTALK_VERSION=$(log_message "$JSON" | jq -r .INTALK_VERSION)

log_message "Start time is: $(date +%r)"

log_message -e "

                            * **.**.**,*****,*
                     **.                          **
                **                                     **.
              *                                            .*
          *                                                   **
        *                                                       **
      *,                                                          **
                                                                    *.
  ###                                           (##.   ###           **
                        (##*                    (##.   ###             ### 
  ###   (##  #####*   #########    #####/ ###   (##.   ###     ###,
  ###   ,###(    ###    (##*     ###*    ####   (##.   ###  (###       ### 
  ###   ,##(     ###    /##*    (##.      ###   (##.   #######         ###  ######### 
  ###   ,##(     ###    (##*    /##(      ###   (##.   ### ####        ###  ###   ### 
  ###   ,##(     ###     ######  (###########   (##.   ###   /###  ##  ###  ######### 
  *                                                                    .*
   *                                                                  .*
    *                                                               .*
     **                                                            *.
       *                                                         ,*
         *                                                     **
            *                                                **
              **                                         ,*,
                   **                                .**
                        ** *.                 ****,
                                    . .                   "

set -a
INTALK_CODE_FILE=$INTALK_CODE_FILE
INTALK_VERSION=$INTALK_VERSION
HTTPD_CONF=$HTTPD_CONF
PHPINI=$PHPINI
HTML_FOLDER=$HTML_FOLDER
OPENCC_FOLDER=$OPENCC_FOLDER
set +a
chmod 777 *.sh

export $(grep '^env_' configuration.ini | sed 's/\[Variables\]//;s/^env_/env_/;s/ = /=/')

file_url=$env_PACKAGE_URL

# Download the file using wget
wget "$file_url"

# Check if download was successful
if [ $? -eq 0 ]; then
  log_message "File downloaded successfully"

  # Extract the downloaded file
  tar -xvf "$(basename "$file_url")"
  if [ $? -eq 0 ]; then
    log_message "Files extracted successfully"
  else
    log_message "Error: Failed to extract the files"
    exit 1
  fi
else
  log_message "Error: Failed to download the file"
  exit 1
fi

sed -i "s/DEFINER=\`opencc\`@\`localhost\`//g" *.sql
sed -i "s/DEFINER=\`root\`@\`localhost\`//g" *.sql

# log_message "Before executing startm.sh"
./startm.sh | tee -a "OUTPUT$today.log"
log_message "After executing startm.sh"

log_message "............ "
log_message "End time is: $(date +%r)"
