# ctlabs

ctlabs is a tool designed to streamline the creation of repeatable lab environments. 
It automates the setup and configuration of virtual machines and containers, allowing us to quickly and consistently provision environments for learning, testing, and development.

**Key Features:**

* Automated lab setup using YAML configuration files.
* Support for virtual machines (using QEMU/KVM) and containers (using Podman).
* Integration with Ansible for configuration management.
* Flexibility to define custom lab topologies and configurations.

**Use Cases:**

* Preparing for Linux certifications (LPIC, RHCSA).
* Testing network configurations and protocols.
* Learning specific technologies like Kubernetes or Docker.
* Creating isolated environments for software development and testing.
* ...

## Manual Installation

### Prerequisites

* CentOS 9

**System Dependencies:**

```bash
sh# dnf install git ruby graphviz ipvsadm make podman-docker qemu-img cloud-utils-growpart python3-pip tmux vim
sh# gem install webrick sinatra rackup
```

_optional_
```bash
sh# dnf install epel-release htop irb wireshark-cli tcpdump perf bpftrace kernel-modules-extra-$(uname -r)
```

## Automated Installation

For faster and more consistent setup, you can use Terraform to automate the creation of a CentOS 9 virtual machine.
* [Terraform configuration](https://github.com/oxdeca/ctlabs-terraform/tree/main/01_lpic2/gcp): 
	* This Terraform configuration creates a CentOS 9 VM on Google Cloud Platform.
* [Installation shell script](https://github.com/oxdeca/ctlabs-terraform/blob/main/01_lpic2/ppvm.sh): 
	* This shell script installs all the necessary packages and dependencies on the VM. (used by the terraform code)

## Container Images

ctlabs relies on a set of pre-built container images for various lab components. 
The make command in the images directory builds the necessary container images using Podman.
This process may take some time.

```bash
git clone https://github.com/oxdeca/ctlabs
cd ctlabs/images && make
cd -
```

## Using ctlabs

Clone the `ctlabs-ansible` repository which contains all the ansible playbooks/roles that are used to setup lab environments.

```bash
git clone https://github.com/oxdeca/ctlabs-ansible
```

**Run ctlabs:**

This command uses the `ctlabs.rb` script to create a lab environment defined in the `lpic208.yml` file.

```bash
cd ctlabs/ctlabs
./ctlabs.rb -c ../labs/lpic2/lpic208.yml
```

![img](./lab_setup.gif)
