FROM debian:bullseye

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt -y install attr acl krb5-config krb5-user ldap-utils libnss-winbind libpam-krb5 libpam-winbind samba winbind vim less systemd && \
    apt -y install iproute2 tcpdump netcat htop iputils-ping iptables syslog-ng openssh-server && \
    echo "root:secret" | chpasswd && rm -f /etc/samba/smb.conf && sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config

COPY setup_adc.sh /root/setup_adc.sh
RUN  chmod 0755 /root/setup_adc.sh 

#RUN samba-tool domain provision --server-role=dc --use-rfc2307 --dns-backend=SAMBA_INTERNAL --realm=SALTNET.OXDECA.COM --domain=SALTNET --adminpass=secre!23
#RUN echo -en "search saltnet.oxdeca.com\nnameserver 172.30.8.222\nnameserver 127.0.0.11\noptions ndots:0\n" > /etc/resolv.conf
#RUN cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

ENTRYPOINT  ["/bin/systemd"]
