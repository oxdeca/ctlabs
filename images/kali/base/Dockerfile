FROM        docker.io/kalilinux/kali-rolling
ENV         container docker 
ENV         DEBIAN_FRONTEND=noneinteractive
ENV         TERM=linux

RUN         apt update && apt -y install attr acl vim less systemd iproute2 tcpdump gnupg htop iputils-ping locales    && \
            apt -y install iptables openssh-server python3 python3-apt pipx nmap netcat-traditional dnsutils lsof sudo && \
            echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen && locale-gen && update-locale LANG=en_US.UTF-8 && \
            echo 'export LANG=en_US.UTF-8' >> /etc/profile.d/locale.sh      && \
            sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config && \
            printf "set paste\n" >> /etc/vim/vimrc

RUN         systemctl enable ssh && systemctl mask systemd-logind dev-hugepages.mount
COPY       --chmod=0755 ctlabs-exec /usr/bin/ctlabs-exec 
COPY       ssh.service /etc/systemd/system/ssh.service

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
