FROM        docker.io/kalilinux/kali-rolling
ENV         container docker 

RUN         apt update && apt install -y systemd procps iproute2 iputils-ping nmap lsof vim dnsutils
RUN         systemctl mask systemd-logind dev-hugepages.mount

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
