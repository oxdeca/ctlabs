#!/bin/bash

IMG_NAME=ctlabs/c9/base
IMG_VERS=0.4

docker build --rm -t ${IMG_NAME}:${IMG_VERS} -t ${IMG_NAME}:latest .
