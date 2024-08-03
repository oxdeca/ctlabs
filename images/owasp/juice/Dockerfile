FROM        ctlabs/d12/base:latest

RUN         apt update && apt -y install nodejs npm 
RUN         cd /opt && curl -LO https://github.com/juice-shop/juice-shop/releases/download/v17.0.0/juice-shop-17.0.0_node18_linux_x64.tgz 
RUN         cd /opt && tar xvf juice-shop-17.0.0_node18_linux_x64.tgz && ln -sv /opt/juice-shop_17.0.0 /opt/juice-shop

COPY        juice-shop.service /etc/systemd/system/
RUN         systemctl enable juice-shop.service

ENTRYPOINT  ["/bin/systemd"]
