packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "iso_url" {
  type        = string
  description = "Path/URL to the Windows Server 2025 evaluation ISO (Microsoft eval center, manual download -- no stable script-fetchable URL)."
}

variable "iso_checksum" {
  type        = string
  description = "e.g. sha256:<hash>, printed on the Microsoft eval download page."
}

variable "virtio_drivers_dir" {
  type        = string
  default     = "virtio-win-extracted"
  description = "Extracted contents of virtio-win.iso (a directory, not the .iso itself -- cd_files bundles loose files into a new CD, it can't attach a pre-built .iso as-is; build.sh extracts it via a loopback mount before invoking packer)."
}

variable "admin_password" {
  type      = string
  default   = "ctlabs-BuildTime!1"
  sensitive = true
  description = "Only used during build (winrm + autounattend); sysprep wipes it. Not the lab-runtime credential."
}

variable "cpus" {
  type    = number
  default = 4
}

variable "memory" {
  type    = number
  default = 4096
}

variable "output_dir" {
  type        = string
  default     = "output-win2025"
  description = "Where the finished qcow2 lands. Point this at a volume with real free space (e.g. /media/nfs/...) -- root disk on h3 only has ~7G free."
}

variable "disk_size" {
  type    = string
  default = "20480"
}

variable "image_name" {
  type    = string
  default = "Windows Server 2025 SERVERSTANDARDCORE"
  description = "WIM /IMAGE/NAME value selecting which edition autounattend.xml installs."
}

source "qemu" "win2025" {
  qemu_binary = "/usr/libexec/qemu-kvm"

  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum
  output_directory = var.output_dir
  vm_name          = "windows-server-2025.qcow2"
  format           = "qcow2"
  accelerator      = "kvm"
  headless         = true
  #vnc_bind_address = "0.0.0.0"

  disk_compression   = true
  disk_discard       = "unmap"
  disk_detect_zeroes = "unmap"

  cpu_model = "host"
  cpus      = var.cpus
  memory    = var.memory

  disk_size       = var.disk_size
  disk_interface  = "virtio-scsi"
  net_device      = "virtio-net"

  boot_wait    = "5s"
  boot_command = ["<enter>"]

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.admin_password
  winrm_timeout  = "6h"
  winrm_use_ssl  = false
  winrm_insecure = true

  floppy_files = [
    "files/enable-winrm.ps1",
    "${var.virtio_drivers_dir}/vioscsi/2k25/amd64/vioscsi.cat",
    "${var.virtio_drivers_dir}/vioscsi/2k25/amd64/vioscsi.inf",
    "${var.virtio_drivers_dir}/vioscsi/2k25/amd64/vioscsi.sys",
    "${var.virtio_drivers_dir}/NetKVM/2k25/amd64/netkvmp.exe",
    "${var.virtio_drivers_dir}/NetKVM/2k25/amd64/netkvm.cat",
    "${var.virtio_drivers_dir}/NetKVM/2k25/amd64/netkvm.inf",
    "${var.virtio_drivers_dir}/NetKVM/2k25/amd64/netkvm.sys",
  ]

  floppy_content = {
    "autounattend.xml" = templatefile("${path.root}/autounattend.xml.pkrtpl.hcl", {
      image_name = var.image_name
    })
  }

  cd_files = [var.virtio_drivers_dir]

  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer Shutdown\""
  shutdown_timeout = "30m"
}

build {
  sources = ["source.qemu.win2025"]

  provisioner "powershell" {
    script = "files/ctlabs-firstboot.ps1"
  }

  provisioner "powershell" {
    script = "files/cleanup.ps1"
  }
}
