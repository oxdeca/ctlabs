FROM       docker.io/dbeaver/cloudbeaver:latest

ENV        container docker
ENV        TERM=linux

USER       root
RUN        apt update && apt -y install iproute2 iptables tcpdump vim openssh-server systemd less
COPY       --chmod=0755 run-server.sh /opt/cloudbeaver/
RUN        echo "root:secret" | chpasswd && sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config
RUN        chmod 0755 /opt/cloudbeaver/run-server.sh

COPY       sshd-mgmt.service     /etc/systemd/system/sshd-mgmt.service
COPY       cloudbeaver.service   /etc/systemd/system/cloudbeaver.service
COPY       cloudbeaver.sysconfig /etc/sysconfig/cloudbeaver
RUN        systemctl enable sshd-mgmt.service && systemctl enable cloudbeaver.service && systemctl disable ssh.service
RUN        echo 'd /run/sshd 0750 root root' > /usr/lib/tmpfiles.d/sshd-mgmt.conf

ENTRYPOINT ["/bin/systemd"]
