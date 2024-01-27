#!/bin/bash

IMG_NAME=ctlabs/c8/gcsdk
IMG_VERS=0.2

docker build --rm -t ${IMG_NAME}:${IMG_VERS} .
