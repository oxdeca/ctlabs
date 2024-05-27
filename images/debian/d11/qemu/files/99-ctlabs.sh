#!/bin/bash

export TERM=linux

if [ -f /usr/bin/resize ]; then
  resize > /dev/null
fi

if [ -f /etc/bashrc.kali ]; then
  . /etc/bashrc.kali
fi