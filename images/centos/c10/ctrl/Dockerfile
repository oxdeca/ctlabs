FROM       ctlabs/c10/base:latest
ENV        container docker
ENV        TERM=linux

RUN        systemctl enable sshd.service

RUN        python3 -m pip install --upgrade pip && python3 -m pip install ansible pywinrm pynetbox pytz pyyaml pre-commit hvac
RUN        dnf -y install dnsmasq && systemctl enable dnsmasq
RUN        dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo && dnf -y install terraform packer
RUN        dnf -y install https://github.com/open-policy-agent/conftest/releases/download/v0.70.0/conftest_0.70.0_Linux_x86_64.rpm && \
           pip install git+https://github.com/oxdeca/ctlabs-tools

ENTRYPOINT ["/usr/lib/systemd/systemd"]
