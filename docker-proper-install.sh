#!/usr/bin/env bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

apt install -fy curl git 
curl -sSL https://get.docker.com/ | sh # Running the docker install script
systemctl start docker
curl -L "https://github.com/docker/compose/releases/download/v2.12.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose #Download the Right Version of docker-compose
chmod +x /usr/local/bin/docker-compose # Grant execution permissions to docker-compose

(docker -v && echo "Installed docker sucessfuly") || echo "Error occured while installing docker"
(docker-compose --version && echo "Installed docker compose successfully") || echo "Error occured while installing docker"

