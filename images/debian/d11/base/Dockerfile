FROM        debian:11
ENV         container docker
ENV         DEBIAN_FRONTEND=noninteractive
ENV         TERM=linux

RUN         apt update && apt -y install attr acl vim less systemd iproute2 tcpdump netcat    && \
            apt -y install htop iputils-ping iptables syslog-ng openssh-server python3-apt    && \
            echo "root:secret" | chpasswd && sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config

RUN         echo 'if [ -f "/etc/bashrc.kali" ]; then . /etc/bashrc.kali; fi' >> /etc/bash.bashrc
COPY        bashrc.kali /etc/bashrc.kali

ENTRYPOINT  ["/bin/systemd"]
