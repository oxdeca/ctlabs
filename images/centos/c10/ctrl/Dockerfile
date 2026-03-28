FROM       ctlabs/c10/base:latest
ENV        container docker
ENV        TERM=linux

RUN        systemctl enable sshd.service

RUN        python3 -m pip install --upgrade pip && python3 -m pip install ansible pywinrm pynetbox pytz pyyaml pre-commit hvac
RUN        dnf -y install ruby ruby-devel openssl-devel gcc make redhat-rpm-config && gem install sinatra puma webrick
RUN        dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo && dnf -y install terraform packer
RUN        dnf -y install https://github.com/open-policy-agent/conftest/releases/download/v0.63.0/conftest_0.63.0_linux_amd64.rpm && \
           pip install git+https://github.com/oxdeca/ctlabs-tools

ENTRYPOINT ["/usr/lib/systemd/systemd"]
