#!/bin/bash

# -----------------------------------------------------------------------------
# File        : ctlabs-terraform/lpic2/ppvm.sh
# Description : Post-Provisioning Script for centos 9 vm's
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# COMMANDS
# -----------------------------------------------------------------------------
#
CP=/usr/bin/cp
LN=/usr/bin/ln
MV=/usr/bin/mv
GEM=/usr/bin/gem
GIT=/usr/bin/git
PIP=/usr/bin/pip3
DNF=/usr/bin/dnf
SED=/usr/bin/sed
BASH=/bin/bash
ECHO=/usr/bin/echo
CURL=/usr/bin/curl
SCTL=/usr/bin/systemctl
MAKE=/usr/bin/make
CHMOD=/usr/bin/chmod
MKDIR=/usr/bin/mkdir
PYTHON=/usr/bin/python3
DOCKER=/usr/bin/docker
TOUCH=/usr/bin/touch
BASE64=/usr/bin/base64
SYSTEMCTL=/usr/bin/systemctl
OPENSSL=/usr/bin/openssl


# -----------------------------------------------------------------------------
# GLOBALS
# -----------------------------------------------------------------------------
#
LAB="lpic2.c9"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PKGS=(
  'lvm2'
  'tmux'
  'vim'
  'git'
  'graphviz'
  'epel-release'
  'htop'
  'ruby'
  'irb'
  'podman-docker'
  'wireshark-cli'
  'tcpdump'
  'nc'
  'perf'
  'bpftrace'
  "kernel-modules-extra-$(uname -r)"
  'python3-pip'
  'ipvsadm'
  'qemu-img'
  'cloud-utils-growpart'
  'make'
  'gcc'
  'g++'
  'ruby-devel'
  'redhat-rpm-config'
)

GEMS=(
  'webrick'
  'sinatra'
  'rackup'
  'faye-websocket'
  'puma'
)

CTIMGS=(
  "${HOME}/ctlabs/images/centos/c9"
  "${HOME}/ctlabs/images/debian/d12"
  "${HOME}/ctlabs/images/kali"
  "${HOME}/ctlabs/images/parrot"
)

BASHRC_KALI="https://raw.githubusercontent.com/oxdeca/ctlabs/refs/heads/main/install/bashrc.kali"
TMUX_CONF="https://raw.githubusercontent.com/oxdeca/ctlabs/refs/heads/main/install/tmux.conf"

# -----------------------------------------------------------------------------
# FUNCTIONS
# -----------------------------------------------------------------------------
#
os_update() {
  ${DNF} -y update > /dev/null 2>&1
}

packages() {
  for p in "${PKGS[@]}"; do
    ${DNF} -y install "${p}" > /dev/null 2>&1
  done

  ${TOUCH} /etc/containers/nodocker
  ${GEM} install --no-document ${GEMS[*]} > /dev/null 2>&1
}

config() {
  ${MKDIR} -vp /etc/ansible/facts.d > /dev/null 2>&1

  ${ECHO} '
  alias vi="/usr/bin/vim"
  alias pva=". ~/virtenv/bin/activate"
  alias pve="deactivate"
  alias kubectl="/usr/bin/k3s kubectl"
  alias crictl="/usr/bin/k3s crictl"
  alias ctr="/usr/bin/k3s ctr"
  alias kc=kubectl

  function enter() {
    docker exec -it -w ~/ ${1} bash
  }
  ' > /etc/profile.d/bashrc_ctlabs.sh

  ${CURL} -skL "${BASHRC_KALI}" -o /etc/profile.d/bashrc_kali.sh
  ${ECHO} "set paste" >> /etc/vimrc
}

services() {
  ${SCTL} disable --now firewalld.service > /dev/null 2>&1
}


tmux() {
  ${CURL} -skL "${TMUX_CONF}" -o /etc/tmux.conf
}

ansible() {
  ${PYTHON} -mpip install pip --upgrade -q > /dev/null 2>&1
  ${PYTHON} -m venv ~/virtenv > /dev/null 2>&1
  . ~/virtenv/bin/activate
  python -mpip install pip --upgrade -q > /dev/null 2>&1
  python -mpip install ansible -q > /dev/null 2>&1
}

clone_repo() {
  if [ !-d "ctlabs" ]; then
    ${GIT} clone https://github.com/oxdeca/ctlabs 
  fi
  if [ !-d "ctlabs-ansible" ]; then
    ${GIT} clone https://github.com/oxdeca/ctlabs-ansible
  fi
  
  if [ !-d "/srv/ctlabs-server/public" ]; then
    ${MKDIR} -vp /srv/ctlabs-server/public/ > /dev/null 2>&1
  fi
  ${LN} -svf "${HOME}/ctlabs/ctlabs/js/"  /srv/ctlabs-server/public/js > /dev/null 2>&1
  ${LN} -svf "${HOME}/ctlabs/ctlabs/css/" /srv/ctlabs-server/public/css > /dev/null 2>&1
  
  # Update the service file dynamically
  ${SED} -i "s|WorkingDirectory=.*|WorkingDirectory=${HOME}/ctlabs|"    ctlabs/ctlabs/ctlabs-server.service
  ${SED} -i "s|ExecStart=.*|ExecStart=${HOME}/ctlabs/ctlabs/server.rb|" ctlabs/ctlabs/ctlabs-server.service

  ${CP} ctlabs/ctlabs/ctlabs-server.service /etc/systemd/system/
  ${SYSTEMCTL} daemon-reload
  ${SYSTEMCTL} enable --now ctlabs-server.service > /dev/null 2>&1
}

ctimages() {
  for d in "${CTIMGS[@]}"; do
    cd ${d}
    ${MAKE} -s > /dev/null 2>&1
  done
}

selinux() {
  setenforce permissive > /dev/null 2>&1
  ${SED} -ri 's@(SELINUX=).*@\1permissive@' /etc/selinux/config
}

set_password() {
  SUGGESTED_PASS=$(${OPENSSL} rand -base64 12)
  echo -e "${CYAN}-----------------------------------------------------------------------------${NC}"
  echo -e "${MAGENTA}WEB UI SECURITY${NC}"
  echo -e "${CYAN}-----------------------------------------------------------------------------${NC}"
  echo -e "Suggested secure password: ${GREEN}${SUGGESTED_PASS}${NC}"
  echo -ne "Enter password for 'ctlabs' user (${YELLOW}leave empty to use suggested${NC}): "
  read PASS
  PASS=${PASS:-${SUGGESTED_PASS}}
  echo -e "Password set to: ${GREEN}${PASS}${NC}"
  
  SALT="GGV78Ib5vVRkTc"
  # Generate SHA-512 hash
  HASH=$(${OPENSSL} passwd -6 -salt "${SALT}" "${PASS}")
  
  # Replace in base_controller.rb
  # Using @ as delimiter for sed to avoid issues with / in the hash
  ${SED} -i "s@password_hash = \".*\"@password_hash = \"${HASH}\"@" ctlabs/ctlabs/controllers/base_controller.rb
  echo -e "${CYAN}-----------------------------------------------------------------------------${NC}"
}

status_check() {
  echo -e "${BLUE}Performing final status checks...${NC}"

  # Get primary IP address
  HOSTIP=$(hostname -I | awk '{print $1}')
  URL="https://${HOSTIP}:4567"

  # Wait for service to initialize
  echo -ne "Waiting for ctlabs-server to start..."
  for i in {1..30}; do
    if ${CURL} -sk "${URL}" > /dev/null; then
      echo -e " ${GREEN}UP${NC}"
      echo -e "\n${GREEN}=============================================================================${NC}"
      echo -e "${GREEN}CT LABS DEPLOYMENT SUCCESSFUL${NC}"
      echo -e "${GREEN}=============================================================================${NC}"
      echo -e "Web UI is ready at: ${CYAN}${URL}${NC}"
      echo -e "Default user      : ${CYAN}ctlabs${NC}"
      echo -e "Password          : ${CYAN}${PASS}${NC}"
      echo -e "${GREEN}=============================================================================${NC}"
      return 0
    fi
    echo -ne "."
    sleep 2
  done

  echo -e " ${RED}TIMED OUT${NC}"
  echo -e "${YELLOW}Warning: The service didn't respond within 60s. Check 'systemctl status ctlabs-server'${NC}"
  echo -e "Once running, access it at: ${CYAN}${URL}${NC}"
}

run_task() {
  local msg=$1
  shift
  printf "${BLUE}%-50s${NC} " "${msg}..."
  printf "[|]"
  "$@" > /dev/null 2>&1 &
  local pid=$!
  local spin='|/-\'
  local i=0
  while kill -0 $pid 2>/dev/null; do
    printf "\b\b%s]" "${spin:$i:1}"
    i=$(( (i+1) % 4 ))
    sleep 0.1
  done
  wait $pid
  local res=$?
  if [ $res -eq 0 ]; then
    printf "\b\b\b[  ${GREEN}OK${NC}  ]\n"
  else
    printf "\b\b\b[ ${RED}FAIL${NC} ]\n"
    return $res
  fi
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
#
echo -e "${CYAN}Starting CT Labs Deployment...${NC}"
run_task "Configuring SELinux" selinux
run_task "Configuring system" config
run_task "Configuring tmux" tmux
run_task "Updating OS" os_update
run_task "Installing packages" packages
run_task "Configuring services" services
run_task "Cloning repositories" clone_repo
set_password
run_task "Building container images" ctimages
status_check
