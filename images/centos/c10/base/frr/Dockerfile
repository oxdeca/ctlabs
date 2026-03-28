FROM        ctlabs/c10/base:latest
ENV         container docker
ENV         TERM=linux

COPY        frr.service /etc/systemd/system/frr.service
RUN         yum -y install https://rpm.frrouting.org/repo/frr-stable-repo.el10.noarch.rpm && \
            yum -y install frr frr-pythontools ipvsadm && systemctl enable frr.service   && \
            systemctl enable sshd.service

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
