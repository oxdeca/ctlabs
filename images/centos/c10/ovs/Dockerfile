FROM        ctlabs/c10/base:latest
ENV         container docker
ENV         TERM=linux

RUN         dnf -y install centos-release-nfv-openvswitch && \
            dnf -y install openvswitch3.5                 && \
            systemctl enable openvswitch.service          && \
            systemctl enable sshd.service

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
