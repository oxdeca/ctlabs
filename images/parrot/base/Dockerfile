FROM        docker.io/parrotsec/core
ENV         container docker 
ENV         DEBIAN_FRONTEND=noneinteractive
ENV         TERM=linux

RUN         apt update && apt -y full-upgrade && apt -y install attr acl less systemd iproute2 tcpdump gnupg sudo  && \
            apt -y install iptables openssh-server python3 htop iputils-ping pipx nmap netcat-traditional dnsutils lsof && \
            sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config  && \
            printf "set paste\n" >> /etc/vim/vimrc

RUN         systemctl enable ssh && systemctl mask systemd-logind dev-hugepages.mount
COPY        bashrc.kali /etc/bashrc.kali
COPY       --chmod=0755 ctlabs-exec /usr/bin/ctlabs-exec 
COPY       sshd.service /etc/systemd/system/ssh.service
RUN        systemctl enable ssh.service

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
