#!/usr/bin/env bash
set -Eeuo pipefail

info () { printf "%b%s%b" "\E[1;34m❯ \E[1;36m" "${1:-}" "\E[0m\n"; }
error () { printf "%b%s%b" "\E[1;31m❯ " "ERROR: ${1:-}" "\E[0m\n" >&2; }
warn () { printf "%b%s%b" "\E[1;31m❯ " "Warning: ${1:-}" "\E[0m\n" >&2; }

trap 'error "Status $? while: $BASH_COMMAND (line $LINENO/$BASH_LINENO)"' ERR

[ ! -f "/run/entry.sh" ] && error "Script must run inside Docker container!" && exit 11
[ "$(id -u)" -ne "0" ] && error "Script must be executed with root privileges." && exit 12

echo "❯ Starting $APP for Docker v$(</run/version)..."
echo "❯ For support visit $SUPPORT"

# Docker environment variables

: "${BOOT:=""}"            # URL of the ISO file
: "${DEBUG:="N"}"          # Disable debugging
: "${COMMIT:="N"}"         # Commit to image
: "${MACHINE:="q35"}"      # Machine selection
: "${ALLOCATE:=""}"        # Preallocate diskspace
: "${ARGUMENTS:=""}"       # Extra QEMU parameters
: "${CPU_CORES:="1"}"      # Amount of CPU cores
: "${RAM_SIZE:="1G"}"      # Maximum RAM amount
: "${RAM_CHECK:="Y"}"      # Check available RAM
: "${DISK_SIZE:="16G"}"    # Initial data disk size
: "${BOOT_MODE:=""}"       # Boot system with UEFI
: "${BOOT_INDEX:="9"}"     # Boot index of CD drive
: "${STORAGE:="/storage"}" # Storage folder location

# Helper variables

PROCESS="${APP,,}"
PROCESS="${PROCESS// /-}"

INFO="/run/shm/msg.html"
PAGE="/run/shm/index.html"
TEMPLATE="/var/www/index.html"
FOOTER1="$APP for Docker v$(</run/version)"
FOOTER2="<a href='$SUPPORT'>$SUPPORT</a>"

CPI=$(lscpu)
SYS=$(uname -r)
HOST=$(hostname -s)
KERNEL=$(echo "$SYS" | cut -b 1)
MINOR=$(echo "$SYS" | cut -d '.' -f2)
ARCH=$(dpkg --print-architecture)
CORES=$(grep -c '^processor' /proc/cpuinfo)

if ! grep -qi "socket(s)" <<< "$CPI"; then
  SOCKETS=1
else
  SOCKETS=$(echo "$CPI" | grep -m 1 -i 'socket(s)' | awk '{print $(2)}')
fi

if ! grep -qi "model name" <<< "$CPI"; then
  CPU=""
else
  CPU=$(echo "$CPI" | grep -m 1 -i 'model name' | cut -f 2 -d ":" | awk '{$1=$1}1' | sed 's# @.*##g' | sed s/"(R)"//g | sed 's/[^[:alnum:] ]\+/ /g' | sed 's/  */ /g')
fi

if [ -z "${CPU// /}" ] && grep -qi "model:" <<< "$CPI"; then
  CPU=$(echo "$CPI" | grep -m 1 -i 'model:' | cut -f 2 -d ":" | awk '{$1=$1}1' | sed 's# @.*##g' | sed s/"(R)"//g | sed 's/[^[:alnum:] ]\+/ /g' | sed 's/  */ /g')
fi

CPU="${CPU// CPU/}"
CPU="${CPU// 16 Core/}"
CPU="${CPU// Processor/}"
CPU="${CPU// Quad core/}"
CPU="${CPU// Core TM/ Core}"
CPU="${CPU// with Radeon Graphics/}"
[ -z "${CPU// /}" ] && CPU="Unknown"

# Check system

if [ ! -d "/dev/shm" ]; then
  error "Directory /dev/shm not found!" && exit 14
else
  [ ! -d "/run/shm" ] && ln -s /dev/shm /run/shm
fi

# Check folder

if [[ "$COMMIT" != [Nn]* ]]; then
  STORAGE="/local"
  mkdir -p "$STORAGE"
else
  if [ ! -d "$STORAGE" ]; then
    error "Storage folder ($STORAGE) not found!" && exit 13
  fi
fi

# Read memory
RAM_SPARE=500000000
RAM_AVAIL=$(free -b | grep -m 1 Mem: | awk '{print $7}')
RAM_TOTAL=$(free -b | grep -m 1 Mem: | awk '{print $2}')
RAM_SIZE=$(echo "${RAM_SIZE^^}" | sed 's/MB/M/g;s/GB/G/g;s/TB/T/g')
RAM_WANTED=$(numfmt --from=iec "$RAM_SIZE")
AVAIL_GB=$(( RAM_AVAIL/1073741824 ))
TOTAL_GB=$(( (RAM_TOTAL + 1073741823)/1073741824 ))
WANTED_GB=$(( (RAM_WANTED + 1073741823)/1073741824 ))

# Print system info
SYS="${SYS/-generic/}"
FS=$(stat -f -c %T "$STORAGE")
FS="${FS/UNKNOWN //}"
FS="${FS/ext2\/ext3/ext4}"
FS=$(echo "$FS" | sed 's/[)(]//g')
SPACE=$(df --output=avail -B 1 "$STORAGE" | tail -n 1)
SPACE_GB=$(( (SPACE + 1073741823)/1073741824 ))

echo "❯ CPU: ${CPU} | RAM: $AVAIL_GB/$TOTAL_GB GB | DISK: $SPACE_GB GB (${FS}) | KERNEL: ${SYS}..."
echo

# Check compatibilty

if [[ "${FS,,}" == "ecryptfs" ]] || [[ "${FS,,}" == "tmpfs" ]]; then
  DISK_IO="threads"
  DISK_CACHE="writeback"
fi

if [[ "${BOOT_MODE:-}" == "windows"* ]]; then
  if [[ "${FS,,}" == "btrfs" ]]; then
    warn "you are using the BTRFS filesystem for /storage, this might introduce issues with Windows Setup!"
  fi
fi

# Check memory

if [[ "$RAM_CHECK" != [Nn]* ]] && (( (RAM_WANTED + RAM_SPARE) > RAM_AVAIL )); then
  error "Your configured RAM_SIZE of $WANTED_GB GB is too high for the $AVAIL_GB GB of memory available, please set a lower value."
  exit 17
fi

# Helper functions

isAlive() {
  local pid=$1

  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi

  return 1
}

pKill() {
  local pid=$1

  { kill -15 "$pid" || true; } 2>/dev/null

  while isAlive "$pid"; do
    sleep 0.2
  done

  return 0
}

fWait() {
  local name=$1

  while pgrep -f -l "$name" >/dev/null; do
    sleep 0.2
  done

  return 0
}

fKill() {
  local name=$1

  { pkill -f "$name" || true; } 2>/dev/null
  fWait "$name"

  return 0
}

escape () {
    local s
    s=${1//&/\&amp;}
    s=${s//</\&lt;}
    s=${s//>/\&gt;}
    s=${s//'"'/\&quot;}
    printf -- %s "$s"
    return 0
}

html()
{
    local title
    local body
    local script
    local footer

    title=$(escape "$APP")
    title="<title>$title</title>"
    footer=$(escape "$FOOTER1")

    body=$(escape "$1")
    if [[ "$body" == *"..." ]]; then
      body="<p class=\"loading\">${body/.../}</p>"
    fi

    [ -n "${2:-}" ] && script="$2" || script=""

    local HTML
    HTML=$(<"$TEMPLATE")
    HTML="${HTML/\[1\]/$title}"
    HTML="${HTML/\[2\]/$script}"
    HTML="${HTML/\[3\]/$body}"
    HTML="${HTML/\[4\]/$footer}"
    HTML="${HTML/\[5\]/$FOOTER2}"

    echo "$HTML" > "$PAGE"
    echo "$body" > "$INFO"

    return 0
}

addPackage() {
  local pkg=$1
  local desc=$2

  if apt-mark showinstall | grep -qx "$pkg"; then
    return 0
  fi

  MSG="Installing $desc..."
  info "$MSG" && html "$MSG"

  DEBIAN_FRONTEND=noninteractive apt-get -qq update
  DEBIAN_FRONTEND=noninteractive apt-get -qq --no-install-recommends -y install "$pkg" > /dev/null

  return 0
}

hasDisk() {

  [ -b "/disk" ] && return 0
  [ -b "/disk1" ] && return 0
  [ -b "/dev/disk1" ] && return 0
  [ -b "${DEVICE:-}" ] && return 0

  [ -z "${DISK_NAME:-}" ] && DISK_NAME="data"
  [ -s "$STORAGE/$DISK_NAME.img" ]  && return 0
  [ -s "$STORAGE/$DISK_NAME.qcow2" ] && return 0

  return 1
}

# Start webserver
#cp -r /var/www/* /run/shm
#html "Starting $APP for Docker..."
#nginx -e stderr

return 0
