FROM        ctlabs/qemu/base:latest

ENV         QEMU_IMG=windows-server-2022.qcow2
COPY        windows-server-2022.qcow2 /media/

ENTRYPOINT  ["/bin/systemd"]
