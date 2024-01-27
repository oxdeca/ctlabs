FROM       ctlabs/c9/base:0.1
ENV        container docker
ENV        TERM=linux

RUN        echo alias tf='/usr/bin/terraform' >> /root/.bashrc                                                          && \
           echo alias packer='/usr/bin/packer' >> /root/.bashrc                                                         && \
           echo alias gcloud='/usr/bin/gcloud' >> /root/.bashrc

COPY       google-cloud-sdk.repo /etc/yum.repos.d/
RUN        dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo                         && \
           dnf -y install terraform packer google-cloud-cli kubectl

ENTRYPOINT ["/usr/lib/systemd/systemd"]

