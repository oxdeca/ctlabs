#!/bin/bash

IMG_NAME=ctlabs/qemu/base
IMG_VERS=0.1.2

docker build --rm -t ${IMG_NAME}:${IMG_VERS} -t ${IMG_NAME}:latest .
