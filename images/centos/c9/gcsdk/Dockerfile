FROM       quay.io/centos/centos:stream9
ENV        container docker
ENV        TERM=linux

RUN        ln -sfv /usr/share/zoneinfo/America/Toronto /etc/localtime                               && \
           dnf -y install yum-utils vim-enhanced iproute epel-release less git unzip procps sshpass && \
           echo alias tf='/usr/bin/terraform' >> /root/.bashrc                                      && \
           echo alias packer='/usr/bin/packer' >> /root/.bashrc                                     && \
           echo alias gcloud='/usr/bin/gcloud' >> /root/.bashrc

RUN        echo 'if [ -f "/etc/bashrc.kali" ]; then . /etc/bashrc.kali; fi' >> /etc/bashrc
COPY       bashrc.kali /etc/bashrc.kali

COPY       google-cloud-sdk.repo /etc/yum.repos.d/
RUN        dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo    && \
           dnf -y install terraform packer google-cloud-cli kubectl

#ENTRYPOINT ["/usr/lib/systemd/systemd"]
