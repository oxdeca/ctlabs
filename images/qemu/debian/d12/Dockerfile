FROM        ctlabs/qemu/base:latest

ENV         QEMU_IMG=debian-12-nocloud-amd64.qcow2
COPY        debian-12-nocloud-amd64.qcow2 /media/

ENTRYPOINT  ["/bin/systemd"]
