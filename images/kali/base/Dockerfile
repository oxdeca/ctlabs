FROM       docker.io/kalilinux/kali-rolling
ENV        container docker 
ENV        DEBIAN_FRONTEND=noneinteractive
ENV        TERM=linux

RUN        apt update && apt -y install attr acl vim less systemd iproute2 tcpdump iputils-ping curl   && \
           apt -y install iptables openssh-server python3 python3-apt pipx nmap netcat-traditional git && \
           apt -y install dnsutils lsof sudo locales fonts-noto-color-emoji htop gnupg bsdmainutils    && \
           echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen && locale-gen && update-locale LANG=en_US.UTF-8 && \
           echo 'export LANG=en_US.UTF-8' >> /etc/profile.d/locale.sh      && \
           printf "set paste\n" >> /etc/vim/vimrc

RUN        useradd -U -s /bin/bash -d /home/ansible -m ansible && echo 'ansible ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ansible
RUN        systemctl enable ssh && systemctl mask systemd-logind dev-hugepages.mount
COPY       --chmod=0755 ctlabs-exec /usr/bin/ctlabs-exec 
COPY       ssh.service /etc/systemd/system/ssh.service

ENTRYPOINT ["/usr/lib/systemd/systemd"]
