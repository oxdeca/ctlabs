#!/bin/bash

REALM=CTLABS.LOCAL
ADDOMAIN=CTLABS
DOMAIN=ctlabs.local
DNS=192.168.10.11

if [ ! -z ${1} ]; then
  /usr/bin/samba-tool domain provision --server-role=dc --use-rfc2307 --dns-backend=SAMBA_INTERNAL --realm=${REALM} --domain=${ADDOMAIN} --adminpass=secre!23
  echo -en "search ${DOMAIN}\nnameserver ${DNS}\nnameserver 127.0.0.11\noptions ndots:0\n" > /etc/resolv.conf
  cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

  #echo "If you want to use LDAP Authentication, run the following command:"
  #echo -en "/usr/bin/samba-tool forest directory_service dsheuristics 0000002 -H ldaps://localhost --simple-bind-dn='administrator@${DOMAIN}'"

  #samba -i
  systemctl disable --now smbd nmbd winbind
  systemctl unmask samba-ad-dc
  systemctl enable --now samba-ad-dc

  # To import sudoers schema
  # ldbmodify -H /var/lib/samba/private/sam.ldb attr.ldif  --option="dsdb:schema update allowed"=true
  # ldbmodify -H /var/lib/samba/private/sam.ldb class.ldif --option="dsdb:schema update allowed"=true

  # To disable strong ldap authentication
  # /etc/samba/smb.conf
  # [global]
  #   ldap server require strong auth = no
fi
