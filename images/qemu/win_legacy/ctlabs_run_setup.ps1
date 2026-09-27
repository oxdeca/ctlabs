# powershell script to setup ethernet devices
# example

# disable interfaces
netsh interface set interface "Ethernet"   disable

# enable interfaces
netsh interface set interface "Ethernet"   enable

# set mtu=1460
netsh interface ipv4 set subinterface "Ethernet" mtu=1460 store=persistent

# set ip 
netsh interface ipv4 set address name="Ethernet" static 192.168.30.24 255.255.255.0 192.168.30.1

# dns
netsh interface ipv4 add dnsserver name="Ethernet" address=1.1.1.1 index=1
netsh interface ipv4 add dnsserver name="Ethernet" address=8.8.8.8 index=2
