FROM       ctlabs/c9/base:latest
ENV        container docker
ENV        TERM=linux

RUN        systemctl enable sshd.service

RUN        python3 -m pip install --upgrade pip && python3 -m pip install ansible pywinrm pynetbox pytz pyyaml pre-commit hvac
RUN        dnf -y module disable ruby && dnf -y module enable ruby:3.1 && dnf -y install ruby && gem install sinatra webrick
RUN        dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo && dnf -y install terraform packer

ENTRYPOINT ["/usr/lib/systemd/systemd"]
