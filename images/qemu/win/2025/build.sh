#!/bin/bash
set -Eeuo pipefail

# DRAFT / UNVALIDATED (2026-09-27) -- copied from the sibling
# images/qemu/win/2022/build.sh, which took a multi-day debugging saga to
# get right (see design-guide.md 2.7.1). None of that validation transfers
# automatically to Server 2025 -- treat a first real run here the same way,
# expect to hit and fix new issues, not just reuse this file as-is.

# NOTE (2026-09-25, from the 2022 build): root disk on h3 is tight (~4.3G
# free after pruning ~1.7G of unused container image layers -- was 2.6G,
# dropped there from Packer's own scratch/TMPDIR work landing on root, see
# below). Not enough for the eval ISO (~7.6G for 2025) + virtio-win.iso
# (~0.5G) + the qcow2 during install. BUILD_DIR below defaults to
# /media/nfs so Packer's downloads, cache, TMPDIR scratch, and output all
# land there instead. The one thing that CAN'T move: the final
# `docker build` layer commit still lands in container storage under
# /var/lib/containers on root -- see the size check before that step
# below. If it's tight, check `docker system df` and prune unused images
# first rather than guessing (confirm nothing "ACTIVE" gets touched
# before doing so).

# VARIANT: Core (headless, small) vs Desktop Experience (GUI, for running
# RSAT tools inside an isolated lab network without punching AD's
# RPC/LDAP/Kerberos port set through a DNAT boundary to an outside Windows
# box). These are two genuinely independent full installs -- Windows does
# NOT support converting Core to Desktop Experience (or back) after
# install; the GUI shell payload isn't present in Core media at all -- so
# this always means a full separate Packer build per variant, not a
# smaller incremental one.
VARIANT="${1:-core}"
case "${VARIANT}" in
  core)
    IMG_NAME=ctlabs/qemu/win25/core
    IMAGE_NAME="Windows Server 2025 SERVERSTANDARDCORE"
    # Standard Microsoft naming convention (matches 2022's confirmed
    # pattern), but UNLIKE 2022's value, NOT yet confirmed against the
    # real eval WIM -- check with `wimlib-imagex info` (or
    # Get-WindowsImage) before trusting it on a first build.
    DISK_SIZE="20480" # MB -- copied from 2022's Core sizing, not verified
    # against a real 2025 install; bump if actual usage runs higher.
    OUTPUT_SUBDIR="output-win25-core"
    ;;
  dtop)
    IMG_NAME=ctlabs/qemu/win25/dtop
    IMAGE_NAME="Windows Server 2025 SERVERSTANDARD"
    # Same unverified caveat as core's IMAGE_NAME above, one level up
    # (drops the "CORE" suffix per the standard naming convention).
    DISK_SIZE="40960" # MB -- Desktop Experience roughly triples Core's
    # on-disk footprint (per 2022's experience, design-guide.md 2.7.1);
    # this is a thin-provisioned ceiling, not eager allocation.
    OUTPUT_SUBDIR="output-win25-dtop"
    ;;
  *)
    echo "usage: $0 [core|dtop]" >&2
    exit 1
    ;;
esac

# cracklib-packer (an unrelated password-dictionary tool) is symlinked at
# /usr/sbin/packer and shadows the real HashiCorp packer at /usr/bin/packer
# in PATH order on this box (and inside the ansible/ctrl container too) --
# confirmed 2026-09-25, `packer version` silently ran cracklib and printed
# "0 0" instead of erroring. Always call by absolute path here.
PACKER=/usr/bin/packer

IMG_VERS=0.1.0
QIMG_NAME=windows-server-2025.qcow2
BUILD_DIR="${BUILD_DIR:-/media/nfs/ctlabs-win2025-build}"
VIRTIO_ISO="${BUILD_DIR}/virtio-win.iso"
VIRTIO_ISO_URL=https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
VIRTIO_DIR="${BUILD_DIR}/virtio-win-extracted"
OUTPUT_DIR="${BUILD_DIR}/${OUTPUT_SUBDIR}"

# Sourced from dockur/windows's src/define.sh ("win2025-eval" entry),
# fetched directly via curl+grep 2026-09-27 (not WebFetch's LLM-summarized
# output -- that mangled an exact string once already this session, see
# MEMORY.md/design-guide.md; always verify byte-exact strings like this
# via raw fetch). NOT independently verified by actually downloading and
# hashing the ISO here -- if this 404s or the checksum mismatches,
# re-check https://github.com/dockur/windows/blob/master/src/define.sh
# for the current win2025-eval url/sum and override via env instead of
# editing here. 180-day evaluation build -- fine for lab use, not for
# anything long-lived.
WIN_ISO_URL="${WIN_ISO_URL:-https://software-static.download.prss.microsoft.com/dbazure/998969d5-f34g-4e03-ac9d-1f9786c66749/26100.32230.260111-0550.lt_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso}"
WIN_ISO_CHECKSUM="${WIN_ISO_CHECKSUM:-sha256:7b052573ba7894c9924e3e87ba732ccd354d18cb75a883efa9b900ea125bfd51}"

build_qcow2() {
  mkdir -p "${BUILD_DIR}"

  # A killed/interrupted run (e.g. Ctrl-C or `kill -9` on a stuck install)
  # skips Packer's own cleanup, leaving generated CD/floppy scratch images
  # behind under TMPDIR. Bit us 2026-09-26 (on the 2022 build): grew to
  # 8.8G across a few killed attempts and nearly ate all of BUILD_DIR's
  # free space. TMPDIR is pure scratch, regenerated every run -- always
  # safe to clear first.
  rm -rf "${BUILD_DIR}/tmp"

  if [ ! -e "${VIRTIO_ISO}" ]; then
    curl -sLo "${VIRTIO_ISO}" ${VIRTIO_ISO_URL}
  fi

  # cd_files (packer's supported way to attach extra content) bundles loose
  # files/dirs into a new CD -- it can't attach a pre-built .iso directly --
  # so extract virtio-win.iso once via loopback mount rather than pointing
  # Packer at the .iso itself. Shared between variants, not rebuilt per one.
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
    # defaults to /tmp -- on root, not BUILD_DIR. Bit us 2026-09-25 (on the
    # 2022 build): "genisoimage: No space left on device" mid-build, root
    # dropped from 7.4G to 2.6G free with no obvious cause until this was
    # found.
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

# Docker build context is BUILD_DIR's output dir (has the qcow2), not this
# repo dir -- stage the per-image qemu_init.sh extension alongside it so
# the Dockerfile's COPY can see it.
cp -a files/qemu_init.d "${OUTPUT_DIR}/"

docker build --rm -f Dockerfile -t ${IMG_NAME}:${IMG_VERS} -t ${IMG_NAME}:latest "${OUTPUT_DIR}"
