#!/bin/bash
set -Eeuo pipefail

# NOTE (2026-09-25): root disk on h3 is tight (~4.3G free after pruning
# ~1.7G of unused container image layers today -- was 2.6G, dropped there
# from Packer's own scratch/TMPDIR work landing on root, see below). Not
# enough for the eval ISO (~5G) + virtio-win.iso (~0.5G) + the qcow2 during
# install. BUILD_DIR below defaults to /media/nfs (added 2026-09-25, ~9G
# free) so Packer's downloads, cache, TMPDIR scratch, and output all land
# there instead. The one thing that CAN'T move: the final `docker build`
# layer commit still lands in container storage under /var/lib/containers
# on root -- see the size check before that step below. If it's tight,
# check `docker system df` and prune unused images first rather than
# guessing (confirm nothing "ACTIVE" gets touched before doing so).

IMG_NAME=ctlabs/qemu/win2022
IMG_VERS=0.1.0

# cracklib-packer (an unrelated password-dictionary tool) is symlinked at
# /usr/sbin/packer and shadows the real HashiCorp packer at /usr/bin/packer
# in PATH order on this box (and inside the ansible/ctrl container too) --
# confirmed 2026-09-25, `packer version` silently ran cracklib and printed
# "0 0" instead of erroring. Always call by absolute path here.
PACKER=/usr/bin/packer

QIMG_NAME=windows-server-2022.qcow2
BUILD_DIR="${BUILD_DIR:-/media/nfs/ctlabs-win2022-build}"
VIRTIO_ISO="${BUILD_DIR}/virtio-win.iso"
VIRTIO_ISO_URL=https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
VIRTIO_DIR="${BUILD_DIR}/virtio-win-extracted"

# Same artifact the eval center's HTML page hands you, just Microsoft's
# direct PRSS CDN link instead of the click-through form -- sourced from
# dockur/windows's src/define.sh (win2022-eval branch), which is how that
# project scripts this too. Microsoft rotates these paths occasionally
# (dockur keeps 5 fallback mirrors for exactly that reason); if this 404s,
# re-check https://github.com/dockur/windows/blob/master/src/define.sh for
# the current win2022-eval url/sum and override via env instead of editing
# here. 180-day evaluation build -- fine for lab use, not for anything
# long-lived.
WIN_ISO_URL="${WIN_ISO_URL:-https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso}"
WIN_ISO_CHECKSUM="${WIN_ISO_CHECKSUM:-sha256:3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325}"

build_qcow2() {
  mkdir -p "${BUILD_DIR}"

  # A killed/interrupted run (e.g. Ctrl-C or `kill -9` on a stuck install)
  # skips Packer's own cleanup, leaving generated CD/floppy scratch images
  # behind under TMPDIR. Bit us 2026-09-26: grew to 8.8G across a few killed
  # attempts and nearly ate all of BUILD_DIR's free space. TMPDIR is pure
  # scratch, regenerated every run -- always safe to clear first.
  rm -rf "${BUILD_DIR}/tmp"

  if [ ! -e "${VIRTIO_ISO}" ]; then
    curl -sLo "${VIRTIO_ISO}" ${VIRTIO_ISO_URL}
  fi

  # cd_files (packer's supported way to attach extra content) bundles loose
  # files/dirs into a new CD -- it can't attach a pre-built .iso directly --
  # so extract virtio-win.iso once via loopback mount rather than pointing
  # Packer at the .iso itself.
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
    # Packer stages scratch work (e.g. building the cd_files ISO from the
    # 1.5G extracted virtio driver tree) under $TMPDIR/os.TempDir(), which
    # defaults to /tmp -- on root, not BUILD_DIR. Bit us 2026-09-25:
    # "genisoimage: No space left on device" mid-build, root dropped from
    # 7.4G to 2.6G free with no obvious cause until this was found.
    mkdir -p "${BUILD_DIR}/tmp"
    export TMPDIR="${BUILD_DIR}/tmp"
    ${PACKER} init win2022.pkr.hcl
    ${PACKER} build \
      -var "iso_url=${WIN_ISO_URL}" \
      -var "iso_checksum=${WIN_ISO_CHECKSUM}" \
      -var "virtio_drivers_dir=${VIRTIO_DIR}" \
      -var "output_dir=${BUILD_DIR}/output-win2022" \
      win2022.pkr.hcl
  )
}

build_qcow2

echo "--- qcow2 built, checking root disk before docker build (that step still writes to / regardless of BUILD_DIR) ---"
du -h "${BUILD_DIR}/output-win2022/${QIMG_NAME}"
df -h /

# Context = the NFS output dir (has the qcow2); -f points back at our
# Dockerfile in the repo. Avoids an extra copy of the qcow2 onto root just
# to satisfy `docker build .`'s context-must-contain-the-file rule.
docker build --rm -f Dockerfile -t ${IMG_NAME}:${IMG_VERS} -t ${IMG_NAME}:latest "${BUILD_DIR}/output-win2022"
