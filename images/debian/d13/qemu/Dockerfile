FROM        ctlabs/d13/base:latest

RUN         apt update && apt -y install qemu-system-x86 curl tmux mkisofs && \
            apt -y clean && apt -y autoclean && apt -y autoremove

COPY        debian-13-nocloud-amd64.qcow2   /media/
COPY        --chmod=0750 files/if-up        /root/
COPY        --chmod=0750 files/if-down      /root/
COPY        --chmod=0750 files/qemu_init.sh /root/
COPY        files/qemu.service              /etc/systemd/system/

RUN         systemctl disable ssh.service && systemctl enable qemu.service

ENTRYPOINT  ["/bin/systemd"]
