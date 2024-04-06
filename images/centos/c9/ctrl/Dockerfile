FROM        ctlabs/c9/base:latest
ENV         container docker
ENV         TERM=linux

RUN         systemctl enable sshd.service

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
