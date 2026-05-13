#!/bin/bash

echo "Custom container startup"

####################################################################################
#
# Ensure that the currently available mysqli extension is configured for PHP
#
####################################################################################

# Find the latest mysqli.so file in the extensions directory and add it to the redcap.ini file
# MYSQLI_SO_PATH=$(find /usr/local/lib/php/extensions/ -name "mysqli.so" -print 2>/dev/null | sort -V | tail -n 1)
# echo "extension=${MYSQLI_SO_PATH}" > /home/site/ini/extensions.ini

####################################################################################
#
# Install required packages in container
#
####################################################################################

apt-get update -qq && apt-get install cron msmtp msmtp-mta ca-certificates ghostscript imagemagick libmagickwand-dev pkg-config gcc make autoconf php-pear -yqq


####################################################################################
# Install and enable PHP Imagick extension
####################################################################################

apt-get update -qq && apt-get install -yqq \
  imagemagick \
  libmagickwand-dev \
  ghostscript \
  pkg-config \
  gcc \
  make \
  autoconf \
  php-pear

if ! php -m | grep -qi '^imagick$'; then
  printf "\n" | pecl install imagick
  echo "extension=imagick.so" > /home/site/ini/imagick.ini
fi

# Allow ImageMagick PDF read/write
if [ -f /etc/ImageMagick-6/policy.xml ]; then
  sed -i 's~<policy domain="coder" rights="none" pattern="PDF" />~<policy domain="coder" rights="read|write" pattern="PDF" />~' /etc/ImageMagick-6/policy.xml
fi

####################################################################################
#
# SMTP Relay Setup
#
####################################################################################

cat > /etc/msmtprc <<EOF
defaults
auth           off
tls            on
tls_starttls   on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /tmp/msmtp.log

account default
host ${smtpFQDN}
port ${smtpPort}
from ${fromEmailAddress}
EOF

chmod 600 /etc/msmtprc

echo 'sendmail_path = "/usr/sbin/sendmail -t -i"' > /home/site/ini/mail.ini

echo "Sendmail target:"
ls -l /usr/sbin/sendmail
ls -l /etc/alternatives/sendmail || true

####################################################################################
#
# Configure REDCap cronjob to run every minute
#
####################################################################################

# Export the database connection environment variables to /etc/environment so cron can use them
# We do this in startup.sh so that each container instance will get this file (it's outside of /home so not persisted)
# and also because then updates to the environment variables (app settings) will be picked up by cron
echo "DBHostName=$DBHostName" > /etc/environment # Overwrite the file with the first statement
echo "DBName=$DBName" >> /etc/environment # Append all the other lines
echo "DBUserName=$DBUserName" >> /etc/environment
echo "DBPassword=$DBPassword" >> /etc/environment
echo "DBSslCa=$DBSslCa" >> /etc/environment

# Configure PHP timezone setting
# TODO: Can this be done in redcap.ini?
sed -i "s|date.timezone=UTC|date.timezone=$WEBSITE_TIME_ZONE|" /usr/local/etc/php/conf.d/php.ini

# Configure the ImageMagick policy to allow PDF read/write
sed -i 's~<policy domain="coder" rights="none" pattern="PDF" />~<policy domain="coder" rights="read | write" pattern="PDF" />~' /etc/ImageMagick-6/policy.xml

# Disallow reading from the temp directory by adding a location block to nginx config
# But only do this once
NGINX_CONF_FILE="/etc/nginx/sites-enabled/default"
BLOCK_MARKER="REDCap_recommended_block_temp"

if ! grep -q "$BLOCK_MARKER" "$NGINX_CONF_FILE"; then
    sed -i '/server\s*{/a \
    # BEGIN REDCap_recommended_block_temp\
    location ^~ /temp/ {\
        deny all;\
    }\
    # END REDCap_recommended_block_temp\
    ' "$NGINX_CONF_FILE"

    # Validate nginx config and restart if valid
    nginx -t && service nginx restart
fi

# Start the cron service and add the REDCap cronjob
service cron start
(crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/php /home/site/wwwroot/cron.php > /dev/null")|crontab
