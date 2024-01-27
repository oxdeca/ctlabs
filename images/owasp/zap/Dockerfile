FROM        ghcr.io/zaproxy/zaproxy
ENV         container docker 
USER        root 

RUN         apt update && apt install -y procps iproute2 iputils-ping iptables nmap lsof vim && \
            sed -ri 's@("maxClients" ).*@\1 : 3,@' /zap/webswing/webswing.config             && \
            sed -ri 's@("sessionMode" ).*@\1 : "CONTINUE_FOR_USER",@' /zap/webswing/webswing.config
USER        zap

ENTRYPOINT  ["/zap/zap-webswing.sh"]
