FROM        ctlabs/c9/base:latest
ENV         container docker
ENV         TERM=linux

RUN         dnf -y install centos-release-nfv-openvswitch && \
            dnf -y install openvswitch2.15                && \
            systemctl enable openvswitch.service          && \
            systemctl enable sshd.service

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
