#!/bin/bash

IMG_NAME=ctlabs/d11/qemu
IMG_VERS=0.1

docker build --rm -t ${IMG_NAME}:${IMG_VERS} -t ${IMG_NAME}:latest .