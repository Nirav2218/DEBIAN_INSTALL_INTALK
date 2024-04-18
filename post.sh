#! /bin/bash

LOG_FILE="/var/log/$(basename "$0").log"

# Log message function
log_message() {
  local message="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >>"$LOG_FILE"
}

DB_USER=opencc
DB_DB=opencc
DB_PWD=opencc
EXTRA_DIALPLAN_SQL=intalk.io_extra_dialplans.sql
GW_UUID=$(uuidgen)
OPENCC_FOLDER=/var/www/html/openpbx
SOUND_FOLDER=/usr/loacl/freeswitch/sounds

#cd $OPENCC_FOLDER/DB_Schema_C*

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

dos2unix intalk_*db.sql 2>>/dev/null
DB_DB_dummy=$DB_DB""_dummy

log_message "db_operation start"
mysql -u root -pagami210 -e "SET GLOBAL group_concat_max_len = 10240; CREATE DATABASE $DB_DB_dummy; ALTER DATABASE $DB_DB_dummy CHARACTER SET utf8; ALTER DATABASE $DB_DB_dummy COLLATE utf8_general_ci; GRANT ALL PRIVILEGES on $DB_DB_dummy.* to 'opencc'@'%';"
log_message "db dummy created"

mysql -f -u $DB_USER -p$DB_PWD $DB_DB_dummy <intalk_db.sql
mysql -f -u $DB_USER -p$DB_PWD $DB_DB_dummy <intalk_appointment_db.sql
mysql -f -u $DB_USER -p$DB_PWD $DB_DB_dummy <intalk_tiss_db.sql
mysql -f -u $DB_USER -p$DB_PWD $DB_DB_dummy <intalk_helpinbox_db.sql
mysql -f -u $DB_USER -p$DB_PWD $DB_DB_dummy <intalk_icici_db.sql
OLD_PWD=$(pwd)
cd $OPENCC_FOLDER/DBDiff
## ./dbdiff server1.$DB_DB:server2.$DB_DB_dummy
rm -f migration.sql
./dbdiff server1.$DB_DB_dummy:server1.$DB_DB
if [ -f migration.sql ]; then
  dos2unix migration.sql 2>>/dev/null
  mv migration.sql $OLD_PWD
fi
cd - >>/dev/null 2>>/dev/null

mysql -u root -pagami210 -e "DROP DATABASE $DB_DB_dummy"

if [ -f migration.sql ]; then
  log_message "Some correction in DB chema is required"
  mysql -f -u root -pagami210 opencc <migration.sql 2>>/dev/null
  #safer side - executing migration.sql one more time
  log_message "Some final correction in DB chema is required "
  mysql -f -u root -pagami210 opencc <migration.sql 2>>/dev/null
else
  log_message "No DB schema changes"
fi

#update DBschema for charset
DB="$DB_DB"
(
  log_message 'ALTER DATABASE `'"$DB"'` CHARACTER SET utf8 COLLATE utf8_general_ci;'
  mysql -u $DB_USER -p$DB_PWD "$DB" -e "SHOW TABLES" --batch --skip-column-names |
    xargs -I{} log_message 'ALTER TABLE `'{}'` CONVERT TO CHARACTER SET utf8 COLLATE utf8_general_ci;'
) |
  mysql -u $DB_USER -p$DB_PWD "$DB"

#update DB schema for timestamp correction
mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "ALTER TABLE v_login_campaign_break CHANGE available_time available_time TIMESTAMP NULL DEFAULT NULL;"
mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "ALTER TABLE v_login_campaign_break CHANGE offline_time offline_time TIMESTAMP NULL DEFAULT NULL"
mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "ALTER TABLE v_broadcasts_contacts_history CHANGE end_stamp end_stamp TIMESTAMP NULL DEFAULT NULL;"
mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "ALTER TABLE v_broadcasts_contacts_history CHANGE start_stamp start_stamp TIMESTAMP NULL DEFAULT NULL;"
#mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "ALTER TABLE v_call_state CHANGE created_at created_at TIMESTAMP NULL DEFAULT NULL;"
#mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "ALTER TABLE v_call_state CHANGE updated_at updated_at TIMESTAMP NULL DEFAULT NULL;"
mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "ALTER TABLE v_login_campaign CHANGE campaign_login_time campaign_login_time TIMESTAMP NULL DEFAULT NULL;"
mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "ALTER TABLE v_login_campaign CHANGE campaign_logout_time campaign_logout_time TIMESTAMP NULL DEFAULT NULL;"
mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "ALTER TABLE v_break CHANGE deleted_at deleted_at TIMESTAMP NULL DEFAULT NULL;"

#read domain_uuid and domain name
domain_uuid=$(mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "select domain_uuid from v_domains where domain_enabled='true' and domain_description='Default Domain' limit 1;")
domain_name=$(mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "select domain_name from v_domains where domain_enabled='true' and domain_description='Default Domain' limit 1;")

domain_uuid_ho=$(mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "select domain_uuid from v_domains where domain_enabled='true' and domain_description Like '%sub Domain%' limit 1;;")

domain_name_ho=$(mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "select domain_name from v_domains where domain_enabled='true' and domain_description Like '%sub Domain%' limit 1;;")

#execute updated sql statement to create dialplans in FreeSWITCH
mysql -f -p$DB_PWD -u $DB_USER $DB_DB <$EXTRA_DIALPLAN_SQL

#update websocket settings
mysql -p$DB_PWD -u $DB_USER $DB_DB -Be 'INSERT v_websocket_setting SET domain_uuid="'$domain_uuid'", call_socket_url = "wss://'$domain_name':8443", chatsocket_url = "https://'$domain_name':8888", freeswitch_ws = "wss://'$domain_name'", freeswitch_port=9000, freeswitch_url = "'$domain_name'" ;'

#subdomain
mysql -p$DB_PWD -u $DB_USER $DB_DB -Be 'INSERT v_websocket_setting SET domain_uuid="'$domain_uuid_ho'", call_socket_url = "wss://'$domain_name':8443", chatsocket_url = "https://'$domain_name':8888", freeswitch_ws = "wss://'$domain_name'", freeswitch_port=9000, freeswitch_url = "'$domain_name_ho'" ;'

#update wss for FreeSwitch
internal_profile_uuid=$(mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "SELECT sip_profile_uuid FROM v_sip_profiles where sip_profile_name='internal' LIMIT 1;")
new_uuid=$(uuidgen)
mysql -p$DB_PWD -u $DB_USER $DB_DB -Be "INSERT v_sip_profile_settings  SET sip_profile_setting_uuid ='$new_uuid', sip_profile_uuid = '$internal_profile_uuid', sip_profile_setting_name='wss-binding' , sip_profile_setting_value=':9000', sip_profile_setting_enabled='true', sip_profile_setting_description=NULL ;"

#adding default gateway
mysql -p$DB_PWD -u $DB_USER $DB_DB -Be "INSERT INTO v_gateways (gateway_uuid, domain_uuid, gateway, username, password, distinct_to, auth_username, realm, from_user, from_domain, proxy, register_proxy, outbound_proxy, expire_seconds, register, register_transport, retry_seconds, extension, ping, caller_id_in_from, supress_cng, sip_cid_type, codec_prefs, channels, extension_in_contact, context, profile, hostname, enabled, description) VALUES (uuid(),	'$domain_uuid_ho',	'PSTN_PRI',	'not-used',	'not-used',	NULL,	NULL,	NULL,	NULL,	NULL,	'127.0.0.1',	NULL,	NULL,	800,	'false',	NULL,	30,	NULL,	NULL,	NULL,	NULL,	NULL,	NULL,	0,	NULL,	'public',	'internal',	NULL,	'true',	NULL);"
mysql -p$DB_PWD -u $DB_USER $DB_DB -Be "UPDATE v_sip_profile_settings SET sip_profile_setting_value='/usr/local/freeswitch/certs' WHERE sip_profile_uuid = '$internal_profile_uuid' and sip_profile_setting_name = 'tls-cert-dir' ;"

#update SIP ports of FreeSWITCH
mysql -p$DB_PWD -u $DB_USER $DB_DB -Be "UPDATE v_vars SET var_value = 6050 where var_name = 'internal_sip_port' ;"
mysql -p$DB_PWD -u $DB_USER $DB_DB -Be "UPDATE v_vars SET var_value = 6051 where var_name = 'internal_tls_port' ;"

#Version
mysql -p$DB_PWD -N -u $DB_USER $DB_DB -Be "INSERT INTO version (table_name,table_version) VALUES ('location',   9), ('location_attrs',  1), ('subscriber',      7), ('version', 1),('domain', 2),('domain_attrs',1);"

#Add group type operator if does not exist for all sub domains/locations
mysql -u $DB_USER -p$DB_PWD $DB_DB -e "INSERT INTO v_groups (group_uuid, domain_uuid, group_name, group_type)
VALUES (UUID(), NULL, 'Operator', 'operator');"

#default permissions for supervisors
mysql -u $DB_USER -p$DB_PWD $DB_DB -e "INSERT INTO v_permission (permission_uuid, group_uuid,permission_values)
(SELECT UUID(), group_uuid, '[\"Live Dashboard\",\"Live Data\",\"Team status\",\"Call in queue\",\"Logout User\",\"Switch Queue\",\"Call-Hang-up\",\"Transfer Call\",\"Eavesdrop\",\"Conference\",\"whisper\",\"List Statistics\",\"Queue Detail\",\"Supervisor Users Status\",\"Supervisor Users Logout\",\"Campaign Detail\",\"Analytics\",\"Analytics Data\",\"Inbound Dashboard\",\"Outbound Dashboard\",\"Manual Dashboard\",\"Disposition summary\",\"CallBack List\",\"System Disposition Summary Report\",\"Leads\",\"Voice Calls Trend\",\"Average Call Duration Trend\",\"Total Calls\",\"Average Call Duration\",\"Non Connected Calls\",\"Agent Happiness\",\"Call Counts\",\"Call Graph Date wise\",\"Call Graph Status wise\",\"Call-History-Supervisor\",\"cdr-call-detailed-report\",\"Manual Outbound Call Detail Report\",\"Auto Call Distribution Detail Report\",\"Campaign Call Distribution Summary Report\",\"Agent Call Distribution Summary Report\",\"Agent Productivity Report\",\"Abandoned Calls Report\",\"Inbound Performance Report\",\"CallBack Report\",\"Login History Report\",\"Customer Feedback Summary Report\",\"Calls On IVR Report\",\"Calls On IVR Summary Report\",\"Auto Call Distribution Report\",\"Call-List Summary Report\",\"MissedCall Service Summary Report\",\"Call Blaster Report\",\"Call Blaster Summary Report\",\"Report\",\"Manual Outbound Performance Report\",\"Call Distribution Detail Report New\",\"Administrator\",\"Download Bulk Recording\",\"Setting\",\"Campaign Data Migration\",\"System Statstics\",\"Apps\",\"Users\",\"Campaign\",\"Queues\",\"Add Agent Queues\",\"Call List\",\"Abandoned Call Management\",\"Queue Mapping\",\"Disposition List\",\"Scripts\",\"Breaks\",\"DNC List\",\"Recordings\",\"MissedCall Service\",\"Pre Define Recordings\",\"Email Configuration\",\"Email Template\",\"Msg Configuration\",\"Msg Template\",\"Report Scheduler\",\"VIP Caller\",\"IVR\",\"Call Block List\",\"Crm Design\",\"Other\",\"Recording\",\"Call Rating\",\"Change Password\",\"Profile\",\"Export\",\"Report Column Selection\",\"Notification\",\"Date Filter Check\",\"Bulk List\",\"Call-Dialpad\",\"Calling\",\"Redial\",\"Hold\",\"DTMF\",\"Play File\",\"Mute\",\"Blind Transfer\",\"Attended Transfer\",\"Consultation Hold\",\"Call Conference\",\"Recording Stop\",\"Hang-up\",\"Disposition\",\"Call-Info\"]' 
FROM v_groups
WHERE group_type = 'supervisor' and domain_uuid is NULL );"

#default permissions for operators
mysql -u $DB_USER -p$DB_PWD $DB_DB -e "INSERT INTO v_permission (permission_uuid, group_uuid,permission_values)
(SELECT UUID(), group_uuid, '[\"Live Dashboard\",\"Live Data\",\"Team status\",\"Call in queue\",\"Logout User\",\"Switch Queue\",\"Call-Hang-up\",\"Transfer Call\",\"Eavesdrop\",\"Conference\",\"whisper\",\"List Statistics\",\"Queue Detail\",\"Supervisor Users Status\",\"Supervisor Users Logout\",\"Campaign Detail\",\"Analytics\",\"Analytics Data\",\"Inbound Dashboard\",\"Outbound Dashboard\",\"Manual Dashboard\",\"Disposition summary\",\"CallBack List\",\"System Disposition Summary Report\",\"Leads\",\"Voice Calls Trend\",\"Average Call Duration Trend\",\"Total Calls\",\"Average Call Duration\",\"Non Connected Calls\",\"Agent Happiness\",\"Call Counts\",\"Call Graph Date wise\",\"Call Graph Status wise\",\"Call-History-Supervisor\",\"cdr-call-detailed-report\",\"Manual Outbound Call Detail Report\",\"Auto Call Distribution Detail Report\",\"Campaign Call Distribution Summary Report\",\"Agent Call Distribution Summary Report\",\"Agent Productivity Report\",\"Abandoned Calls Report\",\"Inbound Performance Report\",\"CallBack Report\",\"Login History Report\",\"Customer Feedback Summary Report\",\"Calls On IVR Report\",\"Calls On IVR Summary Report\",\"Auto Call Distribution Report\",\"Call-List Summary Report\",\"MissedCall Service Summary Report\",\"Call Blaster Report\",\"Call Blaster Summary Report\",\"Report\",\"Manual Outbound Performance Report\",\"Call Distribution Detail Report New\",\"Other\",\"Recording\",\"Call Rating\",\"Change Password\",\"Profile\",\"Export\",\"Report Column Selection\",\"Notification\",\"Date Filter Check\",\"Bulk List\",\"Call-Dialpad\",\"Calling\",\"Redial\",\"Hold\",\"DTMF\",\"Play File\",\"Mute\",\"Blind Transfer\",\"Attended Transfer\",\"Consultation Hold\",\"Call Conference\",\"Recording Stop\",\"Hang-up\",\"Disposition\",\"Call-Info\",\"Apps\",\"Users\",\"Campaign\",\"Queues\",\"Add Agent Queues\",\"Call List\"]' 
FROM v_groups
WHERE group_type = 'operator' and domain_uuid is NULL );"

#default permissions for agent
mysql -u $DB_USER -p$DB_PWD $DB_DB -e "INSERT INTO v_permission (permission_uuid, group_uuid,permission_values)
(SELECT UUID(), group_uuid, '[\"Dashboard\",\"Campaign-Detail\",\"Login-History\",\"Call-History-Agent\",\"Switch-Queue\",\"List\",\"Disposition Summary\",\"Agent Status Summary\",\"Avg Inbound Talk Time\",\"Today Call Counts\",\"Callback history\",\"Avg Outbound Talk Time\",\"Latest 10 Call History Details\",\"Other\",\"Break\",\"Recording\",\"Set Auto Call\",\"Break Aftre This Call\",\"Logout After This Call\",\"Auto Call Off After This Call\",\"Change Password\",\"Show Masking Number\",\"Call-Dialpad\",\"Today-call-history\",\"Calling\",\"Redial\",\"Hold\",\"DTMF\",\"Play File\",\"Mute\",\"Blind Transfer\",\"Attended Transfer\",\"Consultation Hold\",\"Call Conference\",\"Recording Stop\",\"Hang-up\",\"Disposition\",\"Call-Info\"]' 
FROM v_groups
WHERE group_type = 'agent' and domain_uuid is NULL );"

#update domain_uuid for v_groups table
mysql -u $DB_USER -p$DB_PWD $DB_DB -e "update v_groups set domain_uuid = (select domain_uuid from v_domains where domain_parent_uuid is not null and domain_enabled='true') where domain_uuid is null"

#update config.ini
CONFIG_FILE=$OPENCC_FOLDER/config.ini
sed -i.bak '/API_URL_ROUTE=/cAPI_URL_ROUTE=https://'$domain_name'' $CONFIG_FILE
sed -i '/HANGUP_URL_ROUTE=/cHANGUP_URL_ROUTE=https://'$domain_name'' $CONFIG_FILE

#.env updation for redis IP
ENV_FILE=$OPENCC_FOLDER/cc/.env
sed -i.bak "/APP_PATH=/c APP_PATH=\'\'" $ENV_FILE

#copy script files to freeswitch direcory
###cp $OPENCC_FOLDER/serv/*.lua /usr/local/freeswitch/scripts/
###chown freeswitch:daemon /usr/local/freeswitch/scripts/*.lua

if [ -d $OPENCC_FOLDER/scripts ]; then
  if [ -L /usr/local/freeswitch/scripts ]; then
    rm -f /usr/local/freeswitch/scripts
  elif [ -d /usr/local/freeswitch/scripts ]; then
    mv /usr/local/freeswitch/scripts /usr/local/freeswitch/scripts_X
  fi
  ln -s $OPENCC_FOLDER/scripts /usr/local/freeswitch/scripts
else
  cp $OPENCC_FOLDER/serv/*.lua /usr/local/freeswitch/scripts/
  chown freeswitch:daemon /usr/local/freeswitch/scripts/*.lua
fi

#update library files rquired by LUA to connect to redis or anyother web API
if [ -d $OPENCC_FOLDER/scripts/usr ]; then
  scp -r $OPENCC_FOLDER/scripts/usr/* /usr/
fi

#copy recording/voice files to freeswitch directory
if ! [ -d "/usr/local/freeswitch/recordings/$domain_name" ]; then
  mkdir /usr/local/freeswitch/recordings/$domain_name
fi
cp -rf $OPENCC_FOLDER/IP-BASED /usr/local/freeswitch/recordings/$domain_name/
cp -rf $OPENCC_FOLDER/*.wav /usr/local/freeswitch/recordings/$domain_name/
chown freeswitch:daemon /usr/local/freeswitch/recordings/$domain_name* -R

if [ ! -d $OPENCC_FOLDER/cc/public/upload/pdf ]; then
  mkdir $OPENCC_FOLDER/cc/public/upload/pdf
  chown freeswitch.daemon $OPENCC_FOLDER/cc/public/upload/pdf
fi

if [ -f $OPENCC_FOLDER/format_cdr.conf.xml ]; then
  cp -f $OPENCC_FOLDER/format_cdr.conf.xml /usr/local/freeswitch/conf/autoload_configs/
  chown freeswitch:daemon /usr/local/freeswitch/conf/autoload_configs/format_cdr.conf.xml
fi

if [ -f $OPENCC_FOLDER/change_recording_permission.bin ]; then
  rm -f /usr/local/freeswitch/change_recording_permission.bin
  cp -f $OPENCC_FOLDER/change_recording_permission.bin /usr/local/freeswitch/change_recording_permission.bin
  chmod +s /usr/local/freeswitch/change_recording_permission.bin
fi

sofia_at=$(grep "mod_sofia" /usr/local/freeswitch/conf/autoload_configs/modules.conf.xml -n | cut -d':' -f 1)
#esl not required
#esl_at=`grep "mod_esl" /usr/local/freeswitch/conf/autoload_configs/modules.conf.xml -n | cut -d':' -f 1`
fcdr_at=$(grep "mod_format_cdr" /usr/local/freeswitch/conf/autoload_configs/modules.conf.xml -n | cut -d':' -f 1)
distributor_at=$(grep "mod_distributor" /usr/local/freeswitch/conf/autoload_configs/modules.conf.xml -n | cut -d':' -f 1)

if [ "$sofia_at" == "" ]; then
  # as no sofia module - add it at randomly say at line 5
  sed -i '5 a <load module="mod_sofia"/>' /usr/local/freeswitch/conf/autoload_configs/modules.conf.xml
  $sofia_at = 5
fi
if [ "$fcdr_at" == "" ]; then
  sed -i ''$sofia_at' a <load module="mod_format_cdr"/>' /usr/local/freeswitch/conf/autoload_configs/modules.conf.xml
fi
if [ "$distributor_at" == "" ]; then
  sed -i ''$sofia_at' a <load module="mod_distributor"/>' /usr/local/freeswitch/conf/autoload_configs/modules.conf.xml
fi

if [ -f lualib64_5.3.tgz ]; then
  cp lualib64_5.3.tgz /
  cd /
  tar -xzf lualib64_5.3.tgz
  cd -
fi

if [ -f lualib_5.3.tgz ]; then
  cp lualib_5.3.tgz /
  cd /
  tar -xzf lualib_5.3.tgz
  cd -
fi

#update configuration for perl scripts
cd $OPENCC_FOLDER/serv
dos2unix *.pl
dos2unix *.sh
##sed -i.bak "/\$database = '/c \$database = '"$DB_DB"';" *.pl
##sed -i "/\$username = '/c \$username = '"$DB_USER"';" *.pl
##sed -i "/\$password = '/c \$password = '"$DB_PWD"';" *.pl
cd -

if [ ! -h $OPENCC_FOLDER/recordings ]; then
  ln -s /usr/local/freeswitch/recordings $OPENCC_FOLDER/recordings
fi

# #add crontab entry for running CallCenter script
# log_message "* * * * * /usr/bin/sh "$OPENCC_FOLDER"/serv/redis-campaign-blast.sh" >.temp.cron
# log_message "* * * * * /usr/bin/sh "$OPENCC_FOLDER"/serv/redis-campaign-autoblast.sh" >>.temp.cron
# log_message "#* * * * * sleep 30 && /usr/bin/sh "$OPENCC_FOLDER"/serv/redis-campaign-blast.sh" >>.temp.cron
# log_message "#* * * * * sleep 30 && /usr/bin/sh "$OPENCC_FOLDER"/serv/redis-campaign-autoblast.sh" >>.temp.cron
# log_message "1 0 * * * /usr/bin/sh "$OPENCC_FOLDER"/Archive_LogFiles.sh" >>.temp.cron
# #log_message "* * * * * chmod 775 /usr/local/freeswitch/recordings -R" >> .temp.cron
# #log_message "* * * * * chown freeswitch.daemon /usr/local/freeswitch/recordings -R" >> .temp.cron
# log_message "0 0 28 * * /usr/bin/sh /var/www/html/openpbx/recording_folder_permission.sh" >>.temp.cron
# log_message "* * * * * /usr/bin/wget -O - http://127.0.0.1/cc/gettenmails >/dev/null 2>&1" >>.temp.cron
# log_message "*/10 * * * * /usr/bin/sh /var/www/html/openpbx/collect_sysstat.sh" >>.temp.cron
# crontab -u freeswitch -l | cat - .temp.cron >.temp2.cron
# crontab -u freeswitch .temp2.cron
# crontab -u freeswitch -l

# #keep ntp time update under root permission
# log_message "0 */3 * * * ntpdate pool.ntp.org" >.temp.cron
# log_message "* * * * * /usr/bin/sh /var/www/html/openpbx/tools/service_status.sh" >>.temp.cron
# log_message "*/5 * * * * /usr/bin/sh /var/www/html/openpbx/tools/insert_service_status.sh" >>.temp.cron

if systemctl is-active --quiet nginx; then
  # Append cron entries to FreeSWITCH user's crontab
  {
    crontab -l -u freeswitch 2>/dev/null
    echo "#* * * * * /usr/bin/php /var/www/html/openpbx/cc/artisan redis_campaign_blast"
    echo "#* * * * * /usr/bin/php /var/www/html/openpbx/cc/artisan redis_campaign_autoblast"
    echo "1 0 * * * /usr/bin/sh /var/www/html/openpbx/Archive_LogFiles.sh"
    echo "#Create hourly archive of lg files"
    echo "0 * * * * /usr/bin/sh /var/www/html/openpbx/Archive_lg_files.sh"
    echo "#0 0 28 * * /usr/bin/sh /var/www/html/openpbx/recording_folder_permission.sh"
    echo "#* * * * * /usr/bin/wget -O - http://127.0.0.1/cc/gettenmails >/dev/null 2>&1"
    echo "*/10 * * * * /usr/bin/sh /var/www/html/openpbx/collect_sysstat.sh"
    echo "* * * * * /usr/bin/sh /var/www/html/openpbx/service_connect/service_status.sh"
    echo "*/5 * * * * /usr/bin/sh /var/www/html/openpbx/service_connect/insert_service_status.sh"
    echo "1 0 * * * /usr/bin/wget --no-proxy http://127.0.0.1/cc/api/v1/clean-today-attempts-data"
    echo "#To rename laravel logfile every hour"
    echo "0 * * * * mv -f /var/www/html/openpbx/cc/storage/logs/laravel-\$(date -d '1 hour ago' '+%Y-%m-%d').log /var/www/html/openpbx/cc/storage/logs/laravel_\$(date -d '1 hour ago' '+%Y-%m-%d_%H').log"
  } | crontab -u freeswitch - >> cron.logs
else
  echo "nginx is not running." >> cron.logs
fi

if systemctl is-active --quiet freeswitch; then
  {
    crontab -l -u freeswitch 2>/dev/null
    echo "* * * * * /usr/bin/php /var/www/html/openpbx/cc/artisan redis_campaign_blast"
    echo "* * * * * /usr/bin/php /var/www/html/openpbx/cc/artisan redis_campaign_autoblast"
    echo "1 0 * * * /usr/bin/sh /var/www/html/openpbx/Archive_LogFiles.sh"
    echo "0 * * * * /usr/bin/sh /var/www/html/openpbx/Archive_lg_files.sh" # Corrected the time format
    echo "#0 0 28 * * /usr/bin/sh /var/www/html/openpbx/recording_folder_permission.sh"
    echo "#* * * * * /usr/bin/wget -O - http://127.0.0.1/cc/gettenmails >/dev/null 2>&1"
    echo "*/10 * * * * /usr/bin/sh /var/www/html/openpbx/collect_sysstat.sh"
    echo "* * * * * /usr/bin/sh /var/www/html/openpbx/service_connect/service_status.sh"
    echo "*/5 * * * * /usr/bin/sh /var/www/html/openpbx/service_connect/insert_service_status.sh"
    echo "1 0 * * * /usr/bin/wget --no-proxy http://127.0.0.1/cc/api/v1/clean-today-attempts-data"
    echo "#To rename laravel logfile every hour"
    echo "0 * * * * mv -f /var/www/html/openpbx/cc/storage/logs/laravel-\$(date -d '1 hour ago' '+%Y-%m-%d').log /var/www/html/openpbx/cc/storage/logs/laravel_\$(date -d '1 hour ago' '+%Y-%m-%d_%H').log"
  } | crontab -u freeswitch - >> cron.logs
else
  echo "FreeSWITCH is not running." >> cron.logs
fi

# crontab -l | cat - .temp.cron >.temp2.cron
# crontab .temp2.cron
# crontab -l

# crontab -l | cat - .tempf.cron >.temp2f.cron
# crontab .temp2f.cron
# crontab -l

# rm -f .temp.cron .temp2.cron

mkdir /usr/local/freeswitch/recordings
chown freeswitch:daemon -R /usr/local/freeswitch/recordings
chmod 777 /usr/local/freeswitch/recordings

#version
cp version.csv /var/lib/mysql/opencc/
chown mysql:mysql /var/lib/mysql/opencc/version.csv
chmod 666 /var/lib/mysql/opencc/version.csv
#mysql -u $DB_USER -p$DB_PWD $DB_DB  << EOF
#LOAD DATA INFILE 'version.csv'
#    INTO TABLE version
#FIELDS TERMINATED BY ','
#ENCLOSED BY '"'
#LINES TERMINATED BY '\n'
#IGNORE 1 ROWS;
#EOF
croncmd="/usr/bin/sh /var/www/html/openpbx/tools/service_status.sh > /var/log/service_status.log 2>&1"
cronjob="* * * * * $croncmd"
#( crontab -l | grep -v -F "$croncmd" ; log_message "$cronjob" ) | crontab -

#change ownership of php session folder
chown freeswitch:daemon /var/lib/php/session /var/lib/php/wsdlcache -R

mkdir -p /var/www/html/openpbx/recordings/temp
chmod 777 /var/www/html/openpbx/recordings/temp
chown freeswitch:daemon -R /var/www/html/openpbx/recordings

#2904 - voice prompt "You are the only person in this conference" gets played while doing conference
mv $SOUND_FOLDER/en/us/callie/conference/8000/conf-alone.wav $SOUND_FOLDER/en/us/callie/conference/8000/conf-alone.wavX 2>>/dev/null
mv $SOUND_FOLDER/en/us/callie/conference/16000/conf-alone.wav $SOUND_FOLDER/en/us/callie/conference/16000/conf-alone.wavX 2>>/dev/null
mv $SOUND_FOLDER/en/us/callie/conference/32000/conf-alone.wav $SOUND_FOLDER/en/us/callie/conference/32000/conf-alone.wavX 2>>/dev/null
mv $SOUND_FOLDER/en/us/callie/conference/48000/conf-alone.wav $SOUND_FOLDER/en/us/callie/conference/48000/conf-alone.wavX 2>>/dev/null

cat >/usr/local/freeswitch/conf/autoload_configs/hiredis.conf.xml <<-EOM
<configuration name="hiredis.conf" description="mod_hiredis">
  <profiles>
    <profile name="default">
      <connections>
        <connection name="primary">
          <param name="hostname" value="127.0.0.1"/>
          <param name="password" value="opencc"/>
          <param name="port" value="7379"/>
          <param name="timeout_ms" value="500"/>
        </connection>
        <connection name="secondary">
          <param name="hostname" value="localhost"/>
          <param name="password" value=""/>
          <param name="port" value="6379"/>
          <param name="timeout_ms" value="500"/>
        </connection>
      </connections>
      <params>
        <param name="ignore-connect-fail" value="true"/>
      </params>
    </profile>
 <profile name="limitredis">
      <connections>
        <connection name="primary">
          <param name="hostname" value="127.0.0.1"/>
          <param name="password" value="opencc"/>
          <param name="port" value="7379"/>
          <param name="timeout_ms" value="500"/>
        </connection>
        <connection name="secondary">
          <param name="hostname" value="localhost"/>
          <param name="password" value=""/>
          <param name="port" value="6379"/>
          <param name="timeout_ms" value="500"/>
        </connection>
      </connections>
      <params>
        <param name="ignore-connect-fail" value="true"/>
      </params>
    </profile>
  </profiles>
</configuration>
EOM

sed -i 's/http:\/\/127.0.0.1\/hangup_data.php/http:\/\/127.0.0.1\/openpbx\/hangup_data.php/g' /usr/local/freeswitch/conf/autoload_configs/*
sed -i 's/http:\/\/127.0.0.1\/app/http:\/\/127.0.0.1\/openpbx\/app/g' /usr/local/freeswitch/conf/autoload_configs/*

fs_cli -x 'reloadxml'
fs_cli -x 'reload mod_hiredis'
fs_cli -x "reload mod_format_cdr"
fs_cli -x "reload mod_xml_cdr"
fs_cli -x "reload mod_sofia"
fs_cli -x "reload mod_callcenter"
mysql -p$DB_PWD -u $DB_USER $DB_DB -Be 'INSERT INTO `v_dialplans` (`domain_uuid`, `dialplan_uuid`, `app_uuid`, `hostname`, `dialplan_context`, `dialplan_name`, `dialplan_number`, `dialplan_continue`, `dialplan_xml`, `dialplan_order`, `dialplan_enabled`, `dialplan_description`, `dialplans_lang_code`, `caller_id`, `deleted_at`) VALUES ("'$domain_uuid'",  "72d65b02-368b-4724-9d74-fd3c7a6f04a8", "742714e5-8cdf-32fd-462c-cbe7e3d655db", NULL, "${domain_name}", "wait", "wait", "true", "<extension name=\"wait\" continue=\"true\" uuid=\"72d65b02-368b-4724-9d74-fd3c7a6f04a8\">\\n <condition field=\"destination_number\" expression=\"^wait(\\d+)$\">\\n   <action application=\"sleep\" data=\"$1\"/>\\n    <action application=\"hangup\" data=\"NO_ANSWER\"/>\\n  </condition>\\n</extension>\\n",  25, "true", NULL, NULL, NULL, NULL);'

cd $SCRIPTPATH

php phpinfo.php $domain_uuid

#start all services
systemctl restart opencc_nodejs
systemctl restart apache2
log_message "Done ........."
log_message "init" >/usr/local/post.txt
