#!/bin/bash

export TERM=linux

if [ -f /usr/bin/resize ]; then
  resize > /dev/null
fi

if [ -f /etc/bashrc.kali ]; then
  . /etc/bashrc.kali
fi

if [ -f /usr/bin/k3s ]; then
  alias kubectl="/usr/bin/k3s kubectl"
  alias crictl="/usr/bin/k3s crictl"
  alias ctr="/usr/bin/k3s ctr"
  alias kc=kubectl
fi

if [ -f ~/virtenv ]; then
  alias pva=". ~/virtenv/bin/activate"
  alias pve="deactivate"
fi

alias vi="/usr/bin/vim"
