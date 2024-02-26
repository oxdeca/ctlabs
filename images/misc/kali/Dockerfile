FROM        docker.io/kalilinux/kali-rolling
ENV         container docker 
ENV         DEBIAN_FRONTEND=noneinteractive
ENV         TERM=linux

RUN         apt update && apt -y install attr acl vim less systemd iproute2 tcpdump lsof htop iputils-ping    && \
            apt -y install iptables openssh-server python3 python3-apt nmap netcat-traditional dnsutils       && \
            echo "root:secret" | chpasswd && sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config  && \
            printf "set paste\n" >> /etc/vim/vimrc

RUN         systemctl enable ssh && systemctl mask systemd-logind dev-hugepages.mount

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
