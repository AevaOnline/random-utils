#!/bin/bash

# Install ironic on a SL VSI using bifrost
# Note: this has only been tested on a VSI running ubuntu 14.04

# References:
#   https://repo.hovitos.engineering/ironic/ironic-main/wikis/setup_ironic_with_bifrost
#   https://github.com/openstack/bifrost
#   https://etherpad.openstack.org/p/isnt-it-ironic-walkthrough

function usage {
  echo "Usage:  $0 dhcp_pool_start=<first-ip> dhcp_pool_end=<last-ip> [network_interface=<nic>]"
  exit 1
}

# Check the exit code of the cmd just run.  done this way instead of having a function to run the cmd
# so we dont run into quote issues.
function checkrc {
  rc=$?
  if [[ $rc != 0 ]]; then
  	echo "Exiting because the exit code of the last command was $rc"
  	exit $rc
  fi
}

# Process cmd line variable assignments, assigning each attr=val pair to a variable of same name
for i in $*; do
  # upper case the variable name
  #varstring=`echo "$i"|cut -d '=' -f 1|tr '[a-z]' '[A-Z]'`=`echo "$i"|cut -d '=' -f 2`
  export $i
done

# Set some defaults
if [[ -z $dhcp_pool_start || -z $dhcp_pool_end ]]; then usage; fi
set -x
if [[ -z $network_interface ]]; then network_interface='eth0'; fi

# Get some tools and bifrost
apt-get --yes install python-pip python-virtualenv python-dev git
checkrc
pip install SoftLayer     # in case they want to use slir-create.py or slcli
checkrc
# get rid of the annoying InsecurePlatformWarning warning
pip install --upgrade pip
checkrc
pip install requests[security]
checkrc
cd ~
if [[ ! -d bifrost ]]; then
  git clone https://github.com/openstack/bifrost.git
  checkrc
fi

cd ~/bifrost

# Customize the localhost and baremetal config files
localhost='playbooks/inventory/group_vars/localhost'
#if ! grep -qE '^network_interface:' $localhost; then
sed -i "s/^#* *network_interface:.*/network_interface: $network_interface/g;s/^#* *testing:.*/testing: false/g" $localhost
checkrc
#fi
if ! grep -qE '^dhcp_pool_start:' $localhost || ! grep -qE '^dhcp_pool_end:' $localhost; then
  echo -e "\ndhcp_pool_start: $dhcp_pool_start\ndhcp_pool_end: $dhcp_pool_end" >> $localhost
  checkrc
fi
baremetal='playbooks/inventory/group_vars/baremetal'
sed -i "s/^#* *network_interface:.*/network_interface: $network_interface/g" $baremetal
checkrc

# Get the ansible tools
./scripts/env-setup.sh
checkrc
source env-vars
checkrc
source /opt/stack/ansible/hacking/env-setup
checkrc

# Install ironic
cd ~/bifrost/playbooks
ansible-playbook -vvvv -i inventory/localhost install.yaml
checkrc

# Tell root that is should use real ironic nodes for the deploy step
bashrc=~/.bashrc
BIFROST_INVENTORY_SOURCE=ironic
if ! grep -qE '^export BIFROST_INVENTORY_SOURCE="*'$BIFROST_INVENTORY_SOURCE'"* *$' $bashrc; then
  echo -e "\nexport BIFROST_INVENTORY_SOURCE=$BIFROST_INVENTORY_SOURCE" >> $bashrc
  checkrc
fi
if ! grep -qE '^source ~/bifrost/env-vars' $bashrc; then
  echo -e "source ~/bifrost/env-vars" >> $bashrc
  checkrc
fi
if ! grep -qE '^alias env-setup="source /opt/stack/ansible/hacking/env-setup"' $bashrc; then
  echo -e 'alias env-setup="source /opt/stack/ansible/hacking/env-setup"' >> $bashrc
  checkrc
fi

# Create the ssh key if it doesn't exit
keyfile=/root/.ssh/id_rsa
if [[ ! -f $keyfile ]]; then
  ssh-keygen -f $keyfile -t rsa -N ''
  checkrc
fi

# ironic username should now exist, so add env vars to it so it can run ironic cmds
bashrc=~ironic/.bashrc
OS_AUTH_TOKEN=fake
IRONIC_URL=http://localhost:6385/
BIFROST_INVENTORY_SOURCE=ironic
if ! grep -qE '^export OS_AUTH_TOKEN="*'$OS_AUTH_TOKEN'"* *$' $bashrc || ! grep -qE '^export IRONIC_URL="*'$IRONIC_URL'"* *$' $bashrc || ! grep -qE '^export BIFROST_INVENTORY_SOURCE="*'$BIFROST_INVENTORY_SOURCE'"* *$' $bashrc; then
  echo -e "\nexport OS_AUTH_TOKEN=$OS_AUTH_TOKEN\nexport IRONIC_URL=$IRONIC_URL\nexport BIFROST_INVENTORY_SOURCE=$BIFROST_INVENTORY_SOURCE" >> $bashrc
  checkrc
fi
# for convenience, also let it run root cmds
if ! grep -qE '^ironic ALL=' /etc/sudoers; then
  echo -e "\nironic ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
  checkrc
fi
# add any ssh keys authorized to root to ironic too, so you can ssh in directly as ironic
auth1=~root/.ssh/authorized_keys
auth2=~ironic/.ssh/authorized_keys
if [[ -f $auth1 && ! -f $auth2 ]]; then
  mkdir -p ~ironic/.ssh
  checkrc
  cp $auth1 $auth2
  checkrc
  chown -R ironic:ironic ~ironic/.ssh
  checkrc
fi
# bifrost doesnt set the shell for the ironic user
usermod -s /bin/bash ironic
checkrc


# Instructions after birfrost ironic is installed
set +x
echo -e '\nIronic/bifrost is installed now. To verify that and then proceed with configuration, do:'
echo '1) su - ironic'
echo '2) ironic node-list; ironic port-list; ironic driver-list'
echo '3) create the bare metal nodes in ironic: create ~/.softlayer and run: slir-create.py -bc <bm-hostname>'
echo '4) run "ironic node-set-power-state <node> off" for each node'
echo '5) (optional) in a different xterm: watch "ironic node-list"'
echo '6) su - root (or ctrl-d)'
echo '7) source /opt/stack/ansible/hacking/env-setup'
echo '8) (optional) open the hw console for one of the ironic nodes'
echo '9) (optional) in a different xterm: tail -f /var/log/upstart/ironic-conductor.log'
echo '10) (optional) in a different xterm: tail -f /var/log/syslog'
echo '11) cd ~/bifrost/playbooks; ansible-playbook -vvvv -i inventory/bifrost_inventory.py deploy-dynamic.yaml'

exit
