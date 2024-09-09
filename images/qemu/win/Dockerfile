FROM        scratch
COPY        --from=docker.io/dockurr/windows / /

RUN         apt update && apt -y install attr acl systemd openssh-server python3 tmux htop vim iputils-ping && \
            echo "root:secret" | chpasswd && sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config

COPY        qemu.service      /etc/systemd/system/qemu.service
COPY        sshd-mgmt.service /etc/systemd/system/sshd-mgmt.service
COPY        bashrc.kali       /etc/profile.d/ctlabs-profile.sh

RUN         systemctl enable sshd-mgmt.service && systemctl enable qemu.service && \
            systemctl disable ssh.service && systemctl disable nginx.service

COPY        --chmod=0750 if-up      /root/if-up
COPY        --chmod=0750 if-down    /root/if-down

COPY        --chmod=0750 entry.sh   /run/entry.sh
COPY        --chmod=0750 network.sh /run/network.sh
#COPY        --chmod=0750 config.sh  /run/config.sh

ENV         RAM_SIZE    "2G"
ENV         CPU_CORES   "2"
ENV         DISK_SIZE   "20G"
ENV         VERSION     "2022"
ENV         USERNAME    "ctlabs"
ENV         PASSWORD    "secret"
ENV         DHCP        "no"
ENV         NETWORK     "n"
ENV         VNC         "1"

VOLUME      /storage

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
