#!/bin/bash

IMG_NAME=ctlabs/c8/base
IMG_VERS=0.3

docker build --rm -t ${IMG_NAME}:${IMG_VERS} .
