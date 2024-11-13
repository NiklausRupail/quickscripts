#!/usr/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# First you need all of the dependancies
if [ $(dpkg-query -W -f='${Status}' wget 2>/dev/null | grep -c "ok installed") -eq 0 ];
then
    sudo apt-get install wget --yes
fi
if [ $(dpkg-query -W -f='${Status}' gdebi 2>/dev/null | grep -c "ok installed") -eq 0 ];
then
    sudo apt-get install gdebi --yes
fi
cd /tmp 
wget "https://discord.com/api/download?platform=linux&format=deb" -O /tmp/discord.deb 
sudo gdebi /tmp/discord.deb -n && rm -rf /tmp/discord.deb
sudo apt-get install -fy