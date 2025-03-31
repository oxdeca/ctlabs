To start a container needs following Capabilities:

   ovs:
      image: ctlabs/c9/ovs
      caps : [SYS_NICE,NET_BIND_SERVICE,NET_BROADCAST,IPC_LOCK]
