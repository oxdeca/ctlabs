FROM       dbeaver/cloudbeaver:latest

ENV        container docker

RUN        apt update && apt -y install iproute2 iptables tcpdump vim
COPY       run-server.sh /opt/cloudbeaver/
RUN        chmod 0755 /opt/cloudbeaver/run-server.sh

ENTRYPOINT /opt/cloudbeaver/run-server.sh
