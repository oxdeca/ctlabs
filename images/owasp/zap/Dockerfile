FROM        ghcr.io/zaproxy/zaproxy
ENV         container docker
USER        root

RUN         apt update && apt install -y procps iproute2 iputils-ping iptables nmap lsof vim openssh-server && \
            sed -ri 's@("maxClients" ).*@\1 : 3,@' /zap/webswing/webswing.config                            && \
            sed -ri 's@("sessionMode" ).*@\1 : "CONTINUE_FOR_USER",@' /zap/webswing/webswing.config         && \
            echo "root:secret" | chpasswd && sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config


RUN         echo 'if [ -f "/etc/bashrc.kali" ]; then . /etc/bashrc.kali; fi' > /etc/profile.d/ctlabs.sh     && \
            echo 'if [ -f "/etc/profile" ]; then . /etc/profile; fi' >> ~/.bashrc
COPY        bashrc.kali /etc/bashrc.kali
COPY        sshd-mgmt.service /etc/systemd/system/sshd-mgmt.service
RUN         systemctl enable sshd-mgmt.service && systemctl disable ssh.service
COPY        zap.service /etc/systemd/system/zap.service
RUN         systemctl enable zap.service 

ENTRYPOINT  ["/bin/systemd"]
