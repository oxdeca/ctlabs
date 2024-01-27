#!/bin/bash

IMG_NAME=ctlabs/c8/frr
IMG_VERS=0.3

docker build --rm -t ${IMG_NAME}:${IMG_VERS} .
