FROM       quay.io/centos/centos:stream8 as tmp
COPY       v11.5.8_linuxx64_server_dec.tar.gz /opt/v11.5.8_linuxx64_server_dec.tar.gz
RUN        cd /opt && tar xf v11.5.8_linuxx64_server_dec.tar.gz && rm v11.5.8_linuxx64_server_dec.tar.gz


FROM       ctlabs/c8/base:latest
ENV        container docker

RUN        yum -y install libstdc++ pam gcc-c++ numactl-libs libaio libpam.so.0 file ksh 
COPY       --from=tmp /opt /opt
RUN        groupadd db2iadm1 && groupadd db2fsdm1 && groupadd dasadm1 && useradd -g db2iadm1 db2inst1     && \
           useradd -g db2fsdm1 db2fenc1 && useradd -g dasadm1  dasusr1

ENTRYPOINT ["/usr/lib/systemd/systemd"]
