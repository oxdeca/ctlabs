Make sure the kernel module `openvswitch` is loaded on the vm:

```bash
sh# modeprobe openvswitch
```

To automatically start on boot:

```bash
# /etc/modules-load.d/openvswitch
openvswitch
```



To start a container the following Capabilities have to be configured:

   ovs:
      image: ctlabs/c9/ovs
      caps : [SYS_NICE,NET_BIND_SERVICE,NET_BROADCAST,IPC_LOCK]
