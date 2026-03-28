FROM         debian:13
ENV          container docker
ENV          DEBIAN_FRONTEND=noninteractive
ENV          TERM=linux

RUN         apt update && apt -y install attr acl vim less systemd iproute2 tcpdump netcat-traditional htop  && \
            apt -y install iptables iputils-ping syslog-ng openssh-server python3-apt curl gpg gawk sudo     && \
            sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config && \
            printf "set paste\n" >> /etc/vim/vimrc

RUN         echo 'if [ -f "/etc/bashrc.kali" ]; then . /etc/bashrc.kali; fi' > /etc/profile.d/ctlabs.sh      && \
            echo 'if [ -f "/etc/profile" ]; then . /etc/profile; fi' >> ~/.bashrc

COPY        bashrc.kali /etc/bashrc.kali
COPY       --chmod=0755 ctlabs-exec /usr/bin/ctlabs-exec 
COPY       sshd.service /etc/systemd/system/ssh.service

ENTRYPOINT  ["/bin/systemd"]
