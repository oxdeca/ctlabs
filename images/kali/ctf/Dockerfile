FROM        ctlabs/kali/base:latest
ENV         container docker 
ENV         DEBIAN_FRONTEND=noneinteractive
ENV         TERM=linux

RUN         apt install -y git curl bsdmainutils radare2 python3.12 python3.12-venv python3-pip && \
            git clone https://github.com/pwndbg/pwndbg && cd pwndbg && ./setup.sh && cd -       && \
            python3 -mpip install pwntools

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
