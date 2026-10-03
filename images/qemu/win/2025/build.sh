#!/bin/bash
set -Eeuo pipefail

PACKER=/usr/bin/packer

IMG_VERS=0.1.1
QIMG_NAME=windows-server-2025.qcow2
BASE_IMAGES_DIR="${BASE_IMAGES_DIR:-/media/ctlabs-images/qemu}"
BUILD_DIR="${BUILD_DIR:-/media/nfs/ctlabs-win2025-build}"
VIRTIO_ISO="${BUILD_DIR}/virtio-win.iso"
VIRTIO_ISO_URL=https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
VIRTIO_DIR="${BUILD_DIR}/virtio-win-extracted"

VARIANT="${1:-core}"
if [ "${VARIANT}" == "clean" ]; then
  echo "--- removing Packer output directories under ${BUILD_DIR} ---"
  rm -rf "${BUILD_DIR}/output-win25-core" "${BUILD_DIR}/output-win25-dtop"
  exit 0
fi

case "${VARIANT}" in
  core)
    IMG_NAME=ctlabs/qemu/win25/core
    IMAGE_NAME="Windows Server 2025 SERVERSTANDARDCORE"
    DISK_SIZE="20480"
    OUTPUT_SUBDIR="output-win25-core"
    ;;
  dtop)
    IMG_NAME=ctlabs/qemu/win25/dtop
    IMAGE_NAME="Windows Server 2025 SERVERSTANDARD"
    DISK_SIZE="40960"
    OUTPUT_SUBDIR="output-win25-dtop"
    ;;
  *)
    echo "usage: $0 [core|dtop|clean]" >&2
    exit 1
    ;;
esac

OUTPUT_DIR="${BUILD_DIR}/${OUTPUT_SUBDIR}"

WIN_ISO_URL="${WIN_ISO_URL:-https://software-static.download.prss.microsoft.com/dbazure/998969d5-f34g-4e03-ac9d-1f9786c66749/26100.32230.260111-0550.lt_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso}"
WIN_ISO_CHECKSUM="${WIN_ISO_CHECKSUM:-sha256:7b052573ba7894c9924e3e87ba732ccd354d18cb75a883efa9b900ea125bfd51}"

build_qcow2() {
  mkdir -p "${BUILD_DIR}"

  rm -rf "${BUILD_DIR}/tmp"

  if [ ! -e "${VIRTIO_ISO}" ]; then
    curl -sLo "${VIRTIO_ISO}" ${VIRTIO_ISO_URL}
  fi

  if [ ! -d "${VIRTIO_DIR}" ]; then
    mkdir -p "${VIRTIO_DIR}" "${BUILD_DIR}/virtio-mnt"
    mount -o loop,ro "${VIRTIO_ISO}" "${BUILD_DIR}/virtio-mnt"
    cp -a "${BUILD_DIR}/virtio-mnt/." "${VIRTIO_DIR}/"
    umount "${BUILD_DIR}/virtio-mnt"
    rmdir "${BUILD_DIR}/virtio-mnt"
  fi

  (
    cd packer
    export PACKER_CACHE_DIR="${BUILD_DIR}/packer_cache"
    mkdir -p "${BUILD_DIR}/tmp"
    export TMPDIR="${BUILD_DIR}/tmp"
    ${PACKER} init win2025.pkr.hcl
    ${PACKER} build \
      -var "iso_url=${WIN_ISO_URL}" \
      -var "iso_checksum=${WIN_ISO_CHECKSUM}" \
      -var "virtio_drivers_dir=${VIRTIO_DIR}" \
      -var "output_dir=${OUTPUT_DIR}" \
      -var "image_name=${IMAGE_NAME}" \
      -var "disk_size=${DISK_SIZE}" \
      win2025.pkr.hcl
  )
}

build_qcow2

echo "--- qcow2 built (${VARIANT}), checking root disk before docker build (that step still writes to / regardless of BUILD_DIR) ---"
du -h "${OUTPUT_DIR}/${QIMG_NAME}"
df -h /

cp -a files/qemu_init.d "${OUTPUT_DIR}/"

# qcow2 must still be present in ${OUTPUT_DIR} here - the Dockerfile COPYs it
# in to make the image self-contained (embedded/default mode, see
# design-guide.md §2.7). Archiving to BASE_IMAGES_DIR happens AFTER the build.
docker build --rm -f Dockerfile -t ${IMG_NAME}:${IMG_VERS} -t ${IMG_NAME}:latest "${OUTPUT_DIR}"

echo "--- image built successfully, archiving base qcow2 for optional external/shared-base mode ---"
mkdir -p "${BASE_IMAGES_DIR}/win25-${VARIANT}"
mv "${OUTPUT_DIR}/${QIMG_NAME}" "${BASE_IMAGES_DIR}/win25-${VARIANT}/"

echo "--- removing Packer output dir ${OUTPUT_DIR} ---"
rm -rf "${OUTPUT_DIR}"
