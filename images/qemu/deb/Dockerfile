FROM        scratch
COPY        --from=docker.io/qemux/qemu-docker / /

RUN         apt update && apt -y install attr acl systemd openssh-server python3  && \
            echo "root:secret" | chpasswd && sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config

COPY        qemu.service /etc/systemd/system/qemu.service
COPY        sshd-mgmt.service /etc/systemd/system/sshd-mgmt.service
RUN         systemctl enable sshd-mgmt.service && systemctl enable qemu.service && \
            systemctl disable ssh.service && systemctl disable nginx.service

ENV         BOOT        "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.6.0-amd64-netinst.iso"
ENV         RAM_SIZE    "2G"
ENV         CPU_CORES   "2"
ENV         DISK_SIZE   "8G"

VOLUME      /storage

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
