FROM        ctlabs/c9/base:latest
ENV         container docker
ENV         TERM=linux

RUN         dnf config-manager --set-enabled crb                                            && \
            dnf -y install ninja-build autoconf automake libmpc-devel mpfr-devel gmp-devel  && \
            dnf -y install gawk bison flex pixman-devel make texinfo patchutils gcc gcc-c++ && \
            dnf -y install zlib-devel expat-devel glib2-devel bzip2

RUN         mkdir /root/xv6 && cd /root/xv6 && git clone https://github.com/qemu/qemu      && \
            cd qemu && git checkout v8.0.0 && ./configure --target-list=riscv64-softmmu    && \
            make -j $(nproc) && make install

RUN         cd /opt && curl -LO https://toolchains.bootlin.com/downloads/releases/toolchains/riscv64-lp64d/tarballs/riscv64-lp64d--glibc--stable-2022.08-1.tar.bz2 && \
            tar xvf riscv64-lp64d--glibc--stable-2022.08-1.tar.bz2 && ln -sv riscv64-lp64d--glibc--stable-2022.08-1 /opt/riscv64

RUN         cd /root/xv6 && git clone https://github.com/mit-pdos/xv6-riscv && cd xv6-riscv && \
            echo 'LD_LIBRARY_PATH=/opt/riscv64/lib64 PATH=$PATH:/opt/riscv64/bin/:/usr/local/bin TOOLPREFIX=/opt/riscv64/bin/riscv64-buildroot-linux-gnu- make qemu' > /root/xv6/xv6-riscv/start.sh && \
            chmod 0750 start.sh

COPY        proc.c.patch /root/xv6/xv6-riscv/kernel/
RUN         cd /root/xv6/xv6-riscv/kernel && patch proc.c proc.c.patch

WORKDIR     /root/xv6/xv6-riscv

ENTRYPOINT  ["/usr/lib/systemd/systemd"]
