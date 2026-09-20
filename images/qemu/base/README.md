# QEMU Images based on Debian

## Environment Variables

The following environment variables can be exported before running the provisioning script to customize the virtual machine's hardware topology, resources, and behavior.

| Variable | Default | Description |
|----------|---------|-------------|
| `QEMU_MEM` | `768M` | Total RAM allocated to the VM. Accepts standard QEMU suffixes (e.g., `M` for Megabytes, `G` for Gigabytes). *Note: When NUMA is enabled, this is split evenly across nodes.* |
| `QEMU_CPU` | `2` | **Target** total number of virtual CPUs (vCPUs). The script uses this to calculate cores, but the *actual* spawned vCPUs will be `sockets × cores × threads`. |
| `QEMU_NUMA_NODES` | `0` | Number of NUMA nodes to emulate. Set to `0` for standard UMA (Uniform Memory Access). Set to `2` (or more) to enable NUMA (Non-Uniform Memory Access). When ≥2, it automatically aligns CPU sockets to match the node count. |
| `QEMU_CPU_SOCKETS` | `1`* | Number of CPU sockets. *Defaults to `QEMU_NUMA_NODES` if NUMA is enabled (≥2), otherwise defaults to `1`. |
| `QEMU_CPU_CORES` | *Calculated* | Number of cores per socket. Automatically calculated as `QEMU_CPU / (QEMU_CPU_SOCKETS * QEMU_CPU_THREADS)`. Minimum value is enforced to `1`. |
| `QEMU_CPU_THREADS` | `2` | Number of threads per core (e.g., `2` enables SMT/Hyper-Threading emulation). |
| `QEMU_VGA` | `none` | VGA display adapter type. Set to `none` for headless operation (recommended). Can be set to `std`, `qxl`, `virtio`, etc., if a display is needed. |
| `IMG` | `debian-12-nocloud-amd64.qcow2` | Filename or path of the base Debian NoCloud image to be used as the primary boot disk. |
| `DISK1` | `/media/vda.qcow2` | Path for the secondary (ephemeral or data) disk. The script will automatically create a `500M` qcow2 file at this location if it does not exist. |
| `HOSTNAME` | *(Required)* | The desired hostname for the guest OS. The script uses this to name the generated cloud-init ISO and to set the hostname inside the guest. |

---

## Usage Examples

### 1. Standard UMA Instance (Default)
Creates a basic 2 vCPU VM with Hyper-Threading (1 Socket, 1 Core, 2 Threads). Ideal for general-purpose workloads.
```bash
export HOSTNAME="uma-web-01"
export QEMU_CPU=2
export QEMU_NUMA_NODES=0      # 0 means standard UMA topology
export QEMU_CPU_THREADS=2
./qemu_init.sh
```

### 2. High-Performance 2-Node NUMA VM
Creates a 4 vCPU VM split evenly across 2 NUMA nodes (2 Sockets, 1 Core per socket, 2 Threads per core). Ideal for databases or NUMA-aware software.
```bash
export HOSTNAME="numa-db-01"
export QEMU_CPU=4             # Must be ≥ 4 to split evenly when threads=2
export QEMU_MEM=4G
export QEMU_NUMA_NODES=2      # 2+ enables NUMA topology
./qemu_init.sh
```

### 3. Custom Topology (4 Sockets, No NUMA)
Creates an 8 vCPU VM with 4 distinct CPU sockets, 1 core per socket, and 2 threads per core (useful for testing software licensed per socket).
```bash
export HOSTNAME="license-test-01"
export QEMU_CPU=8
export QEMU_MEM=8G
export QEMU_CPU_SOCKETS=4
export QEMU_CPU_CORES=1
export QEMU_CPU_THREADS=2
export QEMU_NUMA_NODES=0      # Explicitly disable NUMA
./qemu_init.sh
```

---

## Topology & NUMA Configuration Details

### UMA vs. NUMA
* **UMA (Uniform Memory Access)**: Default when `QEMU_NUMA_NODES=0`. All vCPUs share a single memory pool and memory controller (1 Socket). Memory access latency is uniform.
* **NUMA (Non-Uniform Memory Access)**: Enabled when `QEMU_NUMA_NODES≥2`. Memory is split across multiple nodes (sockets). Local memory access is fast (distance `10`), while cross-node access is slower (distance `20`).

### How the Script Ensures Symmetry
A common pitfall in QEMU is mismatching the target `QEMU_CPU` with the actual spawned vCPUs (`sockets × cores × threads`). If the math results in more vCPUs than requested, unassigned vCPUs are silently dumped into Node 0 by QEMU, breaking symmetry.

To prevent this, the script calculates the **`ACTUAL_VCPUS`** after resolving the topology and uses *that* number to divide CPUs and memory evenly across the requested NUMA nodes. This guarantees perfect symmetry (e.g., Node 0 gets `cpus=0-1`, Node 1 gets `cpus=2-3`).

When NUMA is enabled, the script automatically:
1. **Aligns Sockets**: Sets `QEMU_CPU_SOCKETS` to match `QEMU_NUMA_NODES` (guest OS best practice).
2. **Creates Memory Backends**: Dynamically generates `-object memory-backend-ram` for each node, ensuring modern QEMU `q35` compatibility.
3. **Pins vCPUs**: Assigns contiguous, symmetric vCPU ranges to each node.
4. **Sets Distance Metrics**: Injects `-numa dist,src=0,dst=1,val=20` to accurately simulate remote memory latency.

> **Tip:** You can verify the topology inside the running guest by executing:
> ```bash
> numactl --hardware
> ```

---

# How to create qemu images compatible with ctlabs

## Debian

### Used Packages

- `openssh-server`
- `openssh-client`
- `xterm`
- `lvm2`
- `fdisk`
- `htop`
- `nfs-kernel-server`
- `bpftrace`
- `linux-kernel-headers`
  + `apt search linux-headers-$(uname -r)`

### ctlabs-setup.service

___/etc/systemd/system/ctlabs-net.service___

```bash
# /etc/systemd/system/ctlabs-setup.service
[Unit]
Description=ctlabs network setup
After=network.target

[Service]
Type=oneshot
ExecStart=/root/ctlabs_run_setup.sh
RemainAfterExit=true
#ExecStop=/root/qemu_init.sh
StandardOutput=journal

[Install]
WantedBy=multi-user.target
```

___/root/ctlabs_run_setup.sh___

```bash
#!/bin/bash

mount -t 9p -o trans=virtio setup /mnt

cd /mnt
bash ./ctlabs_net_setup.sh
cd -

umount /mnt

exit 0 
```


### sshd-mgmt.service

```bash
# /etc/systemd/system/sshd-mgmt.service
[Unit]
Description=ctlabs mgmt-sshd 
Documentation=man:sshd(8) man:sshd_config(5)
After=ctlabs-net.service
ConditionPathExists=!/etc/ssh/sshd_not_to_be_run

[Service]
EnvironmentFile=-/etc/default/ssh
ExecStartPre=/sbin/ip vrf exec mgmt /usr/sbin/sshd -t
ExecStart=/sbin/ip vrf exec mgmt /usr/sbin/sshd -D $SSHD_OPTS
ExecReload=/sbin/ip vrf exec mgmt /usr/sbin/sshd -t
ExecReload=/sbin/ip vrf exec mgmt /bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=10s
RestartPreventExitStatus=255
Type=notify
RuntimeDirectory=sshd
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
```


### Environment

___/etc//bashrc.kali___

It's a copy of bashrc.kali

___/etc/profile.d/99-ctlabs.sh___

```bash
#!/bin/bash

export TERM=linux

if [ -f /usr/bin/resize ]; then
  resize > /dev/null
fi

if [ -f /etc/bashrc.kali ]; then
  . /etc/bashrc.kali
fi
```



