FROM        ctlabs/qemu/base:latest

ENV         QEMU_IMG=windows-server-2025.qcow2
COPY        qemu_init.d/ /root/qemu_init.d/

ENTRYPOINT  ["/bin/systemd"]
