FROM       registry.redhat.io/ubi7
ENV        container docker
ENV        TERM=linux

RUN        ln -svf /usr/share/zoneinfo/America/Toronto /etc/localtime && echo "America/Toronto" > /etc/timezone && \
           yum -y install yum-utils vim-enhanced rsync rpm-build gcc make less git unzip procps                 && \
           yum -y install tcpdump nc htop iproute nmap sudo openssh-server openssh-client openvpn libreswan     && \
           yum -y install glibc-langpack-en iputils python3 python3-pip passwd sshpass diffutils                && \
           echo "root:secret" | chpasswd && sed -ri 's@^#(PermitRootLogin) .*@\1 yes@' /etc/ssh/sshd_config     && \
           echo alias vi='vim' >> /root/.bashrc_aliases && printf "\nset paste\n" >> /etc/vimrc

RUN        systemctl mask systemd-logind systemd-sysusers systemd-tmpfiles-setup dev-hugepages.mount systemd-tmpfiles-clean

COPY       bashrc.kali /etc/profile.d/ctlabs-bashrc.sh
COPY       sshd-mgmt.service /etc/systemd/system/sshd-mgmt.service
RUN        systemctl enable sshd-mgmt.service && systemctl disable sshd.service

ENTRYPOINT ["/usr/lib/systemd/systemd"]