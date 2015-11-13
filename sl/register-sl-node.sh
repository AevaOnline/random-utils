#!/usr/bin/env python

# Create a node in the ironic db by querying the specified bare metal svr via SL API

import sys
import os
import subprocess
import re
import getopt
from pprint import pprint as pp
import SoftLayer

def usage(exitCode=0):
    print 'Usage: '+sys.argv[0]+' [-c|--create] [-b|--bifrost] [--rebuild] hostname [additional ironic node-update args]'
    print '  Query SL about the bare metal svr hostname specified, and define it in the ironic db. If -c is'
    print '  not specified, the cmds to create the ironic node will just be displayed instead of run.'
    print '  This cmd uses the SL API, so you must create ~/.softlayer or set SL_USERNAME and SL_API_KEY.'
    print 'Options:'
    print '  -c|--create:  run the cmds to create the ironic node'
    print '  -b|--bifrost:  generate the cmds appropriate for bifrost mode'
    print '  --rebuild:  only generate the cmds for adding the instance_info for a bifrost node rebuild'
    sys.exit(exitCode)

def error(msg, exitCode=3):
    print 'Error: '+str(msg)
    sys.exit(exitCode)

# Process the cmd line args
try:
    opts, args = getopt.getopt(sys.argv[1:], 'hcb', ['help','create','bifrost','rebuild'])  # use ":" after short options or "=" after long options if they required a value
except getopt.GetoptError:
    usage(2)
# get the options in a dict
options = {}
for opt, value in opts:
    options[opt] = value
if '-h' in options or '--help' in options:  usage(1)
# if '-c' in options or '--create' in options:  error('option -c|--create not implemented yet.  For now this script will just display the appropriate ironic commands, instead of directly creating the ironic node.')
if '--rebuild' in options and ('-b' not in options and '--bifrost' not in options):
    error('--rebuild can only be specified with -b|--bifrost')

# check the positional args
if len(args) < 1:  usage(2)
name = args.pop(0)
if name.find('.') != -1:
    hostname, domain = name.split('.', 1)
else:
    hostname = name
    domain = None
if args:  updateArgs = ' '.join(args)
else:  updateArgs = None

# Get the attributes of the bm svr from SL
# client = SoftLayer.Client(endpoint_url=SoftLayer.API_PUBLIC_ENDPOINT)
client = SoftLayer.Client()         # i am hoping it will use the private endpoint if inside sl
# no value is returned for networkComponents[networkVlan]
mask = 'mask[id,fullyQualifiedDomainName,hardwareStatus,memoryCapacity,lastTransaction[elapsedSeconds,transactionStatus,pendingTransactions], \
        networkComponents[primaryIpAddress,macAddress,ipmiIpAddress,ipmiMacAddress,maxSpeed,name,port,status,networkVlan[vlanNumber],router[hostname]], \
        billingItem[hostName,item[keyName,totalPhysicalCoreCapacity,totalPhysicalCoreCount,totalProcessorCapacity]],remoteManagementAccounts, \
        activeComponents[id,hardwareComponentModel[id,hardwareGenericComponentModel[capacity,units,hardwareComponentType[keyName]]]] ]'
        # operatingSystem[id,passwords[password,username]],
        # networkVlans[vlanNumber,networkSpace,primaryRouter[hostname],subnets[networkIdentifier,cidr,netmask,gateway,subnetType]], \
if domain:
    filterStr = {"hardware":{"hostname":{"operation":hostname},"domain":{"operation":domain}}}
else:
    filterStr = {"hardware":{"hostname":{"operation":hostname}}}
svrs = client['Account'].getHardware(mask=mask, filter=filterStr)
if len(svrs) == 0:  error('did not find any bare metal servers named '+name)
elif len(svrs) > 1:  error('found more than 1 bare metal server named '+name)

# Get the important properties out of the sl output
svr = svrs[0]
# pp(svr)
# find the bmc and eth0
for nic in svr['networkComponents']:
    if 'ipmiIpAddress' in nic and 'ipmiMacAddress' in nic and 'name' in nic and nic['name']=='mgmt' and 'status' in nic and nic['status']=='ACTIVE':
        ipmiIpAddress = nic['ipmiIpAddress']
        ipmiMacAddress = nic['ipmiMacAddress']
    if ('name' in nic and nic['name']=='eth' and 'port' in nic and nic['port']==0 and 'primaryIpAddress' in nic and 'status' in nic and nic['status']=='ACTIVE' and
            'router' in nic and 'hostname' in nic['router'] and nic['router']['hostname'].startswith('bcr') ):
        privateIp = nic['primaryIpAddress']
        privateMac = nic['macAddress']
for acct in svr['remoteManagementAccounts']:
    if 'username' in acct and acct['username']=='root' and 'password' in acct:  ipmiPw = acct['password']
memory = str(svr['memoryCapacity'] * 1024)      # value from sl is in GB and we need it in MB
# usually either totalPhysicalCoreCapacity (str) or totalProcessorCapacity (int) are present
billing = svr['billingItem']['item']
if 'totalPhysicalCoreCapacity' in billing:  cpus = str(billing['totalPhysicalCoreCapacity'])
elif 'totalProcessorCapacity' in billing:  cpus = billing['totalPhysicalCoreCount']
# else:  cpus = '<unknown>'
#todo: there might be a better way to get local disk size
# disk = '<unknown>'
for component in svr['activeComponents']:
    try:
        comp = component['hardwareComponentModel']['hardwareGenericComponentModel']
        if comp['hardwareComponentType']['keyName'] == 'HARD_DRIVE':
            if comp['units'] == 'GB':  disk = comp['capacity']
            elif comp['units'] == 'MB':   disk = str(int(int(comp['capacity'])/1024))
    except:
        pass

# verify all required vars are set and give error msg if not
if 'ipmiIpAddress' not in locals() or not ipmiIpAddress:  error('could not get ipmiIpAddress of the specified svr')
if 'ipmiMacAddress' not in locals() or not ipmiMacAddress:  error('could not get ipmiMacAddress of the specified svr')
if 'privateIp' not in locals() or not privateIp:  error('could not get privateIp of the specified svr')
if 'privateMac' not in locals() or not privateMac:  error('could not get privateMac of the specified svr')
if 'ipmiPw' not in locals() or not ipmiPw:  error('could not get ipmiPw of the specified svr')
if 'memory' not in locals() or not memory:  error('could not get memory of the specified svr')
if 'billing' not in locals() or not billing:  error('could not get billing of the specified svr')
if 'cpus' not in locals() or not cpus:  error('could not get cpus of the specified svr')
if 'disk' not in locals() or not disk:  error('could not get disk of the specified svr')

# Form and display the appropriate ironic commands for this node/bare metal svr
# driver should be agent_ipmitool or agent_ipminative
# to determine the list of possible driver_info properties:  ironic driver-properties agent_ipmitool
cmds =[]
if '--rebuild' not in options:
    cmds.append('ironic node-create -n '+hostname+' -d agent_ipmitool -i ipmi_address='+ipmiIpAddress+' -i ipmi_username=root -i ipmi_password='+ipmiPw+' -i ipmi_priv_level=OPERATOR -p memory_mb='+memory+' -p cpus='+cpus+' -p local_gb='+disk+' -p cpu_arch=x86_64')

if '-b' not in options and '--bifrost' not in options:
    # full openstack or devstack
    # kernel=$(nova image-list | egrep 'agent-deploy-kernel[^-]' | awk '{ print $2 }')
    # ramdisk=$(nova image-list | egrep 'agent-deploy-ramdisk[^-]' | awk '{ print $2 }')
    cmds.append("ironic node-update "+hostname+" add driver_info/deploy_kernel=$(nova image-list | egrep 'agent-deploy-kernel[^-]' | awk '{ print $2 }') driver_info/deploy_ramdisk=$(nova image-list | egrep 'agent-deploy-ramdisk[^-]' | awk '{ print $2 }')")
else:
    # if bifrost
    # need the ctrl nodes private ip for some of the url settings in bifrost mode
    try:
        # 1st get the list of private nic
        out = subprocess.check_output("ip a | grep -E '^[0-9]+:\s+[a-z]+0:\s'", stderr=subprocess.STDOUT, shell=True)
        # out = out.rstrip()
        # print 'out:'+out+'.'
        lines = out.splitlines()
        # pp(lines)
        # sys.exit()
    except subprocess.CalledProcessError as ex:
        error('Command"' + ex.cmd + '" returned returncode ' + str(ex.returncode) + " and output:\n" + ex.output)
    nic = None
    if filter(lambda x:re.search(r'^\d+:\s+bond0:\s', x), lines):  nic = 'bond0'
    elif filter(lambda x:re.search(r'^\d+:\s+eth0:\s', x), lines):  nic = 'eth0'
    elif filter(lambda x:re.search(r'^\d+:\s+int0:\s', x), lines):  nic = 'int0'
    elif filter(lambda x:re.search(r'^\d+:\s+eno1:\s', x), lines):  nic = 'eno1'
    if not nic:  error('can not find the private nic of the control node')
    # now get the ip of that nic
    try:
        out = subprocess.check_output("ip a list dev eth0 | grep -E '^\s*inet\s+[0-9]'", stderr=subprocess.STDOUT, shell=True)
        # out = out.rstrip()
        # print 'out:'+out+'.'
    except subprocess.CalledProcessError as ex:
        error('Command"' + ex.cmd + '" returned returncode ' + str(ex.returncode) + " and output:\n" + ex.output)
    match = re.search(r'^\s*inet\s+(\S+)/', out)
    if not match:  error('can not find the private ip of the control node')
    controlNodeIp = match.group(1)

    if '--rebuild' not in options:
        cmds.append('ironic node-update '+hostname+' add driver_info/deploy_ramdisk=http://'+controlNodeIp+':8080/ipa.initramfs driver_info/deploy_kernel=http://'+controlNodeIp+':8080/ipa.vmlinuz')
    # export IMAGE_CHECKSUM=$(md5sum /httpboot/deployment_image.qcow2 | awk '{print $1}')
    cmds.append("ironic node-update "+hostname+" add instance_info/root_gb=32 instance_info/image_source=http://"+controlNodeIp+":8080/deployment_image.qcow2 instance_info/image_checksum=$(md5sum /httpboot/deployment_image.qcow2 | awk '{print $1}')")

if updateArgs:
    cmds.append('ironic node-update '+hostname+' add '+updateArgs)

if '--rebuild' not in options:
    cmds.append("ironic port-create -n $(ironic node-list | grep "+hostname+" | awk '{print $2}' ) --address "+privateMac)

cmds.append('ironic node-validate '+hostname)

if '-b' not in options and '--bifrost' not in options:
    cmds.append('nova flavor-create --is-public true bm.'+hostname+' auto '+memory+' '+disk+' '+cpus)
    cmds.append('nova flavor-key bm.'+hostname+' set cpu_arch=x86_64')

if '-c' in options or '--create' in options:
    print 'Running commands:'
    for c in cmds:
        print '$', c
        rc = subprocess.call(c, shell=True)
        if rc > 0:  error('cmd rc: '+str(rc))
else:
    # just print the cmds
    for c in cmds:
        print c
sys.exit()
