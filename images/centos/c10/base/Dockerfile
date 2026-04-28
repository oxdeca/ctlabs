FROM       quay.io/centos/centos:stream10
ENV        container docker
ENV        TERM=linux

RUN        ln -sfv /usr/share/zoneinfo/America/Toronto /etc/localtime                              && \
           dnf -y install yum-utils vim-enhanced rsync epel-release less git unzip procps crontabs && \
           dnf -y install tcpdump nc htop iproute nmap sudo openssh-server openssh-clients openvpn && \
           dnf -y install glibc-langpack-en iputils python3 python3-pip passwd iptables-nft        && \
           dnf -y install sshpass google-noto-color-emoji-fonts diffutils libreswan                && \
           echo 'LANG=en_US.UTF-8' > /etc/locale.conf && \
           sed -ri 's@^#(PermitRootLogin) .*@\1 yes@' /etc/ssh/sshd_config  && \
           echo alias vi='vim' >> /root/.bashrc_alias && printf "\nset paste\n" >> /etc/vimrc

RUN        systemctl mask systemd-logind systemd-sysusers systemd-tmpfiles-setup dev-hugepages.mount systemd-tmpfiles-clean 

RUN        echo 'if [ -f "/etc/bashrc.kali" ]; then . /etc/bashrc.kali; fi' >> /etc/bashrc
COPY       bashrc.kali /etc/profile.d/ctlabs-bashrc.sh
COPY       --chmod=0755 ctlabs-exec /usr/bin/ctlabs-exec 
COPY       sshd.service /etc/systemd/system/sshd.service
RUN        systemctl enable sshd.service

ENTRYPOINT ["/usr/lib/systemd/systemd"]
