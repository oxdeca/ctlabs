#!/bin/bash

# -----------------------------------------------------------------------------
# File        : ctlabs-terraform/lpic2/ppvm.sh
# Description : Post-Provisioning Script for centos 9 vm's
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# COMMANDS
# -----------------------------------------------------------------------------
#
CP=/usr/bin/cp
LN=/usr/bin/ln
MV=/usr/bin/mv
GEM=/usr/bin/gem
GIT=/usr/bin/git
PIP=/usr/bin/pip3
DNF=/usr/bin/dnf
SED=/usr/bin/sed
BASH=/bin/bash
ECHO=/usr/bin/echo
CURL=/usr/bin/curl
SCTL=/usr/bin/systemctl
MAKE=/usr/bin/make
CHMOD=/usr/bin/chmod
MKDIR=/usr/bin/mkdir
PYTHON=/usr/bin/python3
DOCKER=/usr/bin/docker
TOUCH=/usr/bin/touch
BASE64=/usr/bin/base64
OPENSSL=/usr/bin/openssl
SYSTEMCTL=/usr/bin/systemctl


# -----------------------------------------------------------------------------
# GLOBALS
# -----------------------------------------------------------------------------
#
LAB="lpic2.c9"
PKGS=(
  'lvm2'
  'tmux'
  'vim'
  'git'
  'graphviz'
  'epel-release'
  'htop'
  'ruby'
  'irb'
  'podman-docker'
  'wireshark-cli'
  'tcpdump'
  'nc'
  'perf'
  'bpftrace'
  "kernel-modules-extra-$(uname -r)"
  'python3-pip'
  'ipvsadm'
  'qemu-img'
  'cloud-utils-growpart'
  'make'
  'gcc'
  'g++'
  'ruby-devel'
  'redhat-rpm-config'
)

GEMS=(
  'webrick'
  'sinatra'
  'rackup'
  'faye-websocket'
  'puma'
)

CTIMGS=(
  '/root/ctlabs/images/centos/c9'
  '/root/ctlabs/images/debian/d12'
  '/root/ctlabs/images/kali'
  '/root/ctlabs/images/parrot'
)

BASHRC_KALI='
IyB+Ly5iYXNocmM6IGV4ZWN1dGVkIGJ5IGJhc2goMSkgZm9yIG5vbi1sb2dpbiBz
aGVsbHMuCiMgc2VlIC91c3Ivc2hhcmUvZG9jL2Jhc2gvZXhhbXBsZXMvc3RhcnR1
cC1maWxlcyAoaW4gdGhlIHBhY2thZ2UgYmFzaC1kb2MpCiMgZm9yIGV4YW1wbGVz
CgojIElmIG5vdCBydW5uaW5nIGludGVyYWN0aXZlbHksIGRvbid0IGRvIGFueXRo
aW5nCmNhc2UgJC0gaW4KICAgICppKikgOzsKICAgICAgKikgcmV0dXJuOzsKZXNh
YwoKIyBkb24ndCBwdXQgZHVwbGljYXRlIGxpbmVzIG9yIGxpbmVzIHN0YXJ0aW5n
IHdpdGggc3BhY2UgaW4gdGhlIGhpc3RvcnkuCiMgU2VlIGJhc2goMSkgZm9yIG1v
cmUgb3B0aW9ucwpISVNUQ09OVFJPTD1pZ25vcmVib3RoCgojIGFwcGVuZCB0byB0
aGUgaGlzdG9yeSBmaWxlLCBkb24ndCBvdmVyd3JpdGUgaXQKc2hvcHQgLXMgaGlz
dGFwcGVuZAoKIyBmb3Igc2V0dGluZyBoaXN0b3J5IGxlbmd0aCBzZWUgSElTVFNJ
WkUgYW5kIEhJU1RGSUxFU0laRSBpbiBiYXNoKDEpCkhJU1RTSVpFPTEwMDAKSElT
VEZJTEVTSVpFPTIwMDAKCiMgY2hlY2sgdGhlIHdpbmRvdyBzaXplIGFmdGVyIGVh
Y2ggY29tbWFuZCBhbmQsIGlmIG5lY2Vzc2FyeSwKIyB1cGRhdGUgdGhlIHZhbHVl
cyBvZiBMSU5FUyBhbmQgQ09MVU1OUy4Kc2hvcHQgLXMgY2hlY2t3aW5zaXplCgoj
IElmIHNldCwgdGhlIHBhdHRlcm4gIioqIiB1c2VkIGluIGEgcGF0aG5hbWUgZXhw
YW5zaW9uIGNvbnRleHQgd2lsbAojIG1hdGNoIGFsbCBmaWxlcyBhbmQgemVybyBv
ciBtb3JlIGRpcmVjdG9yaWVzIGFuZCBzdWJkaXJlY3Rvcmllcy4KI3Nob3B0IC1z
IGdsb2JzdGFyCgojIG1ha2UgbGVzcyBtb3JlIGZyaWVuZGx5IGZvciBub24tdGV4
dCBpbnB1dCBmaWxlcywgc2VlIGxlc3NwaXBlKDEpCiNbIC14IC91c3IvYmluL2xl
c3NwaXBlIF0gJiYgZXZhbCAiJChTSEVMTD0vYmluL3NoIGxlc3NwaXBlKSIKCiMg
c2V0IHZhcmlhYmxlIGlkZW50aWZ5aW5nIHRoZSBjaHJvb3QgeW91IHdvcmsgaW4g
KHVzZWQgaW4gdGhlIHByb21wdCBiZWxvdykKaWYgWyAteiAiJHtkZWJpYW5fY2hy
b290Oi19IiBdICYmIFsgLXIgL2V0Yy9kZWJpYW5fY2hyb290IF07IHRoZW4KICAg
IGRlYmlhbl9jaHJvb3Q9JChjYXQgL2V0Yy9kZWJpYW5fY2hyb290KQpmaQoKIyBz
ZXQgYSBmYW5jeSBwcm9tcHQgKG5vbi1jb2xvciwgdW5sZXNzIHdlIGtub3cgd2Ug
IndhbnQiIGNvbG9yKQpjYXNlICIkVEVSTSIgaW4KICAgIHh0ZXJtLWNvbG9yfCot
MjU2Y29sb3IpIGNvbG9yX3Byb21wdD15ZXM7Owplc2FjCgojIHVuY29tbWVudCBm
b3IgYSBjb2xvcmVkIHByb21wdCwgaWYgdGhlIHRlcm1pbmFsIGhhcyB0aGUgY2Fw
YWJpbGl0eTsgdHVybmVkCiMgb2ZmIGJ5IGRlZmF1bHQgdG8gbm90IGRpc3RyYWN0
IHRoZSB1c2VyOiB0aGUgZm9jdXMgaW4gYSB0ZXJtaW5hbCB3aW5kb3cKIyBzaG91
bGQgYmUgb24gdGhlIG91dHB1dCBvZiBjb21tYW5kcywgbm90IG9uIHRoZSBwcm9t
cHQKZm9yY2VfY29sb3JfcHJvbXB0PXllcwoKaWYgWyAtbiAiJGZvcmNlX2NvbG9y
X3Byb21wdCIgXTsgdGhlbgogICAgaWYgWyAteCAvdXNyL2Jpbi90cHV0IF0gJiYg
dHB1dCBzZXRhZiAxID4mL2Rldi9udWxsOyB0aGVuCiAgICAgICAgIyBXZSBoYXZl
IGNvbG9yIHN1cHBvcnQ7IGFzc3VtZSBpdCdzIGNvbXBsaWFudCB3aXRoIEVjbWEt
NDgKICAgICAgICAjIChJU08vSUVDLTY0MjkpLiAoTGFjayBvZiBzdWNoIHN1cHBv
cnQgaXMgZXh0cmVtZWx5IHJhcmUsIGFuZCBzdWNoCiAgICAgICAgIyBhIGNhc2Ug
d291bGQgdGVuZCB0byBzdXBwb3J0IHNldGYgcmF0aGVyIHRoYW4gc2V0YWYuKQog
ICAgICAgIGNvbG9yX3Byb21wdD15ZXMKICAgIGVsc2UKICAgICAgICBjb2xvcl9w
cm9tcHQ9CiAgICBmaQpmaQoKIyBUaGUgZm9sbG93aW5nIGJsb2NrIGlzIHN1cnJv
dW5kZWQgYnkgdHdvIGRlbGltaXRlcnMuCiMgVGhlc2UgZGVsaW1pdGVycyBtdXN0
IG5vdCBiZSBtb2RpZmllZC4gVGhhbmtzLgojIFNUQVJUIEtBTEkgQ09ORklHIFZB
UklBQkxFUwpQUk9NUFRfQUxURVJOQVRJVkU9b25lbGluZSAjIHR3b2xpbmUKTkVX
TElORV9CRUZPUkVfUFJPTVBUPW5vICAgIyB5ZXMKIyBTVE9QIEtBTEkgQ09ORklH
IFZBUklBQkxFUwoKaWYgWyAiJGNvbG9yX3Byb21wdCIgPSB5ZXMgXTsgdGhlbgog
ICAgIyBvdmVycmlkZSBkZWZhdWx0IHZpcnR1YWxlbnYgaW5kaWNhdG9yIGluIHBy
b21wdAogICAgVklSVFVBTF9FTlZfRElTQUJMRV9QUk9NUFQ9MQoKICAgIHByb21w
dF9jb2xvcj0nXFtcMDMzWzszMm1cXScKICAgIGluZm9fY29sb3I9J1xbXDAzM1sx
OzM0bVxdJwogICAgcHJvbXB0X3N5bWJvbD3jib8KICAgIGlmIFsgIiRFVUlEIiAt
ZXEgMCBdOyB0aGVuICMgQ2hhbmdlIHByb21wdCBjb2xvcnMgZm9yIHJvb3QgdXNl
cgogICAgICAgIHByb21wdF9jb2xvcj0nXFtcMDMzWzs5NG1cXScKICAgICAgICBp
bmZvX2NvbG9yPSdcW1wwMzNbMTszMW1cXScKICAgICAgICAjIFNrdWxsIGVtb2pp
IGZvciByb290IHRlcm1pbmFsCiAgICAgICAgI3Byb21wdF9zeW1ib2w98J+SgAog
ICAgZmkKICAgIGNhc2UgIiRQUk9NUFRfQUxURVJOQVRJVkUiIGluCiAgICAgICAg
dHdvbGluZSkKICAgICAgICAgICAgUFMxPSRwcm9tcHRfY29sb3In4pSM4pSA4pSA
JHtkZWJpYW5fY2hyb290OisoJGRlYmlhbl9jaHJvb3Qp4pSA4pSAfSR7VklSVFVB
TF9FTlY6KyhcW1wwMzNbMDsxbVxdJChiYXNlbmFtZSAkVklSVFVBTF9FTlYpJyRw
cm9tcHRfY29sb3InKX0oJyRpbmZvX2NvbG9yJ1x1JyRwcm9tcHRfc3ltYm9sJ1xo
JyRwcm9tcHRfY29sb3InKS1bXFtcMDMzWzA7MW1cXVx3JyRwcm9tcHRfY29sb3In
XVxuJyRwcm9tcHRfY29sb3In4pSU4pSAJyRpbmZvX2NvbG9yJ1wkXFtcMDMzWzBt
XF0gJzs7CiAgICAgICAgb25lbGluZSkKICAgICAgICAgICAgUFMxPScke1ZJUlRV
QUxfRU5WOisoJChiYXNlbmFtZSAkVklSVFVBTF9FTlYpKSB9JHtkZWJpYW5fY2hy
b290OisoJGRlYmlhbl9jaHJvb3QpfSckaW5mb19jb2xvcidcdUBcaFxbXDAzM1sw
MG1cXTonJHByb21wdF9jb2xvcidcW1wwMzNbMDFtXF1cd1xbXDAzM1swMG1cXVwk
ICc7OwogICAgICAgIGJhY2t0cmFjaykKICAgICAgICAgICAgUFMxPScke1ZJUlRV
QUxfRU5WOisoJChiYXNlbmFtZSAkVklSVFVBTF9FTlYpKSB9JHtkZWJpYW5fY2hy
b290OisoJGRlYmlhbl9jaHJvb3QpfVxbXDAzM1swMTszMW1cXVx1QFxoXFtcMDMz
WzAwbVxdOlxbXDAzM1swMTszNG1cXVx3XFtcMDMzWzAwbVxdXCQgJzs7CiAgICBl
c2FjCiAgICB1bnNldCBwcm9tcHRfY29sb3IKICAgIHVuc2V0IGluZm9fY29sb3IK
ICAgIHVuc2V0IHByb21wdF9zeW1ib2wKZWxzZQogICAgUFMxPScke2RlYmlhbl9j
aHJvb3Q6KygkZGViaWFuX2Nocm9vdCl9XHVAXGg6XHdcJCAnCmZpCnVuc2V0IGNv
bG9yX3Byb21wdCBmb3JjZV9jb2xvcl9wcm9tcHQKCiMgSWYgdGhpcyBpcyBhbiB4
dGVybSBzZXQgdGhlIHRpdGxlIHRvIHVzZXJAaG9zdDpkaXIKY2FzZSAiJFRFUk0i
IGluCnh0ZXJtKnxyeHZ0KnxFdGVybXxhdGVybXxrdGVybXxnbm9tZSp8YWxhY3Jp
dHR5KQogICAgUFMxPSJcW1xlXTA7JHtkZWJpYW5fY2hyb290OisoJGRlYmlhbl9j
aHJvb3QpfVx1QFxoOiBcd1xhXF0kUFMxIgogICAgOzsKKikKICAgIDs7CmVzYWMK
ClsgIiRORVdMSU5FX0JFRk9SRV9QUk9NUFQiID0geWVzIF0gJiYgUFJPTVBUX0NP
TU1BTkQ9IlBST01QVF9DT01NQU5EPWVjaG8iCgojIGVuYWJsZSBjb2xvciBzdXBw
b3J0IG9mIGxzLCBsZXNzIGFuZCBtYW4sIGFuZCBhbHNvIGFkZCBoYW5keSBhbGlh
c2VzCmlmIFsgLXggL3Vzci9iaW4vZGlyY29sb3JzIF07IHRoZW4KICAgIHRlc3Qg
LXIgfi8uZGlyY29sb3JzICYmIGV2YWwgIiQoZGlyY29sb3JzIC1iIH4vLmRpcmNv
bG9ycykiIHx8IGV2YWwgIiQoZGlyY29sb3JzIC1iKSIKICAgIGV4cG9ydCBMU19D
T0xPUlM9IiRMU19DT0xPUlM6b3c9MzA7NDQ6IiAjIGZpeCBscyBjb2xvciBmb3Ig
Zm9sZGVycyB3aXRoIDc3NyBwZXJtaXNzaW9ucwoKICAgIGFsaWFzIGxzPSdscyAt
LWNvbG9yPWF1dG8nCiAgICAjYWxpYXMgZGlyPSdkaXIgLS1jb2xvcj1hdXRvJwog
ICAgI2FsaWFzIHZkaXI9J3ZkaXIgLS1jb2xvcj1hdXRvJwoKICAgIGFsaWFzIGdy
ZXA9J2dyZXAgLS1jb2xvcj1hdXRvJwogICAgYWxpYXMgZmdyZXA9J2ZncmVwIC0t
Y29sb3I9YXV0bycKICAgIGFsaWFzIGVncmVwPSdlZ3JlcCAtLWNvbG9yPWF1dG8n
CiAgICBhbGlhcyBkaWZmPSdkaWZmIC0tY29sb3I9YXV0bycKICAgIGFsaWFzIGlw
PSdpcCAtLWNvbG9yPWF1dG8nCgogICAgZXhwb3J0IExFU1NfVEVSTUNBUF9tYj0k
J1xFWzE7MzFtJyAgICAgIyBiZWdpbiBibGluawogICAgZXhwb3J0IExFU1NfVEVS
TUNBUF9tZD0kJ1xFWzE7MzZtJyAgICAgIyBiZWdpbiBib2xkCiAgICBleHBvcnQg
TEVTU19URVJNQ0FQX21lPSQnXEVbMG0nICAgICAgICAjIHJlc2V0IGJvbGQvYmxp
bmsKICAgIGV4cG9ydCBMRVNTX1RFUk1DQVBfc289JCdcRVswMTszM20nICAgICMg
YmVnaW4gcmV2ZXJzZSB2aWRlbwogICAgZXhwb3J0IExFU1NfVEVSTUNBUF9zZT0k
J1xFWzBtJyAgICAgICAgIyByZXNldCByZXZlcnNlIHZpZGVvCiAgICBleHBvcnQg
TEVTU19URVJNQ0FQX3VzPSQnXEVbMTszMm0nICAgICAjIGJlZ2luIHVuZGVybGlu
ZQogICAgZXhwb3J0IExFU1NfVEVSTUNBUF91ZT0kJ1xFWzBtJyAgICAgICAgIyBy
ZXNldCB1bmRlcmxpbmUKZmkKCiMgY29sb3JlZCBHQ0Mgd2FybmluZ3MgYW5kIGVy
cm9ycwojZXhwb3J0IEdDQ19DT0xPUlM9J2Vycm9yPTAxOzMxOndhcm5pbmc9MDE7
MzU6bm90ZT0wMTszNjpjYXJldD0wMTszMjpsb2N1cz0wMTpxdW90ZT0wMScKCiMg
c29tZSBtb3JlIGxzIGFsaWFzZXMKYWxpYXMgbGw9J2xzIC1sJwphbGlhcyBsYT0n
bHMgLUEnCmFsaWFzIGw9J2xzIC1DRicKCiMgQWxpYXMgZGVmaW5pdGlvbnMuCiMg
WW91IG1heSB3YW50IHRvIHB1dCBhbGwgeW91ciBhZGRpdGlvbnMgaW50byBhIHNl
cGFyYXRlIGZpbGUgbGlrZQojIH4vLmJhc2hfYWxpYXNlcywgaW5zdGVhZCBvZiBh
ZGRpbmcgdGhlbSBoZXJlIGRpcmVjdGx5LgojIFNlZSAvdXNyL3NoYXJlL2RvYy9i
YXNoLWRvYy9leGFtcGxlcyBpbiB0aGUgYmFzaC1kb2MgcGFja2FnZS4KCmlmIFsg
LWYgfi8uYmFzaF9hbGlhc2VzIF07IHRoZW4KICAgIC4gfi8uYmFzaF9hbGlhc2Vz
CmZpCgojIGVuYWJsZSBwcm9ncmFtbWFibGUgY29tcGxldGlvbiBmZWF0dXJlcyAo
eW91IGRvbid0IG5lZWQgdG8gZW5hYmxlCiMgdGhpcywgaWYgaXQncyBhbHJlYWR5
IGVuYWJsZWQgaW4gL2V0Yy9iYXNoLmJhc2hyYyBhbmQgL2V0Yy9wcm9maWxlCiMg
c291cmNlcyAvZXRjL2Jhc2guYmFzaHJjKS4KaWYgISBzaG9wdCAtb3EgcG9zaXg7
IHRoZW4KICBpZiBbIC1mIC91c3Ivc2hhcmUvYmFzaC1jb21wbGV0aW9uL2Jhc2hf
Y29tcGxldGlvbiBdOyB0aGVuCiAgICAuIC91c3Ivc2hhcmUvYmFzaC1jb21wbGV0
aW9uL2Jhc2hfY29tcGxldGlvbgogIGVsaWYgWyAtZiAvZXRjL2Jhc2hfY29tcGxl
dGlvbiBdOyB0aGVuCiAgICAuIC9ldGMvYmFzaF9jb21wbGV0aW9uCiAgZmkKZmkK
Cg=='

# -----------------------------------------------------------------------------
# FUNCTIONS
# -----------------------------------------------------------------------------
#
os_update() {
  ${DNF} -y update
}

packages() {
  for p in "${PKGS[@]}"; do
    ${DNF} -y install "${p}"
  done

  ${TOUCH} /etc/containers/nodocker
  #${DNF} -y install ${PKGS[*]}
  ${GEM} install ${GEMS[*]}
}

config() {
  ${MKDIR} -vp /etc/ansible/facts.d

  ${ECHO} '
  alias vi="/usr/bin/vim"
  alias pva=". ~/virtenv/bin/activate"
  alias pve="deactivate"
  alias kubectl="/usr/bin/k3s kubectl"
  alias crictl="/usr/bin/k3s crictl"
  alias ctr="/usr/bin/k3s ctr"
  alias kc=kubectl

  function enter() {
    docker exec -it -w ~/ ${1} bash
  }
  ' > /etc/profile.d/bashrc_ctlabs.sh

  ${ECHO} -en $BASHRC_KALI | ${SED} 's@ @\n@g' | ${BASE64} -d > /etc/profile.d/bashrc_kali.sh
  ${ECHO} "set paste" >> /etc/vimrc
}

services() {
  ${SCTL} disable --now firewalld.service
}


tmux() {
cat > /root/.tmux.conf << EOF
unbind C-b
set -g prefix C-a
set -g default-terminal "screen-256color"
bind-key C-a last-window
bind a send-prefix
set-option -g allow-rename off
set -g base-index 1
set-window-option -g mode-keys vi
setw -g monitor-activity on
set -g mouse on
bind | split-window -h
bind - split-window -v
unbind '"'
unbind %
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# vim copy mode
bind P paste-buffer
bind-key -T copy-mode-vi v send-keys -X begin-selection
bind-key -T copy-mode-vi y send-keys -X copy-selection
bind-key -T copy-mode-vi r send-keys -X rectangle-toggle
# Update default binding of 'Enter' to also use copy-pipe
unbind -T copy-mode-vi Enter
bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel "xclip -selection c"
bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -in -selection clipboard"
bind-key -T prefix m set -g mouse\; display 'Mouse: #{?mouse,ON,OFF}'

# statusbar
set -g status-position bottom
set -g status-justify left

# split the window evenly into 8 parts
new-session -d -s ctlabs
split-window -v
split-window -h -t 1
split-window -h -t 0

split-window -v -t 3
resize-pane  -U 50
split-window -v -t 2
resize-pane  -U 50
split-window -v -t 1
resize-pane  -U 50
split-window -v -t 0
resize-pane  -U 50

EOF

}

ansible() {
  ${PYTHON} -mpip install pip --upgrade
  ${PYTHON} -m venv ~/virtenv
  . ~/virtenv/bin/activate
  python -mpip install pip --upgrade
  python -mpip install ansible
}

clone_repo() {
  cd /root/
  ${GIT} clone https://github.com/oxdeca/ctlabs.git
  ${GIT} clone https://github.com/oxdeca/ctlabs-ansible.git

  ${MKDIR} -vp /srv/ctlabs-server/public/
  ${LN} -sv /root/ctlabs/ctlabs/js/  /srv/ctlabs-server/public/js
  ${LN} -sv /root/ctlabs/ctlabs/css/ /srv/ctlabs-server/public/css
  ${CP} ctlabs/ctlabs/ctlabs-server.service /etc/systemd/system/
  ${SYSTEMCTL} enable --now ctlabs-server.service
}

ctimages() {
  for d in "${CTIMGS[@]}"; do
    cd ${d}
    ${MAKE}
  done
}

selinux() {
  setenforce permissive
  ${SED} -ri 's@(SELINUX=).*@\1permissive@' /etc/selinux/config
}

set_password() {
  SUGGESTED_PASS=$(${OPENSSL} rand -base64 12)
  echo "-----------------------------------------------------------------------------"
  echo "WEB UI SECURITY"
  echo "-----------------------------------------------------------------------------"
  echo "Suggested secure password: ${SUGGESTED_PASS}"
  read -p "Enter password for 'ctlabs' user (leave empty to use suggested): " PASS
  PASS=${PASS:-${SUGGESTED_PASS}}
  echo "Password set to: ${PASS}"
  
  SALT="GGV78Ib5vVRkTc"
  # Generate SHA-512 hash
  HASH=$(${OPENSSL} passwd -6 -salt "${SALT}" "${PASS}")
  
  # Replace in base_controller.rb
  # Using @ as delimiter for sed to avoid issues with / in the hash
  ${SED} -i "s@user == 'ctlabs' && pass.crypt(\"\$6\$\#{salt}\$\") == \".*\"@user == 'ctlabs' && pass.crypt(\"\$6\$\#{salt}\$\") == \"${HASH}\"@" /root/ctlabs/ctlabs/controllers/base_controller.rb
  echo "-----------------------------------------------------------------------------"
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
#
selinux
config
tmux
os_update
packages
services

clone_repo
set_password
ctimages