FROM        ctlabs/d11/base:latest

RUN         apt update && apt -y install qemu-system-x86 lvm2 fdisk xterm curl
RUN         cd /media && curl -LO https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.qcow2


ENTRYPOINT  ["/bin/systemd"]
