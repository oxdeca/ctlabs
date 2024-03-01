FROM       ctlabs/c9/base:latest
ENV        container docker
ENV        TERM=linux

RUN        yum -y install qemu-kvm

ENTRYPOINT ["/usr/lib/systemd/systemd"]
