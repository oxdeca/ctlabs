packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

# DRAFT / UNVALIDATED (2026-09-27) -- copied from the sibling win2022.pkr.hcl
# (see design-guide.md 2.7.1 for that pipeline's full validated history and
# every real bug found getting it working). NONE of that validation
# transfers automatically: Server 2025 is a different OS build and could
# hit its own new issues this file hasn't seen yet (autounattend.xml
# schema/behavior changes, different default security baseline -- e.g.
# Server 2025 tightened Credential Guard/VBS defaults versus 2022, WHICH
# THIS HAS NOT BEEN CHECKED AGAINST -- WIM image-index names, driver
# binding, winrm timing, all of it). Treat this the same way the original
# 2022 pipeline was treated before its first real build: needs live
# iteration against a real ISO, not just a copy-paste.
#
# iso_url/iso_checksum defaults below are the real win2025-eval values
# from dockur/windows's src/define.sh (fetched directly via curl+grep,
# 2026-09-27, matching the exact sourcing method used for 2022's) -- not
# independently verified by actually downloading and hashing the ISO here.

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
  default = "20480" # MB -- copied from 2022's Core sizing (~4-6G actual
  # usage there). NOT verified against a real 2025 Core install -- newer
  # OS builds tend to grow, so check actual post-install usage on the
  # first real build and bump if this is too tight. qcow2 is thin-
  # provisioned regardless -- this is a ceiling, not eager allocation.
  # build.sh overrides this to a larger value for the Desktop Experience
  # (`dtop`) variant, which needs meaningfully more room.
}

variable "image_name" {
  type    = string
  default = "Windows Server 2025 SERVERSTANDARDCORE" # Core -- standard
  # Microsoft naming convention (matches 2022/2019/2016's pattern), but
  # UNLIKE 2022's value, this has NOT been confirmed against the real
  # eval WIM yet. Check with `wimlib-imagex info` (or
  # `Get-WindowsImage -ImagePath D:\sources\install.wim`) against the
  # actual mounted ISO before trusting it -- if Setup shows "No images
  # are available" or similar, this value is the first thing to
  # re-verify. build.sh overrides this to
  # "Windows Server 2025 SERVERSTANDARD" (no "CORE" suffix, same
  # unverified caveat) for the Desktop Experience variant.
  description = "WIM /IMAGE/NAME value selecting which edition autounattend.xml installs."
}

source "qemu" "win2025" {
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
  vm_name          = "windows-server-2025.qcow2"
  format           = "qcow2"
  accelerator      = "kvm"
  headless         = true

  # Default plugin CPU model is the deprecated, minimal "qemu64" (its own
  # startup warning says as much). Confirmed 2026-09-26 on h3: the guest
  # hung solid ~20+ min post-reboot at the boot logo, CPU pegged but real
  # disk I/O (read_bytes/write_bytes in /proc/<pid>/io) completely flat --
  # not slow NFS I/O, a genuine stall. Matches the other ctlabs qemu images'
  # own convention (qemu_init.sh uses "-cpu host,...") -- exposing full host
  # features is fine here since this is a one-shot build VM, not something
  # needing live-migration compatibility across mismatched hosts.
  cpu_model = "host"

  cpus   = var.cpus
  memory = var.memory
  disk_size       = var.disk_size
  disk_interface  = "virtio-scsi"
  # Tried e1000 for the build VM briefly (2026-09-26) on the theory that
  # NetKVM binding was flaky -- turned out not to be the issue at all (the
  # real bug was the <AutoLogon> element order, see autounattend.xml).
  # Reverted to virtio-net once a genuinely working config was confirmed.
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
  # Explicit, matching github.com/therayy/packer-windows2022-qemu's own
  # template (their enable-winrm.ps1 comments note these "must match" the
  # Packer side) -- both already equal Packer's defaults for a plain-HTTP
  # WinRM setup, but being explicit guards against any environment where
  # that default differs.
  winrm_use_ssl  = false
  winrm_insecure = true
  # Deliberately NOT setting winrm_use_ntlm. Tried it (=true) first on the
  # theory that Kerberos-first Negotiate can't work against a standalone
  # WORKGROUP machine -- wrong theory, reverted 2026-09-26. Proven via a
  # live interactive PowerShell session on a stuck build: the WinRM service
  # only advertises "WWW-Authenticate: Negotiate" (confirmed with `winrm get
  # winrm/config/service/auth`: Negotiate=true, Kerberos=true, Basic=false --
  # no separate NTLM scheme), and `Test-WSMan -Authentication Negotiate`
  # with the real Administrator credentials succeeded cleanly. Firewall/
  # network-profile was also ruled out (`Get-NetFirewallRule` showed our own
  # rule already Enabled/Profile=Any/Allow). winrm_use_ntlm=true forces
  # Packer's raw-NTLM client transport, which a server that only advertises
  # "Negotiate" (SPNEGO-wrapped) appears to silently reject -- Packer just
  # retries forever rather than surfacing an auth error. Default (unset)
  # uses the SPNEGO-wrapped path that the live test just proved works.

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
  # driver binding) was added wholesale. Trimmed to .cat/.inf/.sys per
  # driver, but that dropped the network adapter entirely (confirmed live:
  # install completed fine, but Server Core's SConfig showed no NIC at
  # all) -- netkvm.inf's own [Install.NT] CopyFiles directive requires
  # netkvmp.exe (a real install-time dependency, not just a bonus config
  # tool like the much larger netkvmco.exe, which genuinely isn't
  # referenced anywhere in the INF and stays excluded). Adding it back:
  # still well under the floppy cap (~501K total vs ~1.44M).
  # UNVERIFIED FOR 2025 (2026-09-27): these paths still point at the
  # "2k22" driver directory, copied as-is from the 2022 pipeline. Checked
  # vioscsi's own INF source (vioscsi.inx in
  # virtio-win/kvm-guest-drivers-windows) directly -- its [Manufacturer]/
  # [VirtioScsi.NTamd64] PnP-matching rules have NO OS-version gate at
  # all, so a "2k22"-labeled driver binding on a Server 2025 guest isn't
  # inherently impossible. But virtio-win packages a SEPARATE, WHQL-signed
  # catalog per OS directory (2k16/2k19/2k22/w10/w11/...), and that
  # signing is what Windows' driver-signature enforcement actually checks
  # -- not just PnP hardware-ID matching -- and WHQL certification for a
  # newer OS release lags behind the OS itself, so a dedicated "2k25"
  # directory may or may not exist yet in whatever virtio-win-stable.iso
  # gets downloaded. Could not confirm either way without extracting a
  # real ISO. Before the first real build: `ls ${virtio_drivers_dir}/
  # vioscsi/` (and `NetKVM/`) and use "2k25" paths here if present --
  # only fall back to "2k22" (as currently written) if it's genuinely
  # not there yet.
  floppy_files = [
    "files/enable-winrm.ps1",
    "${var.virtio_drivers_dir}/vioscsi/2k22/amd64/vioscsi.cat",
    "${var.virtio_drivers_dir}/vioscsi/2k22/amd64/vioscsi.inf",
    "${var.virtio_drivers_dir}/vioscsi/2k22/amd64/vioscsi.sys",
    "${var.virtio_drivers_dir}/NetKVM/2k22/amd64/netkvmp.exe",
    "${var.virtio_drivers_dir}/NetKVM/2k22/amd64/netkvm.cat",
    "${var.virtio_drivers_dir}/NetKVM/2k22/amd64/netkvm.inf",
    "${var.virtio_drivers_dir}/NetKVM/2k22/amd64/netkvm.sys",
  ]

  # autounattend.xml is rendered from a template (floppy_content, not a
  # static floppy_files entry) so the one line that differs between the
  # Core and Desktop Experience variants (the WIM /IMAGE/NAME value) can be
  # parameterized via var.image_name instead of maintaining two near-
  # identical copies of the whole file. Confirmed the installed plugin
  # (v1.1.3) supports floppy_content (`strings` on the binary shows
  # `mapstructure:"floppy_content"`/`hcl:"floppy_content"`) and that it
  # merges onto the same floppy as floppy_files above, not a separate one.
  floppy_content = {
    "autounattend.xml" = templatefile("${path.root}/autounattend.xml.pkrtpl.hcl", {
      image_name = var.image_name
    })
  }

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

  # STAGE 1 (2026-09-26): plain forced shutdown, no sysprep, matching the
  # exact config that finally got the whole pipeline working end-to-end
  # (boot, install, WinRM connect, provision, shutdown, capture) after this
  # session's long debugging saga. Deliberately validating the baseline
  # pipeline before layering sysprep generalization back in as a separate,
  # separately-tested step -- see TODO below.
  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer Shutdown\""
  shutdown_timeout = "30m"
}

build {
  sources = ["source.qemu.win2025"]

  # STAGE 2 (2026-09-27): real payload -- OpenSSH via a SYSTEM-context
  # scheduled task, the boot-time ctlabs-net-agent registration (which is
  # what actually runs qemu_init.sh's generated ctlabs_net_setup.ps1 every
  # boot), and timezone. Confirmed missing entirely from the image that
  # first booted successfully 2026-09-27 -- that build only ran the Stage 1
  # placeholder below, so neither OpenSSH nor the net-agent task were ever
  # installed. This is the fix.
  provisioner "powershell" {
    script = "files/ctlabs-firstboot.ps1"
  }
}
