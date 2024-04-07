#!/bin/bash

IMG_NAME=ctlabs/c9/xv6
IMG_VERS=0.1

docker build --rm -t ${IMG_NAME}:${IMG_VERS} -t ${IMG_NAME}:latest .
