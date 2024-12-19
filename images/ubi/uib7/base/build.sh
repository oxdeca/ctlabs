#!/bin/bash

IMG_NAME=ctlabs/ubi7/base
IMG_VERS=0.1

docker build --rm -t ${IMG_NAME}:${IMG_VERS} -t ${IMG_NAME}:latest .
