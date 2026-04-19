CtLabs
======

`ctlabs` is a tool designed to streamline the creation of repeatable lab environments.
It automates the setup and configuration of lab components, which are all run as containers. When full virtualization is required, ctlabs creates QEMU instances within those containers and connects them to the container's network via TAP interfaces. This approach allows for a consistent and straightforward lab setup, regardless of the virtualization needs.

![CtLabs](./lab_setup.gif) 


Key Features
------------

* **Automated Lab Setup:** Uses YAML configuration files to define complex environments.
* **Hybrid Virtualization:** Support for virtual machines (using QEMU/KVM) and containers (using Podman).
* **Infrastructure as Code:** Integrated editors for Ansible playbooks, Terraform configurations, and Dockerfiles.
* **Segregated Networking:** Automatic creation of isolated Data and Management Networks for enhanced lab security and realism.
* **Real-time Visibility:** Unified logging architecture with real-time streaming in both CLI and web interfaces.
* **Interactive Web Terminal:** Integrated xterm.js-based console access for every node in the lab.
* **Dynamic Topology Mapping:** Automated SVG generation for both Data and Management network planes.
* **Ad-hoc DNAT Management:** Runtime port forwarding with a full audit trail visible in operational logs.
* **Concurrency Protection:** Playbook execution lock prevents dangerous concurrent runs between CLI and web interfaces.
* **CLI and WebUI** Can be used via cli and WebUI

Quick Start
-----------

1. Create a new/Use an existing VM and make sure `nested virtualization` is enabled.
We can test if `nested virtualization` is enabled with the command `grep -cw vmx /proc/cpuinfo`. If the result is greater zero, it is enabled, e.g.

_VM with enabled `nested virtualiztion`_
```
root@vm1:~# grep -cw vmx /proc/cpuinfo
4
```

The VM should have at least following resources:

| vCPUs | Memory | Storage |
|------|---------|---------|
|   2  |   4GB   |   20GB  |

e.g. we can create a vm in `GCP` with:

```bash
gcloud compute instances create centos9-vm \
    --zone=us-central1-a                   \
    --machine-type=n1-standard-1           \  # 2 vCPU, 4GB RAM
    --image-family=centos-stream-9         \
    --image-project=centos-cloud           \
    --boot-disk-size=20GB                  \
    --enable-nested-virtualization         \
    --provisioning-model=SPOT              \
    --instance-termination-action=STOP     \
    --max-run-duration=8h
```

2. Login into the vm and run the `install.sh` script

```sh
curl -fSs https://raw.githubusercontent.com/oxdeca/ctlabs/refs/heads/main/install/install.sh | bash
```

```bash
[root@vm1 ctlabs]# sh ./install.sh 
Starting CT Labs Deployment...
Configuring SELinux...                             [  OK  ]
Configuring system...                              [  OK  ]
Configuring tmux...                                [  OK  ]
Updating OS...                                     [  OK  ]
Installing packages...                             [  OK  ]
Configuring services...                            [  OK  ]
Cloning repositories...                            [  OK  ]
-----------------------------------------------------------------------------
WEB UI SECURITY
-----------------------------------------------------------------------------
Suggested secure password: /r********M
Enter password for 'ctlabs' user (leave empty to use suggested): 
Password set to: /rvUIviOCCD7yAtM
-----------------------------------------------------------------------------
Building container images...                       [  OK  ]
Performing final status checks...
Waiting for ctlabs-server to start... UP

=============================================================================
CT LABS DEPLOYMENT SUCCESSFUL
=============================================================================
Web UI is ready at: https://192.168.45.3:4567
Default user      : ctlabs
Password          : /r********M
=============================================================================
```

3. Enter a password for the `ctlabs` user used by the `WebUI` when prompted:

```
-----------------------------------------------------------------------------
WEB UI SECURITY
-----------------------------------------------------------------------------
Suggested secure password: z********H
Enter password for 'ctlabs' user (leave empty to use suggested): 
Password set to: z********H
-----------------------------------------------------------------------------
```

4. Login into the `WebUI`

- <https://${CENTOS9-VM-IP}:4567>

```
username: ctlabs
password: <was_set_during_installation>
```

---


Web Interface
-------------

The web interface provides a comprehensive management console for your labs.

### Lab Details View
![Lab Details Overview](docs/pics/screenshot-20260418-125613.png)

The Lab Details view is the central hub for managing a specific lab environment. It is organized into several functional tabs:

* __Overview__: Displays lab metadata (name, description) and a real-time table of **Exposed Ports (DNAT)**. It includes a form to add **Ad-hoc DNAT Rules** during runtime.
* __Automation__: Integrated editors for managing **Ansible playbooks**, **Terraform scripts**, and **Dockerfiles** associated with the lab.
* __Nodes__: A complete list of all nodes (VMs and Containers). Shows hardware specs (CPU, RAM), images, and provides quick actions for terminal access or editing.
* __Links__: Visual and form-based management of network connections between nodes and virtual switches.
* __Node Profiles__: Management of reusable templates for node configurations, allowing for consistent deployment of common node types.
* __Container Images__: View and manage the local container images available for use within the lab.

---


### Network Topologies

ctlabs provides automated, real-time visualization of your lab's network structure:

*   **Data Network Topology**: Visualizes the primary communication paths defined in your lab configuration.
*   **Management Network Topology**: Shows the isolated management plane, including the controller and management interfaces of all nodes.
*   **Interactive Viewer**: SVG-based maps with pan and zoom capabilities for exploring complex topologies.


![Network Topology](./docs/pics/screenshot-topology_data_01.png)

### Connections & Terminals

Every node in the lab is accessible via an integrated web terminal:

*   **WebSocket Powered**: Uses WebSockets for low-latency, bi-directional communication.
*   **Xterm.js**: A full-featured terminal emulator in your browser, supporting copy-paste, resizing, and standard ANSI sequences.
*   **Direct Console Access**: Connect directly to the shell of Podman containers. QEMU serial console is accesible via tmux session in the container.

![Web Terminal](./docs/pics/screenshot-terminal_02.png)

---

Network Architecture
--------------------

ctlabs automatically creates separate network planes to enhance lab isolation and simulate complex environments.

  * **Management Plane (mgmt):**
      * Used for out-of-band management tasks, such as initial provisioning via the Ansible controller.
      * Nodes with `type: controller` or explicitly assigned to the `mgmt` plane are placed here.
      * ctlabs automatically generates management links for all local nodes, isolated from other networks via a VRF.

  * **Data Plane (data):**
      * Simulates the primary communication network within the lab.
      * Links and interface mappings are defined within the lab's YAML configuration.
      * Most simulated services and user traffic run over this plane.

  * **Transit Plane (transit):**
      * Dedicated to carrying traffic between different network segments or remote sites.
      * Frequently used for VPN gateways (OpenVPN, WireGuard) and overlay network tunnels.
      * Isolated from management traffic to ensure realistic routing scenarios.

  * **Edge Plane (edge):**
      * Represents the boundary between the internal lab infrastructure and external networks (e.g., the public Internet).
      * Used for nodes requiring NAT, public IPs, or providing external access points.
      * Often serves as the termination point for cloud-integrated nodes (GCP, AWS).


### Modals & Editors

The UI employs various modals to provide focused editing experiences:

* **Node Editor**: Configure hardware resources, network interfaces, and startup images for individual nodes.
* **Link Editor**: Define connections, VLANs, and interface mappings between lab components.
* **Automation Editors**: Full-screen CodeMirror editors for Ansible, Terraform, and Dockerfiles with syntax highlighting.
* **Container Image Manager**: Tools to pull new images or create custom ones via Dockerfiles.
* **Vault Login**: Securely manage credentials for integrated services.


### Ansible Inventories

Inventories are dynamically generated based on the current lab state:

*   **Management Inventory**: Targets the `eth0` interface on the isolated management plane. Used for initial provisioning and out-of-band management.
*   **Data Inventory**: Targets the data plane interfaces (`eth1`, etc.). Used for configuring services that run over the simulated lab network.
