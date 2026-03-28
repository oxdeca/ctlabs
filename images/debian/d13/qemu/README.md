
# How to create qemu images compatible with ctlabs

## Debian

### Used Packages

- `openssh-server`
- `openssh-client`
- `xterm`
- `lvm2`
- `fdisk`
- `htop`
- `nfs-kernel-server`
- `bpftrace`
- `linux-kernel-headers`
  + `apt search linux-headers-$(uname -r)`

### ctlabs-setup.service

___/etc/systemd/system/ctlabs-net.service___

```bash
# /etc/systemd/system/ctlabs-setup.service
[Unit]
Description=ctlabs network setup
After=network.target

[Service]
Type=oneshot
ExecStart=/root/ctlabs_run_setup.sh
RemainAfterExit=true
#ExecStop=/root/qemu_init.sh
StandardOutput=journal

[Install]
WantedBy=multi-user.target
```

___/root/ctlabs_run_setup.sh___

```bash
#!/bin/bash

mount -t 9p -o trans=virtio setup /mnt

cd /mnt
bash ./ctlabs_net_setup.sh
cd -

umount /mnt

exit 0 
```


### sshd-mgmt.service

```bash
# /etc/systemd/system/sshd-mgmt.service
[Unit]
Description=ctlabs mgmt-sshd 
Documentation=man:sshd(8) man:sshd_config(5)
After=ctlabs-net.service
ConditionPathExists=!/etc/ssh/sshd_not_to_be_run

[Service]
EnvironmentFile=-/etc/default/ssh
ExecStartPre=/sbin/ip vrf exec mgmt /usr/sbin/sshd -t
ExecStart=/sbin/ip vrf exec mgmt /usr/sbin/sshd -D $SSHD_OPTS
ExecReload=/sbin/ip vrf exec mgmt /usr/sbin/sshd -t
ExecReload=/sbin/ip vrf exec mgmt /bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=10s
RestartPreventExitStatus=255
Type=notify
RuntimeDirectory=sshd
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
```


### Environment

___/etc//bashrc.kali___

It's a copy of bashrc.kali

___/etc/profile.d/99-ctlabs.sh___

```bash
#!/bin/bash

export TERM=linux

if [ -f /usr/bin/resize ]; then
  resize > /dev/null
fi

if [ -f /etc/bashrc.kali ]; then
  . /etc/bashrc.kali
fi
```



