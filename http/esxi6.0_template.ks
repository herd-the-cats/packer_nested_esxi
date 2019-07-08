# Accept EULA
vmaccepteula
# Set serial number
serialnum --esx=XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
# Set root password
%include /tmp/rootpw-include

# Install on local disk overwriting any existing VMFS datastore
install --firstdisk --overwritevmfs
# Network configuration
network --bootproto=dhcp --device=vmnic0
# Reboot after installation completed
reboot

%pre --interpreter=busybox
vsish -e get /system/bootCmdLine > /tmp/CmdLine
#printf "HDEBUG: /tmp/CmdLine contains\n$(cat /tmp/CmdLine)\n"

for param in $(cat /tmp/CmdLine) ; do
#  printf "HDEBUG: $param\n"
  case "$param" in
    packer_ks_rootpw=*)
      printf "HDEBUG: Using value ${param#*=}\n"
      export PACKER_ROOTPW="${param#*=}"
    ;;
    *)
      printf "HDEBUG: Unused parameter: %s\n" "$param"
    ;;
  esac
done

if [ ! -z PACKER_ROOTPW ]; then
  printf "HDEBUG: setting root password to hash $PACKER_ROOTPW\n"
  printf "rootpw --iscrypted %s\n" "$PACKER_ROOTPW" > /tmp/rootpw-include
else
  printf "ERROR: no crypted password supplied. Exiting.\n" ; exit 65
fi

%firstboot --interpreter=busybox

# Enable SSH & Shell
vim-cmd hostsvc/enable_ssh
vim-cmd hostsvc/start_ssh
esxcli system settings advanced set -o /UserVars/SuppressShellWarning -i 1
vim-cmd hostsvc/enable_esx_shell
vim-cmd hostsvc/start_esx_shell

# Enable GuestIPHack for remote Packer builds
esxcli system settings advanced set -o /Net/GuestIPHack -i 1

# Open firewall for VNC (only needed for upcoming 6.5 version)
esxcli network firewall ruleset set -e true -r gdbserver

# Automatically allow all VMs to start nested
grep -i "vmx.allowNested" /etc/vmware/config || printf "vmx.allowNested = TRUE\n" >> /etc/vmware/config

## Settings to ensure that ESXi cloning goes smooth
## http://www.virtuallyghetto.com/2013/12/how-to-properly-clone-nested-esxi-vm.html
#esxcli system settings advanced set -o /Net/FollowHardwareMac -i 1
#sed -i '/\/system\/uuid/d' /etc/vmware/esx.conf

# DHCP doesn't refresh correctly upon boot, this will force a renew, it will
# be executed on every boot, if you don't like this behavior you can remove
# the line during the Vagrant provisioning part.
sed -i '/exit 0/d' /etc/rc.local.d/local.sh
echo 'esxcli network ip interface set -e false -i vmk0; esxcli network ip interface set -e true -i vmk0' >> /etc/rc.local.d/local.sh
echo 'exit 0' >> /etc/rc.local.d/local.sh

# Ensure changes are persistent
/sbin/auto-backup.sh
