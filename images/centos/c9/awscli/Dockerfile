FROM       quay.io/centos/centos:stream9
ENV        container docker
ENV        TERM=linux

RUN        yum -y install vim-enhanced rsync epel-release less git unzip procps sshpass          && \
           echo alias tf='/usr/bin/terraform' >> /root/.bashrc                                   && \
           echo alias packer='/usr/bin/packer' >> /root/.bashrc                                  && \
           echo alias gcloud='/usr/bin/gcloud' >> /root/.bashrc                                  && \
           echo alias aws='/usr/bin/awscli' >> /root/.bashrc

RUN        echo 'if [ -f "/etc/bashrc.kali" ]; then . /etc/bashrc.kali; fi' >> /etc/bashrc
COPY       bashrc.kali /etc/bashrc.kali

RUN        curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -Lo awscliv2.zip        && \
           unzip awscliv2.zip && ./aws/install -b /usr/bin -i /opt/aws-cli                       && \
           ln -sv /opt/aws-cli/v2/current/dist/aws /usr/bin/awscli  

RUN        dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo  && \
           dnf -y install terraform packer

#ENTRYPOINT ["/usr/lib/systemd/systemd"]

