FROM       quay.io/centos/centos:stream9
ENV        container docker

RUN        yum -y install yum-utils vim-enhanced git rsync epel-release less git unzip procps iptables sshpass  && \
           yum -y install tcpdump nc htop iproute nmap sudo openssh-server openssh-clients diffutils crontabs   && \
           yum -y install glibc-langpack-ca glibc-langpack-en iputils ruby python39 python3-pip passwd          && \
           echo "root:secret" | chpasswd && sed -ri 's@^#(PermitRootLogin) .*@\1 yes@' /etc/ssh/sshd_config     && \
           echo alias vi='vim' >> /root/.bashrc_alias

RUN        systemctl mask systemd-logind systemd-sysusers systemd-tmpfiles-setup dev-hugepages.mount systemd-tmpfiles-clean

RUN        echo '. /etc/bashrc.kali' >> /etc/bashrc
COPY       bashrc.kali /etc/bashrc.kali

RUN        python3 -m pip install --upgrade pip && python3 -m pip install ansible

ENTRYPOINT ["/usr/lib/systemd/systemd"]
