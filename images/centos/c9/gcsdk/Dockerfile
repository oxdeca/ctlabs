FROM       quay.io/centos/centos:stream9
ENV        container docker
ENV        TERM=linux

RUN        ln -sfv /usr/share/zoneinfo/America/Toronto /etc/localtime                               && \
           dnf -y install yum-utils vim-enhanced iproute epel-release less git unzip procps sshpass && \
           echo alias tf='/usr/bin/terraform' >> /root/.bashrc                                      && \
           echo alias packer='/usr/bin/packer' >> /root/.bashrc                                     && \
           echo alias gcloud='/usr/bin/gcloud' >> /root/.bashrc                                     && \
           printf "\nset paste\n" >> /etc/vimrc

RUN        echo 'if [ -f "/etc/bashrc.kali" ]; then . /etc/bashrc.kali; fi' >> /etc/bashrc
COPY       bashrc.kali /etc/bashrc.kali

COPY       google-cloud-sdk.repo /etc/yum.repos.d/
RUN        dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo    && \
           dnf -y install terraform packer google-cloud-cli kubectl

RUN        curl -L "https://github.com/Cyclenerd/google-cloud-pricing-cost-calculator/releases/latest/download/gcosts-linux-x86_64" \
           -o /usr/bin/gcosts && chmod 0755 /usr/bin/gcosts

RUN        mkdir -vp /etc/gcosts && \
           curl -L "https://github.com/Cyclenerd/google-cloud-pricing-cost-calculator/raw/master/pricing.yml" \
           -o /etc/gcosts/pricing.yml

#ENTRYPOINT ["/usr/lib/systemd/systemd"]
