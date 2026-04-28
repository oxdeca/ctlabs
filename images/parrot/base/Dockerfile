FROM        docker.io/parrotsec/core
ENV         container docker 
ENV         DEBIAN_FRONTEND=noneinteractive
ENV         TERM=linux

COPY        parrot.list /etc/apt/sources.list.d/parrot.list
RUN         apt update && apt -y full-upgrade && apt -y install attr acl less systemd iproute2 tcpdump && \
            apt -y install iptables openssh-server python3 htop iputils-ping pipx netcat-traditional   && \
            apt -y install sudo locales fonts-noto-color-emoji dnsutils lsof gnupg nmap                && \
            sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config  && \
            echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen && locale-gen        && \
            echo 'export LANG=en_US.UTF-8' > /etc/profile.d/locale.sh        && \
            printf "set paste\n" >> /etc/vim/vimrc

RUN         systemctl enable ssh && systemctl mask systemd-logind dev-hugepages.mount
COPY        bashrc.kali /etc/bashrc.kali
COPY       --chmod=0755 ctlabs-exec /usr/bin/ctlabs-exec 
COPY       ssh.service /etc/systemd/system/ssh.service
RUN        systemctl enable ssh.service

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
