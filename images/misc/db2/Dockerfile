FROM       icr.io/db2_community/db2

ENV        container docker
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
ENV        TERM=linux


RUN        dnf install -y iproute iptables systemd wireshark-cli tcpdump iputils htop            && \
           ln -sv /var/db2_setup/lib/setup_db2_instance.sh /root/db2_setup.sh                    && \
           echo "root:secret" | chpasswd                                                         && \
           sed -i 's@^PasswordAuthentication no@PasswordAuthentication yes@' /etc/ssh/sshd_config

RUN        echo 'if [ -f "/etc/bashrc.kali" ]; then . /etc/bashrc.kali; fi' >> /etc/bash.bashrc
COPY       bashrc.kali /etc/bashrc.kali
COPY       sshd-mgmt.service /etc/systemd/system/sshd-mgmt.service
RUN        systemctl enable sshd-mgmt.service && systemctl disable sshd.service

ENTRYPOINT /usr/lib/systemd/systemd
