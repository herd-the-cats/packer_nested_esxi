# Nested ESXI Packer template

This template creates an ESXi VM image nested on the qemu builder. The wrapper script is designed to pass a crypted root password on the boot command line and write log files.
In order to get nested ESXi on KVM working, the following kernel params need to be added to an /etc/modprobe.d/kvm.conf file:
```
options kvm-intel nested=1 ept=1
options kvm ignore_msrs=1
#options kvm_amd nested=1
```
(AMD option commented out.)

Besides the kvm module options, nested ESXi is finicky about the virtual hardware. The qemuargs on the builder (and subsequent libvirt/qemu config) may need to be changed. You may be able to use host-model for the CPU, but especially on the 6.0 version (older probably won't work) the virtual hardware may be seen as incompatible.

The VMWare ovftool must also be installed to create the ova file.
