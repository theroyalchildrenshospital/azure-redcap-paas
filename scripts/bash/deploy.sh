#!/bin/bash

# Copyright (c) Microsoft Corporation
# All rights reserved.
#
# MIT License

####################################################################################
#
# Timestamp for log file
#
####################################################################################

stamp=$(date +%Y-%m-%d-%H-%M)

####################################################################################
#
# Configure mysqli extension
#
####################################################################################

echo "Configuring mysqli extension" >> /home/site/log-$stamp.txt
# This path is set in webapp.bicep as an environment variable
mkdir -p /home/site/ini
# Find the latest mysqli.so file in the extensions directory and add it to the redcap.ini file
MYSQLI_SO_PATH=$(find /usr/local/lib/php/extensions/ -name "mysqli.so" -print 2>/dev/null | sort -V | tail -n 1)
echo "extension=${MYSQLI_SO_PATH}" > /home/site/ini/extensions.ini

####################################################################################
#
# Download REDCap zip file and unzip to wwwroot
# If zip file path exists just download it; otherwise 
# make a call to REDCap community site and download it
#
####################################################################################

# redcapZipPath="/tmp/redcap.zip"

# cd /tmp

# # If there is no REDCap zip file path, download from REDCap Community site
# if [ -z "$APPSETTING_redcapAppZip" ]; then
#   echo "Downloading REDCap zip file from REDCap Community site" >> /home/site/log-$stamp.txt

#   if [ -z "$APPSETTING_redcapCommunityUsername" ]; then
#     echo "Missing REDCap Community site username." >> /home/site/log-$stamp.txt
#     exit 1
#   fi

#   if [ -z "$APPSETTING_redcapCommunityPassword" ]; then
#     echo "Missing REDCap Community site password." >> /home/site/log-$stamp.txt
#     exit 1
#   fi

#   if [ -z "$APPSETTING_zipVersion" ]; then
#     echo "zipVersion is null or empty. Setting to latest" >> /home/site/log-$stamp.txt
#     export APPSETTING_zipVersion="latest"
#   fi
  
#   wget --method=post -O $redcapZipPath -q --body-data="username=$APPSETTING_redcapCommunityUsername&password=$APPSETTING_redcapCommunityPassword&version=$APPSETTING_zipVersion&install=1" --header=Content-Type:application/x-www-form-urlencoded https://redcap.vumc.org/plugins/redcap_consortium/versions.php

#   # Check to see if the redcap.zip file contains the word error
#   if [ -z "$(grep -i error redcap.zip)" ]; then
#     echo "Downloaded REDCap zip file" >> /home/site/log-$stamp.txt
#   else
#     echo $(cat redcap.zip) >> /home/site/log-$stamp.txt
#     exit 1
#   fi

# else
#   echo "Downloading REDCap zip file from storage" >> /home/site/log-$stamp.txt
#   wget -q -O $redcapZipPath $APPSETTING_redcapAppZip
# fi

# # Remove any default files from wwwroot
# rm -rf /home/site/wwwroot/*

# # Unzip the REDCap zip file to a temp location
# echo "Unzipping redcap.zip to /tmp/wwwroot" >> /home/site/log-$stamp.txt
# unzip -oq $redcapZipPath -d /tmp/wwwroot

# echo "Copying REDCap files and subdirectories to wwwroot using tar" >> /home/site/log-$stamp.txt
# cd /tmp/wwwroot/redcap && (tar cf - . ) | ( cd /home/site/wwwroot && tar xf - )

# # Cleanup: delete the tmp files and the downloaded zip file
# rm -rf /tmp/wwwroot
# rm -f $redcapZipPath

####################################################################################
#
# Download REDCap zip file and deploy to wwwroot
#
# Supports:
#   redcapPackageType=INSTALL
#   redcapPackageType=UPGRADE
#
# INSTALL:
#   Used for full REDCap installation packages.
#   Replaces /home/site/wwwroot with the contents of the REDCap application root.
#
# UPGRADE:
#   Used for REDCap upgrade packages.
#   Merges the contents inside the zip's "redcap" folder into the existing
#   /home/site/wwwroot directory.
#
####################################################################################

redcapZipPath="/tmp/redcap.zip"
extractPath="/tmp/redcap-extract"
stableRoot="/home/site/wwwroot"
logFile="/home/site/log-$stamp.txt"

cd /tmp

echo "Preparing REDCap deployment" >> "$logFile"

# App Service may expose app settings as APPSETTING_name in this image.
# Prefer APPSETTING_redcapPackageType but fall back to redcapPackageType if present.
redcapPackageType="${APPSETTING_redcapPackageType:-$redcapPackageType}"
redcapPackageType="$(echo "$redcapPackageType" | tr '[:lower:]' '[:upper:]')"

if [ -z "$redcapPackageType" ]; then
  echo "Missing redcapPackageType app setting. Expected INSTALL or UPGRADE." >> "$logFile"
  exit 1
fi

if [ "$redcapPackageType" != "INSTALL" ] && [ "$redcapPackageType" != "UPGRADE" ]; then
  echo "Invalid redcapPackageType: $redcapPackageType. Expected INSTALL or UPGRADE." >> "$logFile"
  exit 1
fi

echo "REDCap package type: $redcapPackageType" >> "$logFile"

# Install required tools if missing
if ! command -v wget >/dev/null 2>&1; then
  echo "wget not found. Installing wget..." >> "$logFile"
  apt-get update >> "$logFile" 2>&1
  apt-get install -y wget >> "$logFile" 2>&1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "unzip not found. Installing unzip..." >> "$logFile"
  apt-get update >> "$logFile" 2>&1
  apt-get install -y unzip >> "$logFile" 2>&1
fi

mkdir -p "$stableRoot"

####################################################################################
# Download REDCap package
####################################################################################

# If there is no REDCap zip file path, download from REDCap Community site
if [ -z "$APPSETTING_redcapAppZip" ]; then
  echo "Downloading REDCap zip file from REDCap Community site" >> "$logFile"

  if [ -z "$APPSETTING_redcapCommunityUsername" ]; then
    echo "Missing REDCap Community site username." >> "$logFile"
    exit 1
  fi

  if [ -z "$APPSETTING_redcapCommunityPassword" ]; then
    echo "Missing REDCap Community site password." >> "$logFile"
    exit 1
  fi

  if [ -z "$APPSETTING_zipVersion" ]; then
    echo "zipVersion is null or empty. Setting to latest" >> "$logFile"
    export APPSETTING_zipVersion="latest"
  fi

  # This endpoint call uses install=1, so it should normally download a full install package.
  wget \
    --method=post \
    -O "$redcapZipPath" \
    -q \
    --body-data="username=$APPSETTING_redcapCommunityUsername&password=$APPSETTING_redcapCommunityPassword&version=$APPSETTING_zipVersion&install=1" \
    --header=Content-Type:application/x-www-form-urlencoded \
    https://redcap.vumc.org/plugins/redcap_consortium/versions.php

  if grep -qi error "$redcapZipPath"; then
    cat "$redcapZipPath" >> "$logFile"
    exit 1
  fi

  echo "Downloaded REDCap zip file from REDCap Community site" >> "$logFile"

else
  echo "Downloading REDCap zip file from storage" >> "$logFile"

  wget -q -O "$redcapZipPath" "$APPSETTING_redcapAppZip"
fi

# Validate zip exists
if [ ! -s "$redcapZipPath" ]; then
  echo "REDCap zip was not downloaded or is empty: $redcapZipPath" >> "$logFile"
  exit 1
fi

####################################################################################
# Extract package
####################################################################################

rm -rf "$extractPath"
mkdir -p "$extractPath"

echo "Unzipping REDCap zip to $extractPath" >> "$logFile"
unzip -oq "$redcapZipPath" -d "$extractPath"

echo "Extracted package structure:" >> "$logFile"
find "$extractPath" -maxdepth 4 -type d >> "$logFile"

####################################################################################
# INSTALL mode
####################################################################################

if [ "$redcapPackageType" = "INSTALL" ]; then
  echo "Running REDCap INSTALL deployment" >> "$logFile"

  # A full install package should normally have:
  #   extracted/redcap/index.php
  #   extracted/redcap/cron.php
  #
  # Some packages may be nested, so find a folder containing index.php, cron.php,
  # and install.php, but avoid selecting redcap_v* upgrade/version folders if possible.

  installSourcePath=""

  if [ -f "$extractPath/redcap/index.php" ] && [ -f "$extractPath/redcap/cron.php" ]; then
    installSourcePath="$extractPath/redcap"
  else
    installSourcePath="$(find "$extractPath" \
      -maxdepth 5 \
      -type f \
      -name 'cron.php' \
      -printf '%h\n' \
      | grep -v '/redcap_v[0-9]' \
      | head -n 1)"
  fi

  if [ -z "$installSourcePath" ]; then
    echo "Could not find full REDCap install application root." >> "$logFile"
    echo "For INSTALL mode, the ZIP should contain a full REDCap application root, normally redcap/index.php and redcap/cron.php." >> "$logFile"
    exit 1
  fi

  if [ ! -f "$installSourcePath/index.php" ]; then
    echo "INSTALL source is missing index.php: $installSourcePath" >> "$logFile"
    exit 1
  fi

  if [ ! -f "$installSourcePath/cron.php" ]; then
    echo "INSTALL source is missing cron.php: $installSourcePath" >> "$logFile"
    exit 1
  fi

  echo "Detected full REDCap install source folder: $installSourcePath" >> "$logFile"

  # Optional safety backup of local files/folders that may already exist.
  backupPath="/tmp/redcap-existing-backup"
  rm -rf "$backupPath"
  mkdir -p "$backupPath"

  if [ -f "$stableRoot/database.php" ]; then
    echo "Backing up existing database.php" >> "$logFile"
    cp "$stableRoot/database.php" "$backupPath/database.php"
  fi

  if [ -d "$stableRoot/modules" ]; then
    echo "Backing up existing modules folder" >> "$logFile"
    cp -a "$stableRoot/modules" "$backupPath/modules"
  fi

  if [ -d "$stableRoot/temp" ]; then
    echo "Backing up existing temp folder" >> "$logFile"
    cp -a "$stableRoot/temp" "$backupPath/temp"
  fi

  echo "Cleaning stable web root: $stableRoot" >> "$logFile"
  rm -rf "$stableRoot"/*

  echo "Copying full REDCap install package to stable web root" >> "$logFile"
  cd "$installSourcePath" && tar cf - . | ( cd "$stableRoot" && tar xf - )

  # Restore environment-specific files/folders if they existed.
  # This protects existing deployments if INSTALL is accidentally used over an existing system.
  if [ -f "$backupPath/database.php" ]; then
    echo "Restoring existing database.php" >> "$logFile"
    cp "$backupPath/database.php" "$stableRoot/database.php"
  fi

  if [ -d "$backupPath/modules" ]; then
    echo "Restoring existing modules folder" >> "$logFile"
    rm -rf "$stableRoot/modules"
    cp -a "$backupPath/modules" "$stableRoot/modules"
  fi

  if [ -d "$backupPath/temp" ]; then
    echo "Restoring existing temp folder" >> "$logFile"
    rm -rf "$stableRoot/temp"
    cp -a "$backupPath/temp" "$stableRoot/temp"
  fi

  echo "REDCap INSTALL deployment completed to stable path: $stableRoot" >> "$logFile"
fi

####################################################################################
# UPGRADE mode
####################################################################################

if [ "$redcapPackageType" = "UPGRADE" ]; then
  echo "Running REDCap UPGRADE deployment" >> "$logFile"

  # Upgrade packages are expected to have a wrapper folder:
  #   extracted/redcap/redcap_vX.X.X/
  #
  # The instructions say:
  #   Copy all files/folders inside the "redcap" folder into the main REDCap directory
  #   where database.php is located.
  #
  # So we copy:
  #   extracted/redcap/*
  # into:
  #   /home/site/wwwroot/
  #
  # We do NOT delete /home/site/wwwroot.

  upgradeSourcePath="$extractPath/redcap"

  if [ ! -d "$upgradeSourcePath" ]; then
    echo "UPGRADE package is missing expected redcap folder: $upgradeSourcePath" >> "$logFile"
    exit 1
  fi

  if [ ! -f "$stableRoot/database.php" ]; then
    echo "UPGRADE requested, but database.php was not found in $stableRoot." >> "$logFile"
    echo "This does not look like an existing REDCap installation. Use INSTALL mode with a full install package first." >> "$logFile"
    exit 1
  fi

  # Validate the upgrade package contains at least one redcap_v* folder.
  if ! find "$upgradeSourcePath" -maxdepth 1 -type d -name 'redcap_v*' | grep -q .; then
    echo "UPGRADE requested, but no redcap_v* folder was found directly inside $upgradeSourcePath." >> "$logFile"
    echo "This may not be a REDCap upgrade package." >> "$logFile"
    exit 1
  fi

  echo "Detected REDCap upgrade source folder: $upgradeSourcePath" >> "$logFile"
  echo "Merging upgrade package into existing REDCap directory: $stableRoot" >> "$logFile"

  cd "$upgradeSourcePath" && tar cf - . | ( cd "$stableRoot" && tar xf - )

  echo "REDCap UPGRADE files copied." >> "$logFile"
  echo "Now complete the REDCap database upgrade from the Control Center or by browsing to the new redcap_vX.X.X/upgrade.php URL." >> "$logFile"
fi

####################################################################################
# Cleanup
####################################################################################

rm -rf "$extractPath"
rm -f "$redcapZipPath"

echo "REDCap deployment block completed successfully" >> "$logFile"

####################################################################################
#
# Update database connection info in database.php
#
####################################################################################

echo "Updating database connection info in database.php" >> /home/site/log-$stamp.txt

cd /home/site/wwwroot

wget --no-check-certificate -O $APPSETTING_DBSslCa https://cacerts.digicert.com/DigiCertGlobalRootG2.crt.pem

sed -i "s|hostname[[:space:]]*= '';|hostname = getenv('DBHostName');|" database.php
sed -i "s|db[[:space:]]*= '';|db = getenv('DBName');|" database.php
sed -i "s|username[[:space:]]*= '';|username = getenv('DBUserName');|" database.php
sed -i "s|password[[:space:]]*= '';|password = getenv('DBPassword');|" database.php
sed -i "s|db_ssl_ca[[:space:]]*= '';|db_ssl_ca = getenv('DBSslCa');|" database.php

sed -i "s/db_ssl_verify_server_cert = false;/db_ssl_verify_server_cert = true;/" database.php
sed -i "s/$salt = '';/$salt = '$(echo $RANDOM | md5sum | head -c 20; echo;)';/" database.php

####################################################################################
#
# Configure REDCap recommended settings
#
####################################################################################

echo "Configuring REDCap recommended settings" >> /home/site/log-$stamp.txt

# HACK: 2025-11-11: SMTP settings are not supported anymore; commenting out for now
# sed -i "s|SMTP[[:space:]]*= ''|SMTP = '$APPSETTING_smtpFQDN'|" /home/site/repository/Files/settings.ini
# sed -i "s|smtp_port[[:space:]]*= |smtp_port = $APPSETTING_smtpPort|" /home/site/repository/Files/settings.ini
# sed -i "s|sendmail_from[[:space:]]*= ''|sendmail_from = '$APPSETTING_fromEmailAddress'|" /home/site/repository/Files/settings.ini
# sed -i "s|sendmail_path[[:space:]]*= ''|sendmail_path = '/usr/sbin/sendmail -t -i'|" /home/site/repository/Files/settings.ini

cp /home/site/repository/Files/settings.ini /home/site/ini/redcap.ini

####################################################################################
#
# For better security, it is recommended that you enable the 
# session.cookie_secure option in your web server's PHP.INI file
#
####################################################################################

echo "Enabling session.cookie_secure option in redcap.ini" >> /home/site/log-$stamp.txt
echo "session.cookie_secure = On" >> /home/site/ini/redcap.ini

####################################################################################
#
# Copy postbuild.sh to PostDeploymentActions for execution after deployment
#
####################################################################################

mkdir -p /home/site/deployments/tools/PostDeploymentActions
cp /home/site/repository/scripts/bash/postbuild.sh /home/site/deployments/tools/PostDeploymentActions/postbuild.sh

####################################################################################
#
# Copy startup.sh /home for a custom startup
#
####################################################################################

cp /home/site/repository/scripts/bash/startup.sh /home/startup.sh
