#!/bin/sh

#
# File: install.sh
# Author: Scott Kidder
# Purpose: This script will configure a newly-imaged Raspberry Pi running 
#   Raspbian Wheezy 2013-07-26 with the dependencies and HSMM-Pi components.
#

PROJECT_HOME=${HOME}/hsmm-pi

cd ${HOME}

# Update list of packages
sudo apt-get update

# Update existing packages
sudo apt-get upgrade -y

# Install Web Server deps
sudo apt-get install -y \
    apache2 \
    php5 \
    sqlite \
    php-pear \
    php5-sqlite  \
    php5-curl \
    dnsmasq \
    chkconfig \
    bison \
    flex \
    gpsd \
    gpsd-clients \
    libnet-gpsd3-perl

# Install cakephp with Pear
sudo pear channel-discover pear.cakephp.org
sudo pear install cakephp/CakePHP

# Checkout the HSMM-Pi project
if [ ! -e ${PROJECT_HOME} ]; then
    git clone https://github.com/urlgrey/hsmm-pi.git
else
    cd ${PROJECT_HOME}
    git pull
fi

# Set symlink to webapp
cd /var/www
if [ ! -e /var/www/hsmm-pi ]; then
    sudo ln -s ${PROJECT_HOME}/src/var/www/hsmm-pi
fi
sudo rm -f /var/www/index.html
sudo ln -s ${PROJECT_HOME}/src/var/www/index.html /var/www/

# Create temporary directory used by HSMM-PI webapp, granting write priv's to www-data
cd ${PROJECT_HOME}/src/var/www/hsmm-pi
mkdir -p tmp/cache/models
mkdir -p tmp/cache/persistent
mkdir -p tmp/logs
mkdir -p tmp/persistent
sudo chown -R pi.www-data tmp
sudo chmod -R 775 tmp

# Set permissions on system files to give www-data group write priv's
for file in /etc/hosts /etc/hostname /etc/resolv.conf /etc/network/interfaces /etc/rc.local /etc/default/gpsd; do
    sudo chgrp www-data ${file}
    sudo chmod g+w ${file}
done

sudo chgrp www-data /etc/dnsmasq.d
sudo chmod 775 /etc/dnsmasq.d

sudo chgrp www-data /etc/dhcp/dhclient.conf
sudo chmod g+w /etc/dhcp/dhclient.conf

# Copy scripts into place
if [ ! -e /usr/local/bin/callsign_announcement.sh ]; then
    sudo cp ${PROJECT_HOME}/src/var/www/hsmm-pi/webroot/files/callsign_announcement.sh.template /usr/local/bin/callsign_announcement.sh
    sudo chgrp www-data /usr/local/bin/callsign_announcement.sh
    sudo chmod 775 /usr/local/bin/callsign_announcement.sh
fi

if [ ! -e /usr/local/bin/read_gps_coordinates.pl ]; then
    sudo cp ${PROJECT_HOME}/src/usr/local/bin/read_gps_coordinates.pl /usr/local/bin/read_gps_coordinates.pl
    sudo chgrp www-data /usr/local/bin/read_gps_coordinates.pl
    sudo chmod 775 /usr/local/bin/read_gps_coordinates.pl
fi

sudo mkdir -p /var/data/hsmm-pi
sudo chown root.www-data /var/data/hsmm-pi
sudo chmod 775 /var/data/hsmm-pi
if [ ! -e /var/data/hsmm-pi/hsmm-pi.sqlite ]; then
    sudo cp ${PROJECT_HOME}/src/var/data/hsmm-pi/hsmm-pi.sqlite /var/data/hsmm-pi/hsmm-pi.sqlite
    sudo chown root.www-data /var/data/hsmm-pi/hsmm-pi.sqlite
    sudo chmod 664 /var/data/hsmm-pi/hsmm-pi.sqlite
fi

# enable apache mod-rewrite
cd /etc/apache2/mods-enabled
sudo ln -s ../mods-available/rewrite.load
sudo cp ${PROJECT_HOME}/src/etc/apache2/conf.d/hsmm-pi.conf /etc/apache2/conf.d/hsmm-pi.conf
sudo service apache2 restart

# Download and build olsrd
cd /var/tmp
git clone git://olsr.org/olsrd.git
cd olsrd

# Checkout the latest 0.6.6 release, have seen intermittent problems with 0.6.5
git checkout release-0.6.6

# build the OLSRD core
make
sudo make install

# build the OLSRD plugins (libs)
make libs
sudo make libs_install

sudo mkdir /etc/olsrd
sudo cp debian/olsrd.conf /etc/olsrd/olsrd.conf
sudo chgrp -R www-data /etc/olsrd
sudo chmod g+w -R /etc/olsrd

sudo cp debian/olsrd.init /etc/init.d/olsrd
sudo chmod +x /etc/init.d/olsrd

sudo mkdir -p /etc/default
sudo cp ${PROJECT_HOME}/src/etc/default/olsrd /etc/default/olsrd

cd /var/tmp
rm -rf /var/tmp/olsrd

sudo rm -f /etc/olsrd.conf
sudo ln -s /etc/olsrd/olsrd.conf /etc/olsrd.conf
sudo ln -s /usr/local/sbin/olsrd /usr/sbin/

# enable services
sudo chkconfig olsrd on
sudo chkconfig dnsmasq on
sudo chkconfig gpsd on

# install CRON jobs for reboot and callsign announcement
sudo cp ${PROJECT_HOME}/src/etc/cron.d/* /etc/cron.d/
