#!/bin/bash

set -euxo pipefail

echo "STARTUP VERSION: 2026-05-15-01"
date

####################################################################################
#
# Ensure that the currently available mysqli extension is configured for PHP
#
####################################################################################

# Find the latest mysqli.so file in the extensions directory and add it to the redcap.ini file
MYSQLI_SO_PATH=$(find /usr/local/lib/php/extensions/ -name "mysqli.so" -print 2>/dev/null | sort -V | tail -n 1)
echo "extension=${MYSQLI_SO_PATH}" > /home/site/ini/extensions.ini

####################################################################################
#
# Install required packages in container
#
####################################################################################

apt-get update -qq

apt-get install -y \
  cron \
  unzip \
  msmtp \
  msmtp-mta \
  ca-certificates \
  ghostscript \
  2>&1 | tee /tmp/apt-install.log

echo "Install exit code: ${PIPESTATUS[0]}"

echo "Checking installed binaries:"
command -v cron || echo "cron missing"
command -v crontab || echo "crontab missing"
command -v msmtp || echo "msmtp missing"
command -v sendmail || echo "sendmail missing"

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
auth           on
tls            on
tls_starttls   on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /tmp/msmtp.log

account default
host ${smtpFQDN}
port ${smtpPort}
from ${fromEmailAddress}
user ${smtpUsername}
password ${smtpPassword}
EOF

chown www-data:www-data /etc/msmtprc
chmod 600 /etc/msmtprc

MSMTP_PATH=$(command -v msmtp)

cat > /home/site/ini/99-msmtp.ini <<EOF
sendmail_path = "$MSMTP_PATH -C /etc/msmtprc -t -i"
EOF

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
# sed -i 's~<policy domain="coder" rights="none" pattern="PDF" />~<policy domain="coder" rights="read | write" pattern="PDF" />~' /etc/ImageMagick-6/policy.xml

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

# Start cron directly; service cron may not exist in this container
if command -v cron >/dev/null 2>&1; then
    cron
else
    echo "ERROR: cron binary not found"
    command -v crontab || true
fi

# Remove existing REDCap cron entry to avoid duplicates
crontab -l 2>/dev/null | grep -v "/home/site/wwwroot/cron.php" | crontab - || true

# Add REDCap cronjob every minute with logging
(crontab -l 2>/dev/null; echo "* * * * * . /etc/environment; /usr/local/bin/php /home/site/wwwroot/cron.php >> /tmp/redcap-cron.log 2>&1") | crontab -

echo "Current crontab:"
crontab -l
