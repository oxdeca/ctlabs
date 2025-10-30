#!/bin/bash

labs=(
  'db/db01'
  'k3s/k3s01'
  'k3s/k3s02'
  'k8s/k8s01'
  'lpic2/lpic207'
  'lpic2/lpic208'
  'lpic2/lpic210'
  'lpic2/lpic212'
  'mon/mon01'
  'mon/mon02'
  'mon/mon03'
  'net/net01'
  'net/net02'
  'net/net03'
  'net/net04'
  'net/net05'
  'net/net09'
  'rke2/rke201'
  'rke2/rke202'
  'sec/sec01'
  'sec/sec02'
  'srv/srv01'
  'srv/srv02'
  'srv/srv03'
  'sys/sys01'
  'sys/sys02'
  'sys/sys03'
  'sys/sys04'
)

test_lab_config() {
  for lab in ${labs[@]}; do
    echo "Testing lab $lab ..."
    ./ctlabs.rb -c ../labs/${lab}.yml
    if [ $? -eq 0 ]; then
      echo "SUCCESS"
    else
      echo "ERROR"
    fi
    echo "-----------------------"
  done
}

test_lab_config
