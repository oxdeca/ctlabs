#!/bin/bash

IMG_NAME=ctlabs/c9/frr
IMG_VERS=0.2

docker build --rm -t ${IMG_NAME}:${IMG_VERS} -t ${IMG_NAME}:latest .
