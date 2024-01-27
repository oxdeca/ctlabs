FROM       quay.io/centos/centos:stream8
ENV        container docker
ENV        TERM=linux

RUN        ln -sfv /usr/share/zoneinfo/America/Toronto /etc/localtime                                       && \
           dnf -y install yum-utils vim-enhanced git rsync epel-release less unzip procps crontabs          && \
           dnf -y install tcpdump nc htop iproute nmap sudo openssh-server openssh-clients diffutils        && \
           dnf -y install glibc-langpack-en iputils python39 passwd iptables sshpass openvpn libreswan      && \
           echo "root:secret" | chpasswd && sed -ri 's@^#(PermitRootLogin) .*@\1 yes@' /etc/ssh/sshd_config && \
           echo alias vi='vim' >> /root/.bashrc_alias                                                       && \
           systemctl disable NetworkManager

RUN        python3 -m pip install --upgrade pip && python3 -m pip install ansible pywinrm pynetbox pytz pyyaml \
           pre-commit

RUN        dnf -y module disable ruby && dnf -y module enable ruby:3.0 && dnf -y install ruby               && \
           gem install sinatra webrick

RUN        echo '. /etc/bashrc.kali' >> /etc/bashrc
COPY       bashrc.kali /etc/bashrc.kali

ENTRYPOINT ["/usr/lib/systemd/systemd"]
