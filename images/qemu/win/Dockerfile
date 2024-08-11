FROM        scratch
COPY        --from=docker.io/dockurr/windows / /

RUN         apt update && apt -y install attr acl systemd openssh-server  && \
            echo "root:secret" | chpasswd && sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config

COPY        --chmod=0750 network.sh /run/network.sh
COPY        qemu.service /etc/systemd/system/qemu.service
COPY        sshd-mgmt.service /etc/systemd/system/sshd-mgmt.service
RUN         systemctl enable sshd-mgmt.service && systemctl enable qemu.service && \
            systemctl disable ssh.service && systemctl disable nginx.service

ENV         RAM_SIZE    "4G"
ENV         CPU_CORES   "2"
ENV         DISK_SIZE   "20G"
ENV         VERSION     "2022"
ENV         USER_PORTS  "5985,5986"
ENV         USERNAME    "ctlabs"
ENV         PASSWORD    "secret"

VOLUME      /storage

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
