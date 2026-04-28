FROM         debian:12
ENV          container docker
ENV          DEBIAN_FRONTEND=noninteractive
ENV          TERM=linux

RUN         apt update && apt -y install attr acl vim less systemd iproute2 tcpdump netcat-traditional  && \
            apt -y install iptables iputils-ping syslog-ng openssh-server python3-apt curl gpg gawk     && \
            apt -y install fonts-noto-color-emoji htop sudo locales                                     && \
            sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config                             && \
            echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen && locale-gen                                   && \
            echo 'export LANG=en_US.UTF-8' > /etc/profile.d/locale.sh                                   && \
            printf "set paste\n" >> /etc/vim/vimrc

RUN         echo 'if [ -f "/etc/bashrc.kali" ]; then . /etc/bashrc.kali; fi' > /etc/profile.d/ctlabs.sh && \
            echo 'if [ -f "/etc/profile" ]; then . /etc/profile; fi' >> ~/.bashrc

COPY        bashrc.kali /etc/bashrc.kali
COPY       --chmod=0755 ctlabs-exec /usr/bin/ctlabs-exec 
COPY       ssh.service /etc/systemd/system/ssh.service
RUN        systemctl enable ssh.service

ENTRYPOINT  ["/bin/systemd"]
