#!/bin/bash
# Build an iocage jail under FreeNAS 11.3-12.0 using the latest release of WordPress
# git clone https://github.com/basilhendroff/freenas-iocage-wordpress

print_msg () {
  echo
  echo -e "\e[1;32m"$1"\e[0m"
  echo
}

print_err () {
  echo -e "\e[1;31m"$1"\e[0m"
  echo
}

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   print_err "This script must be run with root privileges" 
   exit 1
fi

#####################################################################
print_msg "General configuration..."

# Initialize defaults
JAIL_IP=""
JAIL_INTERFACES=""
DEFAULT_GW_IP=""
INTERFACE="vnet0"
VNET="on"
POOL_PATH=""
JAIL_NAME="wordpress"
TIME_ZONE=""
HOST_NAME=""
DB_PATH=""
FILES_PATH=""
CONFIG_NAME="wordpress-config"

# Exposed configuration parameters
# php.ini
UPLOAD_MAX_FILESIZE="32M"	# default=2M
POST_MAX_SIZE="48M"		# default=8M
MEMORY_LIMIT="256M"		# default=128M
MAX_EXECUTION_TIME=600		# default=30 seconds
MAX_INPUT_VARS=3000		# default=1000
MAX_INPUT_TIME=1000		# default=60 seconds

# Check for wordpress-config and set configuration
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")
if ! [ -e "${SCRIPTPATH}"/"${CONFIG_NAME}" ]; then
  print_err "${SCRIPTPATH}/${CONFIG_NAME} must exist."
  exit 1
fi
. "${SCRIPTPATH}"/"${CONFIG_NAME}"
INCLUDES_PATH="${SCRIPTPATH}"/includes

RELEASE=$(freebsd-version | sed "s/STABLE/RELEASE/g" | sed "s/-p[0-9]*//")
#RELEASE="12.1-RELEASE"
JAILS_MOUNT=$(zfs get -H -o value mountpoint $(iocage get -p)/iocage)

#####################################################################
print_msg "Input/Config Sanity checks..."

# Check that necessary variables were set by nextcloud-config
if [ -z "${JAIL_IP}" ]; then
  print_err 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z "${JAIL_INTERFACES}" ]; then
  print_msg 'JAIL_INTERFACES defaulting to: vnet0:bridge0'
  JAIL_INTERFACES="vnet0:bridge0"
fi
if [ -z "${DEFAULT_GW_IP}" ]; then
  print_err 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi
if [ -z "${POOL_PATH}" ]; then
  POOL_PATH="/mnt/$(iocage get -p)"
  print_msg 'POOL_PATH defaulting to '$POOL_PATH
fi
if [ -z "${TIME_ZONE}" ]; then
  print_err 'Configuration error: TIME_ZONE must be set'
  exit 1
fi

# If DB_PATH and FILES_PATH weren't set in wordpress-config, set them
if [ -z "${DB_PATH}" ]; then
  DB_PATH="${POOL_PATH}"/apps/wordpress/db
fi
if [ -z "${FILES_PATH}" ]; then
  FILES_PATH="${POOL_PATH}"/apps/wordpress/files
fi

# Sanity check DB_PATH and FILES_PATH -- they have to be different and can't be the same as POOL_PATH
if [ "${FILES_PATH}" = "${DB_PATH}" ]
then
  print_err "FILES_PATH and DB_PATH must be different!"
  exit 1
fi
if [ "${DB_PATH}" = "${POOL_PATH}" ] || [ "${FILES_PATH}" = "${POOL_PATH}" ]
then
  print_err "DB_PATH and FILES_PATH must all be different from POOL_PATH!"
  exit 1
fi

# Extract IP and netmask, sanity check netmask
IP=$(echo ${JAIL_IP} | cut -f1 -d/)
NETMASK=$(echo ${JAIL_IP} | cut -f2 -d/)
if [ "${NETMASK}" = "${IP}" ]
then
  NETMASK="24"
fi
if [ "${NETMASK}" -lt 8 ] || [ "${NETMASK}" -gt 30 ]
then
  NETMASK="24"
fi

# Check that this is a new installation 
FILE=${FILES_PATH}/wp-config.php
#if [ "$(ls -A "${FILES_PATH}")" ] || [ "$(ls -A "${DB_PATH}")" ]
#then
   if [ -f "${FILE}" ]; then
     print_msg "Old install found"
     REINSTALL="true"
   fi
#fi

#####################################################################
print_msg "Jail Creation. Time for a cuppa. Installing packages will take a while..."

# List packages to be auto-installed after jail creation

cat <<__EOF__ >/tmp/pkg.json
	{
  "pkgs":[
  "php74","php74-curl","php74-dom","php74-exif","php74-fileinfo","php74-json","php74-mbstring",
  "php74-mysqli","php74-pecl-libsodium","php74-openssl","php74-pecl-imagick","php74-xml","php74-zip",
  "php74-filter","php74-gd","php74-iconv","php74-pecl-mcrypt","php74-simplexml","php74-xmlreader","php74-zlib",
  "php74-ftp","php74-pecl-ssh2","php74-sockets",
  "mariadb103-server","unix2dos","ssmtp","php74-xmlrpc","php74-ctype","php74-session"
  ]
}
__EOF__

# Create the jail and install previously listed packages
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" interfaces="${JAIL_INTERFACES}" ip4_addr="${INTERFACE}|${IP}/${NETMASK}" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}"
then
	print_err "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

#####################################################################
print_msg "Directory Creation and Mounting..."

mkdir -p "${DB_PATH}"
chown -R 88:88 "${DB_PATH}"
iocage fstab -a "${JAIL_NAME}" "${DB_PATH}"  /var/db/mysql  nullfs  rw  0  0

mkdir -p "${FILES_PATH}"
chown -R 80:80 "${FILES_PATH}"
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www/wordpress
iocage fstab -a "${JAIL_NAME}" "${FILES_PATH}"  /usr/local/www/wordpress  nullfs  rw  0  0

iocage exec "${JAIL_NAME}" mkdir -p /mnt/includes
iocage fstab -a "${JAIL_NAME}" "${INCLUDES_PATH}" /mnt/includes nullfs rw 0 0

#####################################################################
print_msg "Caddy download..."

FILE="caddy_2.2.0_freebsd_amd64.tar.gz"
if ! iocage exec "${JAIL_NAME}" fetch -o /tmp https://github.com/caddyserver/caddy/releases/latest/download/"${FILE}"
#if ! iocage exec "${JAIL_NAME}" fetch -o /tmp https://github.com/caddyserver/caddy/releases/tag/v2.2.0-rc.3"
then
	print_err "Failed to download Caddy"
	exit 1
fi
if ! iocage exec "${JAIL_NAME}" tar xzf /tmp/"${FILE}" -C /usr/local/bin/
then
	print_err "Failed to extract Caddy"
	exit 1
fi
iocage exec "${JAIL_NAME}" rm /tmp/"${FILE}"

#####################################################################
if [ "${REINSTALL}" == "true" ]; then
print_msg "Found previous install"

else
print_msg "Wordpress download..."  

FILE="latest.tar.gz"
if ! iocage exec "${JAIL_NAME}" fetch -o /tmp https://wordpress.org/"${FILE}"
then
	print_err "Failed to download WordPress"
	exit 1
fi
if ! iocage exec "${JAIL_NAME}" tar xzf /tmp/"${FILE}" -C /usr/local/www/
then
	print_err "Failed to extract WordPress"
	exit 1
fi
iocage exec "${JAIL_NAME}" rm /tmp/"${FILE}"
iocage exec "${JAIL_NAME}" chown -R www:www /usr/local/www/wordpress
fi
#####################################################################
print_msg "Configure and start Caddy..."

# Copy and edit pre-written config files
iocage exec "${JAIL_NAME}" cp -f /mnt/includes/Caddyfile /usr/local/www
iocage exec "${JAIL_NAME}" cp -f /mnt/includes/caddy /usr/local/etc/rc.d/

iocage exec "${JAIL_NAME}" sysrc caddy_enable="YES"
iocage exec "${JAIL_NAME}" sysrc caddy_config="/usr/local/www/Caddyfile"

iocage exec "${JAIL_NAME}" service caddy start

#####################################################################
print_msg "Configure and start PHP-FPM..."

# Copy and edit pre-written config files
iocage exec "${JAIL_NAME}" cp -f /usr/local/etc/php.ini-production /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" sed -i '' "s|upload_max_filesize = 2M|upload_max_filesize = ${UPLOAD_MAX_FILESIZE}|" /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" sed -i '' "s|post_max_size = 8M|post_max_size = ${POST_MAX_SIZE}|" /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" sed -i '' "s|memory_limit = 128M|memory_limit = ${MEMORY_LIMIT}|" /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" sed -i '' "s|max_execution_time = 30|max_execution_time = ${MAX_EXECUTION_TIME}|" /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" sed -i '' "s|;max_input_vars = 1000|max_input_vars = ${MAX_INPUT_VARS}|" /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" sed -i '' "s|max_input_time = 60|max_input_time = ${MAX_INPUT_TIME}|" /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" sed -i '' "s|;date.timezone =|date.timezone = ${TIME_ZONE}|" /usr/local/etc/php.ini

iocage exec "${JAIL_NAME}" sysrc php_fpm_enable="YES"
iocage exec "${JAIL_NAME}" service php-fpm start

#####################################################################
print_msg "Configure and start MariaDB..."

iocage exec "${JAIL_NAME}" sysrc mysql_enable="YES"
iocage exec "${JAIL_NAME}" service mysql-server start

#####################################################################
if [ "${REINSTALL}" == "true" ]; then
print_msg "Found previous install will skip database creation"
else
print_msg "Create the WordPress database..."

DB_ROOT_PASSWORD=$(openssl rand -base64 16)
#DB_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD="e8284304167cbf99f185"
# Save passwords for later reference
iocage exec "${JAIL_NAME}" echo "MariaDB root password is ${DB_ROOT_PASSWORD}" > /root/${JAIL_NAME}_db_password.txt
iocage exec "${JAIL_NAME}" echo "MariaDB database user wordpress password is ${DB_PASSWORD}" >> /root/${JAIL_NAME}_db_password.txt

iocage exec "${JAIL_NAME}" mysql -u root -e "CREATE DATABASE wordpress;"
iocage exec "${JAIL_NAME}" mysql -u root -e "GRANT ALL PRIVILEGES ON wordpress.* TO wordpress@localhost IDENTIFIED BY '${DB_PASSWORD}';"
iocage exec "${JAIL_NAME}" mysql -u root -e "FLUSH PRIVILEGES;"

iocage exec "${JAIL_NAME}" mysqladmin --user=root password "${DB_ROOT_PASSWORD}" reload

#####################################################################
print_msg "Configure WordPress..."

iocage exec "${JAIL_NAME}" cp -f /usr/local/www/wordpress/wp-config-sample.php /usr/local/www/wordpress/wp-config.php
iocage exec "${JAIL_NAME}" dos2unix /usr/local/www/wordpress/wp-config.php
iocage exec "${JAIL_NAME}" sed -i '' "s|database_name_here|wordpress|" /usr/local/www/wordpress/wp-config.php
iocage exec "${JAIL_NAME}" sed -i '' "s|username_here|wordpress|" /usr/local/www/wordpress/wp-config.php
iocage exec "${JAIL_NAME}" sed -i '' "s|password_here|${DB_PASSWORD}|" /usr/local/www/wordpress/wp-config.php

#####################################################################
print_msg "Configure sSMTP..."

iocage exec "${JAIL_NAME}" pw useradd ssmtp -g nogroup -h - -s /sbin/nologin -d /nonexistent -c "sSMTP pseudo-user"
iocage exec "${JAIL_NAME}" chown ssmtp:wheel /usr/local/etc/ssmtp
iocage exec "${JAIL_NAME}" chmod 4750 /usr/local/etc/ssmtp
iocage exec "${JAIL_NAME}" cp /usr/local/etc/ssmtp/ssmtp.conf.sample /usr/local/etc/ssmtp/ssmtp.conf
iocage exec "${JAIL_NAME}" cp /usr/local/etc/ssmtp/revaliases.sample /usr/local/etc/ssmtp/revaliases
iocage exec "${JAIL_NAME}" chown ssmtp:wheel /usr/local/etc/ssmtp/ssmtp.conf
iocage exec "${JAIL_NAME}" chmod 640 /usr/local/etc/ssmtp/ssmtp.conf
iocage exec "${JAIL_NAME}" chown ssmtp:nogroup /usr/local/sbin/ssmtp
iocage exec "${JAIL_NAME}" chmod 4555 /usr/local/sbin/ssmtp
fi
#####################################################################
print_msg "Installation complete!"

cat /root/${JAIL_NAME}_db_password.txt
print_msg "All passwords are saved in /root/${JAIL_NAME}_db_password.txt"
print_msg "Continue with the post installation steps at https://github.com/basilhendroff/freenas-iocage-wordpress/blob/master/POST-INSTALL.md"
#print_msg "Wordpress should be available at http://${JAIL_IP}/index.php"
