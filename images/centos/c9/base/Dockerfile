FROM       quay.io/centos/centos:stream9
ENV        container docker
ENV        TERM=linux

RUN        ln -sfv /usr/share/zoneinfo/America/Toronto /etc/localtime                                        && \
           dnf -y install yum-utils vim-enhanced rsync epel-release less git unzip procps crontabs diffutils && \
           dnf -y install tcpdump nc htop iproute nmap sudo openssh-server openssh-clients openvpn libreswan && \
           dnf -y install glibc-langpack-en iputils python3 python3-pip passwd iptables-nft sshpass          && \
           echo "root:secret" | chpasswd && sed -ri 's@^#(PermitRootLogin) .*@\1 yes@' /etc/ssh/sshd_config  && \
           echo alias vi='vim' >> /root/.bashrc_alias && printf "\nset paste\n" >> /etc/vimrc

#RUN          sed -ri 's@(\[Journal\])@\1\nCompact=no@' /etc/systemd/journald.conf

RUN        systemctl mask systemd-logind systemd-sysusers systemd-tmpfiles-setup dev-hugepages.mount systemd-tmpfiles-clean
#RUN        python3 -m pip install --upgrade pip && python3 -m pip install ansible pywinrm pynetbox pytz pyyaml pre-commit

#RUN        dnf -y module disable ruby && dnf -y module enable ruby:3.1 && dnf -y install ruby               && \
#           gem install sinatra webrick

RUN        echo 'if [ -f "/etc/bashrc.kali" ]; then . /etc/bashrc.kali; fi' >> /etc/bashrc
COPY       bashrc.kali /etc/profile.d/ctlabs-bashrc.sh
COPY       sshd-mgmt.service /etc/systemd/system/sshd-mgmt.service
RUN        systemctl enable sshd-mgmt.service && systemctl disable sshd.service

ENTRYPOINT ["/usr/lib/systemd/systemd"]
