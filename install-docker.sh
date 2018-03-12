#!/bin/bash

#
# Simple shell script to automate installing Docker CE runtimes
# on an Ubuntu cloud host
#

set -xe

# add docker key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

# add debian repo
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# update
apt-get update -y
apt-get upgrade -y

# install
apt-get install -y docker-ce

# ensure ubuntu default user has docker rights
usermod -aG docker ubuntu

# FIN
exit 0
