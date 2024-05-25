FROM        ctlabs/d11/base:latest

RUN         apt update && apt -y install qemu-system-x86 curl screen
RUN         cd /media && curl -LO https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-nocloud-amd64.qcow2
#RUN         cd /media && curl -LO https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.qcow2
COPY        --chmod=0750 if-up   /root/
COPY        --chmod=0750 if-down /root/
COPY        --chmod=0750 qemu_init.sh /root/
COPY        qemu.service /etc/systemd/system/
RUN         systemctl enable qemu.service

ENTRYPOINT  ["/bin/systemd"]
CMD         ["/root/qemu_init.sh"]
