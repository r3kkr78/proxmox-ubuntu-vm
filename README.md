# Proxmox Ubuntu VM

Create Ubuntu 24.04 LTS virtual machines on Proxmox VE with optional GPU passthrough and a modern post-installation setup utility.

## Quick Start

**On your Proxmox host:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/r3kkr78/proxmox-ubuntu-vm/main/vm/create-vm.sh)
```

**Inside the VM after first boot:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/r3kkr78/proxmox-ubuntu-vm/main/setup/setup.sh)
```

## Features

### VM Creation Script
- Ubuntu 24.04 LTS cloud image with UEFI boot
- Cloud-init support for user/password configuration
- GPU passthrough configuration (NVIDIA, Intel, AMD)
- Automatic storage pool detection
- Default and advanced configuration modes
- Whiptail-based interactive UI

### Setup Script
- Modern terminal UI with ANSI box-drawing
- Modular installation (pick what you need)
- Auto-detection for GPU driver selection
- Handles apt locks from background updates
- No external dependencies

## Requirements

### Proxmox Host
- Proxmox VE 8.1 or later
- AMD64 architecture
- Storage pool with "Disk image" content type enabled
- Root access (run from Proxmox shell, not SSH)

### For GPU Passthrough (Optional)
- IOMMU enabled in BIOS (VT-d for Intel, AMD-Vi for AMD)
- Kernel parameter configured: `intel_iommu=on` or `amd_iommu=on`
- GPU not in use by Proxmox host

## Installation

### Method 1: Direct Execution (Recommended)

No download required. Run directly from GitHub:

**VM Creation (on Proxmox host):**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/r3kkr78/proxmox-ubuntu-vm/main/vm/create-vm.sh)
```

**Setup Script (inside VM):**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/r3kkr78/proxmox-ubuntu-vm/main/setup/setup.sh)
```

### Method 2: Clone Repository

Download and run locally:

```bash
git clone https://github.com/r3kkr78/proxmox-ubuntu-vm.git
cd proxmox-ubuntu-vm

# Make scripts executable
chmod +x vm/create-vm.sh setup/setup.sh

# Run VM creation (on Proxmox host)
./vm/create-vm.sh

# Run setup (inside VM)
./setup/setup.sh
```

## Usage

### Creating a VM

1. Open the Proxmox web UI and click on your node
2. Click **Shell** to open a root terminal (avoid SSH for variable detection)
3. Run the VM creation script
4. Choose **Default Settings** or **Advanced** when prompted
5. Select your storage pool
6. Optionally configure GPU passthrough
7. Wait for the VM to be created and started

**After VM Creation:**
1. Select the new VM in Proxmox
2. Go to **Cloud-Init** tab
3. Set your **User** and **Password**
4. Click **Regenerate Image**
5. Reboot the VM if it's already running

### Post-Installation Setup

1. Log into your VM via console or SSH
2. Run the setup script as a **regular user** (not root)
3. Select options from the menu to install packages
4. The script will prompt for sudo password when needed

## Configuration Options

### VM Creation Defaults

| Setting | Default Value |
|---------|---------------|
| Hostname | `ubuntu-vm` |
| CPU Cores | 4 |
| RAM | 4096 MB |
| Disk Size | 10 GB |
| Network Bridge | `vmbr0` |
| Machine Type | i440fx |
| Start on Boot | Yes |

All settings can be customized in Advanced mode.

### Setup Script Menu

| Option | Packages Installed |
|--------|-------------------|
| **1. Base Tools** | git, vim, nano, curl, wget, jq, btop, ncdu, tree, tmux, screen, build-essential |
| **2. Docker & Compose** | Docker CE, Compose plugin, optional Portainer |
| **3. GPU Drivers** | Auto-detects and installs NVIDIA, Intel, or AMD drivers |
| **4. Dev Tools** | Node.js LTS, uv (Python), GitHub CLI, VS Code, database clients |
| **5. Modern CLI** | ripgrep, fd, bat, fzf, starship prompt |
| **6. Tailscale** | Tailscale VPN client |
| **7. Everything** | All of the above |

## GPU Passthrough

### Prerequisites

1. **Enable IOMMU in BIOS**
   - Intel: Enable VT-d
   - AMD: Enable AMD-Vi / IOMMU

2. **Configure Kernel Parameters**

   Edit `/etc/default/grub` on Proxmox host:
   ```bash
   # Intel
   GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on"

   # AMD
   GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on"
   ```

   Then run:
   ```bash
   update-grub
   reboot
   ```

3. **Verify IOMMU is Active**
   ```bash
   dmesg | grep -i iommu
   ```

### Using GPU Passthrough

When running the VM creation script:
1. Select **Yes** when asked about GPU passthrough
2. The script will list available GPU devices
3. Enter the number of the GPU you want to pass through
4. The VM will be configured with the GPU attached

## Troubleshooting

### VM Creation

**"No storage pools detected"**
- Ensure you have storage configured in Datacenter > Storage
- The storage must have "Disk image" in its Content settings

**GPU not listed for passthrough**
- Verify IOMMU is enabled: `dmesg | grep -i iommu`
- Check if the GPU is bound to vfio-pci driver
- Ensure the GPU isn't being used by the Proxmox display

**VM fails to start after GPU passthrough**
- Try using q35 machine type in Advanced settings
- Check if ROM bar is needed for your GPU
- Verify IOMMU groups aren't splitting the GPU

### Setup Script

**"Do not run this script as root"**
- Run as a regular user: `./setup.sh`
- The script uses sudo internally when needed

**"Waiting for apt locks"**
- Normal on fresh boot; unattended-upgrades is running
- Wait for the message to clear (up to 60 seconds)
- If stuck: `sudo killall apt apt-get unattended-upgr`

**Docker permission denied after install**
- Log out and back in for group membership to apply
- Or run: `newgrp docker`

**Package installation fails**
- Check internet connectivity: `ping google.com`
- Try manually: `sudo apt update`

## License

MIT License - See [LICENSE](LICENSE) for details.
