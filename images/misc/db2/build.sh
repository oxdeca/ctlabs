#!/bin/bash

IMG_NAME=ctlabs/misc/db2
IMG_VERS=0.2

docker build --rm -t ${IMG_NAME}:${IMG_VERS} -t ${IMG_NAME}:latest .
