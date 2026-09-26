packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

# DRAFT / UNVALIDATED (2026-09-25) -- built from documented Packer qemu-plugin
# behavior, never run against real infra. iso_checksum, the WIM image_index
# for "Server 2022 Standard (Desktop Experience)" vs Core, and winrm timing
# all need live verification on the first real build. See build.sh.

variable "iso_url" {
  type        = string
  description = "Path/URL to the Windows Server 2022 evaluation ISO (Microsoft eval center, manual download -- no stable script-fetchable URL)."
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
  default     = "output-win2022"
  description = "Where the finished qcow2 lands. Point this at a volume with real free space (e.g. /media/nfs/...) -- root disk on h3 only has ~7G free."
}

variable "disk_size" {
  type    = string
  default = "20480" # MB -- sized for Server Core (~4-6G used post-install),
  # not Desktop Experience. qcow2 is thin-provisioned so this is a ceiling,
  # not eager allocation -- the packaged image will be close to actual
  # usage, not this number. Deliberately below Microsoft's officially
  # published 32G minimum; acceptable for disposable/rebuildable lab nodes,
  # but if the guest ever runs Windows Update, WinSxS growth could eat
  # into this fast -- bump it if that becomes a problem.
}

source "qemu" "win2022" {
  # EL9's qemu-kvm package ships the binary at /usr/libexec/qemu-kvm, not
  # /usr/bin/qemu-system-x86_64 (that name is a Debian/Ubuntu convention) --
  # the qemu plugin defaults to the latter and errors "executable file not
  # found in $PATH" otherwise. Confirmed missing entirely on h3 2026-09-25
  # (only qemu-img/qemu-guest-agent were installed) -- `dnf install qemu-kvm
  # genisoimage` first if this errors again on a fresh host.
  qemu_binary = "/usr/libexec/qemu-kvm"

  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum
  output_directory = var.output_dir
  vm_name          = "windows-server-2022.qcow2"
  format           = "qcow2"
  accelerator      = "kvm"
  headless         = true

  cpus   = var.cpus
  memory = var.memory
  disk_size       = var.disk_size
  disk_interface  = "virtio-scsi"
  net_device      = "virtio-net"

  # Root cause of "install never starts" confirmed 2026-09-26 on two
  # separate hosts (h3 ran 4+ hours, qcow2 grew 196K -> 324K the whole
  # time -- never actually booted the installer): the Windows ISO shows a
  # BIOS "Press any key to boot from CD or DVD..." prompt, and with no
  # boot_command at all the VM let that prompt time out and fell through to
  # the empty hard disk instead, spinning forever with no OS to boot. This
  # sends Enter early enough to catch it.
  boot_wait    = "5s"
  boot_command = ["<enter>"]

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.admin_password
  winrm_timeout  = "6h" # unattended install + reboots can run long, unverified real-world duration

  # WinPE has no inbox virtio-scsi/virtio-net drivers, so without these
  # Setup can't even see disk 0 to partition it -- confirmed 2026-09-26,
  # this is the actual cause of "Windows could not apply the unattend
  # answer file's <DiskConfiguration> settings" (and would separately have
  # broken WinRM/networking post-install too, via the missing NIC driver).
  # floppy_files flattens everything into A:\ root (confirmed via Packer's
  # own "Copying files flatly from floppy_files" log line) -- vioscsi's and
  # NetKVM's files don't collide by name, so DriverPaths below just points
  # at the floppy root.
  #
  # Packer's floppy is a real, size-capped FAT12 image (~1.44M) -- confirmed
  # 2026-09-26 via "FAT FULL" when the whole NetKVM/2k22/amd64 dir (19M,
  # mostly .pdb debug symbols and coinstaller .exe/.pdb not needed for
  # driver binding) was added wholesale. Only .cat/.inf/.sys are actually
  # required; those three per driver total ~320K, comfortably under the cap.
  floppy_files = [
    "autounattend.xml",
    "files/ctlabs-firstboot.ps1",
    "${var.virtio_drivers_dir}/vioscsi/2k22/amd64/vioscsi.cat",
    "${var.virtio_drivers_dir}/vioscsi/2k22/amd64/vioscsi.inf",
    "${var.virtio_drivers_dir}/vioscsi/2k22/amd64/vioscsi.sys",
    "${var.virtio_drivers_dir}/NetKVM/2k22/amd64/netkvm.cat",
    "${var.virtio_drivers_dir}/NetKVM/2k22/amd64/netkvm.inf",
    "${var.virtio_drivers_dir}/NetKVM/2k22/amd64/netkvm.sys",
  ]

  # Second CD-ROM for virtio drivers Setup needs to see the virtio-scsi disk
  # and virtio-net NIC at all. NOT via qemuargs -- confirmed 2026-09-25 by
  # reading the installed v1.1.3 plugin's source (step_run.go): any qemuargs
  # entry for a key (e.g. "-drive") REPLACES that key's entire default value
  # wholesale, not appends. A raw ["-drive", "file=...,media=cdrom"] entry
  # here silently ate BOTH the primary disk's drive AND the install ISO's
  # cdrom drive (confirmed via PACKER_LOG=1: "Property 'scsi-hd.drive' can't
  # find value 'drive0'" -- the disk device referenced a drive that no
  # longer existed). cd_files is the actual supported mechanism: it's
  # merged into state("cd_path") -> cdPaths alongside the install ISO in
  # getDeviceAndDriveArgs, not through the qemuargs override path at all.
  cd_files = [var.virtio_drivers_dir]

  shutdown_command = "C:\\Windows\\System32\\Sysprep\\sysprep.exe /generalize /oobe /shutdown /quiet"
  shutdown_timeout = "30m"
}

build {
  sources = ["source.qemu.win2022"]

  provisioner "powershell" {
    script = "files/ctlabs-firstboot.ps1"
  }
}
