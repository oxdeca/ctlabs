FROM        ctlabs/c8/base:latest
ENV         container docker
ENV         TERM=linux

COPY        frr.service /etc/systemd/system/frr.service
RUN         yum -y install https://rpm.frrouting.org/repo/frr-stable-repo.el8.noarch.rpm && \
            yum -y install frr frr-pythontools && systemctl enable frr.service

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
