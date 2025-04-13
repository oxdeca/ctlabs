FROM        ctlabs/kali/base:latest
ENV         container docker 
ENV         DEBIAN_FRONTEND=noninteractive
ENV         TERM=linux

RUN         apt install -y git curl bsdmainutils radare2 python3-venv python3-pip python3-pwntools && \
            git clone https://github.com/pwndbg/pwndbg && cd pwndbg && ./setup.sh                  && \
            echo "source /pwndbg/gdbinit.py" >> /etc/gdb/gdbinit

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
