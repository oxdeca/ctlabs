FROM       dbeaver/cloudbeaver:latest

ENV        container docker

RUN        apt update && apt -y install iproute2 iptables tcpdump vim openssh-server && systemctl enable ssh
COPY       run-server.sh /opt/cloudbeaver/
RUN        echo "root:secret" | chpasswd && sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config
RUN        chmod 0755 /opt/cloudbeaver/run-server.sh

CMD         /opt/cloudbeaver/run-server.sh
ENTRYPOINT ["/usr/lib/systemd/systemd"]
