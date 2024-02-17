FROM         debian:12
ENV          container docker
ENV          DEBIAN_FRONTEND=noninteractive
ENV          TERM=linux

RUN         apt update && apt -y install attr acl vim less systemd iproute2 tcpdump netcat-traditional       && \
            apt -y install htop iputils-ping iptables syslog-ng openssh-server python3-apt                   && \
            echo "root:secret" | chpasswd && sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config && \
            printf "set paste\n" >> /etc/vimrc

RUN         echo 'if [ "/etc/bashrc.kali" ]; then . /etc/bashrc.kali; fi' >> /etc/bashrc
COPY        bashrc.kali /etc/bashrc.kali

ENTRYPOINT  ["/bin/systemd"]
