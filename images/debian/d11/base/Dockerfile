FROM        debian:11
ENV         container docker

ENV         DEBIAN_FRONTEND=noninteractive
ENV         DEBCONF_NONINTERACTIVE_SEEN=true
ENV         DEBCONF_NOWARNINGS=yes

ENV         TERM=linux

RUN         apt update && apt -y install attr acl vim less systemd iproute2 tcpdump netcat htop iputils-ping  && \
            apt -y install iptables syslog-ng openssh-server python3-apt curl gpg gawk sudo gnupg             && \
            echo "root:secret" | chpasswd && sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config  && \
            printf "set paste\n" >> /etc/vim/vimrc

COPY        bashrc.kali /etc/profile.d/kali.sh
COPY        sshd-mgmt.service /etc/systemd/system/sshd-mgmt.service
RUN         systemctl enable sshd-mgmt.service && systemctl disable ssh.service

ENTRYPOINT  ["/bin/systemd"]
