FROM       icr.io/db2_community/db2

ENV        container docker
ENV        TERM=linux

ENV        LICENSE=accept
ENV        DB2INSTANCE=db2inst1
ENV        DB2INST1_PASSWORD=secret
ENV        DBNAME=testdb
ENV        BLU=false
ENV        ENABLE_ORACLE_COMPATIBILITY=false
ENV        UPDATEAVAIL=NO
ENV        TO_CREATE_SAMPLEDB=true
ENV        REPODB=false
ENV        IS_OSXFS=false
ENV        PERSISTENT_HOME=true
ENV        HADR_ENABLED=false
ENV        ETCD_ENDPOINT=
ENV        ETCD_USERNAME=
ENV        ETCD_PASSWORD=

RUN        dnf install -y iproute iptables systemd tcpdump iputils htop             && \
           ln -sv /var/db2_setup/lib/setup_db2_instance.sh /root/db2_setup.sh       && \
           echo 'export $(cat /proc/1/environ | tr '\0' '\n' | grep QEMU)' 

COPY       bashrc.kali /etc/profile.d/kali.sh
COPY       sshd-mgmt.service   /etc/systemd/system/sshd-mgmt.service
COPY       db2-setup.service   /etc/systemd/system/db2-setup.service
COPY       db2-setup.sysconfig /etc/sysconfig/db2-setup
RUN        systemctl enable sshd-mgmt.service && systemctl enable db2-setup.service && \
           systemctl disable sshd.service

RUN        echo "root:secret" | chpasswd                                            && \
           sed -ri "s@^(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config

ENTRYPOINT ["/usr/lib/systemd/systemd"]
