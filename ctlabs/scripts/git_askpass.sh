#!/bin/sh
prompt="$1"
case "$prompt" in
  *[Uu]sername*) echo "$CTLABS_GIT_USERNAME" ;;
  *[Pp]assword*|*[Tt]oken*) echo "$CTLABS_GIT_PASSWORD" ;;
  *[Pp]assphrase*) echo "$CTLABS_GIT_PASSPHRASE" ;;
  *) echo "" ;;
esac
