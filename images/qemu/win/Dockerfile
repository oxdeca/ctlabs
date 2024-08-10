FROM        scratch
COPY        --from=docker.io/dockurr/windows / /

RUN         apt update && apt -y install attr acl systemd openssh-server  && \
            echo "root:secret" | chpasswd && sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config

COPY        --chmod=0750 entry.sh   /run/entry.sh
COPY        --chmod=0750 network.sh /run/network.sh
COPY        sshd-mgmt.service /etc/systemd/system/sshd-mgmt.service
RUN         systemctl enable sshd-mgmt.service && systemctl disable ssh.service && systemctl disable nginx.service

ENV         RAM_SIZE    "4G"
ENV         CPU_CORES   "2"
ENV         DISK_SIZE   "64G"
ENV         VERSION     "2019"
ENV         USER_PORTS  "5985,5986"

VOLUME      /storage

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
