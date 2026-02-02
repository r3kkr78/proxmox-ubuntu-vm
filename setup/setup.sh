#!/usr/bin/env bash
#
# Ubuntu 24.04 VM Post-Installation Setup Script
# Modern ANSI box-drawing UI with no external dependencies
#

set -e

# ─────────────────────────────────────────────────────────────────────────────
# Colors and Formatting
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# ─────────────────────────────────────────────────────────────────────────────
# Status Message Functions
# ─────────────────────────────────────────────────────────────────────────────

msg_info() {
    echo -e "${BLUE}[*]${NC} $1"
}

msg_ok() {
    echo -e "${GREEN}[✓]${NC} $1"
}

msg_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

msg_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# ─────────────────────────────────────────────────────────────────────────────
# UI Functions
# ─────────────────────────────────────────────────────────────────────────────

clear_screen() {
    clear
}

draw_header() {
    echo -e "${CYAN}"
    echo "╭──────────────────────────────────────────╮"
    echo "│         Ubuntu 24.04 VM Setup            │"
    echo "│                                          │"
    echo "│   Post-installation package installer    │"
    echo "╰──────────────────────────────────────────╯"
    echo -e "${NC}"
}

draw_menu() {
    echo ""
    echo -e "  ${BOLD}[1]${NC}  Base Tools"
    echo -e "  ${BOLD}[2]${NC}  Docker & Compose"
    echo -e "  ${BOLD}[3]${NC}  GPU Drivers"
    echo -e "  ${BOLD}[4]${NC}  Dev Tools"
    echo -e "  ${BOLD}[5]${NC}  Modern CLI Tools"
    echo -e "  ${BOLD}[6]${NC}  Tailscale VPN"
    echo -e "  ${BOLD}[7]${NC}  Everything"
    echo ""
    echo -e "  ${DIM}[0]${NC}  Exit"
    echo ""
    echo -e "${DIM}────────────────────────────────────────────${NC}"
}

draw_section() {
    local title="$1"
    echo ""
    echo -e "${CYAN}┌─ ${BOLD}$title${NC}${CYAN} ─────────────────────────────────${NC}"
    echo ""
}

draw_section_end() {
    echo ""
    echo -e "${CYAN}└────────────────────────────────────────────${NC}"
    echo ""
}

press_enter() {
    echo ""
    read -rp "  Press Enter to continue..." </dev/tty
}

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight Checks
# ─────────────────────────────────────────────────────────────────────────────

check_root() {
    if [[ $EUID -eq 0 ]]; then
        msg_error "Do not run this script as root!"
        msg_warn "The script will prompt for sudo when needed."
        exit 1
    fi
}

check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        msg_error "Cannot detect OS. This script is designed for Ubuntu."
        exit 1
    fi

    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        msg_warn "This script is designed for Ubuntu. Detected: $ID"
        read -rp "  Continue anyway? (y/N): " continue_anyway </dev/tty
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
}

wait_for_apt() {
    # Wait for apt locks to be released (unattended-upgrades on fresh boot)
    local max_wait=60
    local waited=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
        if [[ $waited -eq 0 ]]; then
            msg_warn "Waiting for apt locks (background updates may be running)..."
        fi
        sleep 2
        waited=$((waited + 2))
        if [[ $waited -ge $max_wait ]]; then
            msg_error "Timed out waiting for apt locks after ${max_wait}s"
            msg_warn "Try: sudo killall apt apt-get unattended-upgr"
            return 1
        fi
    done
    if [[ $waited -gt 0 ]]; then
        msg_ok "Apt locks released"
    fi
}

ensure_prerequisites() {
    # Ensure curl, gpg, ca-certificates exist (needed for Docker, Dev Tools, etc.)
    local missing=()
    command -v curl >/dev/null || missing+=("curl")
    command -v gpg >/dev/null || missing+=("gnupg")
    [[ -d /etc/ssl/certs ]] || missing+=("ca-certificates")

    if [[ ${#missing[@]} -gt 0 ]]; then
        msg_info "Installing prerequisites: ${missing[*]}"
        wait_for_apt
        sudo apt update -qq
        sudo apt install -y "${missing[@]}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Installation Functions
# ─────────────────────────────────────────────────────────────────────────────

install_base_tools() {
    draw_section "Base Tools"

    wait_for_apt
    msg_info "Updating package lists..."
    sudo apt update

    msg_info "Upgrading existing packages..."
    sudo apt upgrade -y

    msg_info "Installing base tools..."
    sudo apt install -y \
        git vim nano curl wget jq btop ncdu tree unzip zip p7zip-full \
        net-tools dnsutils nfs-common rsync screen tmux \
        build-essential ca-certificates gnupg lsb-release

    msg_ok "Base tools installed successfully"
    draw_section_end
}

install_docker() {
    draw_section "Docker & Compose"

    ensure_prerequisites

    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        msg_warn "Docker is already installed"
        docker --version
        read -rp "  Reinstall? (y/N): " reinstall </dev/tty
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            draw_section_end
            return
        fi
    fi

    msg_info "Adding Docker GPG key..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    msg_info "Adding Docker repository..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    msg_info "Installing Docker..."
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    msg_info "Enabling Docker service..."
    sudo systemctl enable --now docker

    msg_info "Adding user to docker group..."
    sudo usermod -aG docker "$USER"

    msg_ok "Docker installed successfully"
    msg_warn "Log out and back in for docker group changes to take effect"

    # Portainer prompt
    echo ""
    read -rp "  Install Portainer web UI? (y/N): " install_portainer </dev/tty
    if [[ "$install_portainer" =~ ^[Yy]$ ]]; then
        msg_info "Installing Portainer..."
        sudo docker volume create portainer_data
        sudo docker run -d -p 9443:9443 --name portainer --restart=always \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v portainer_data:/data \
            portainer/portainer-ce:latest

        local ip_addr
        ip_addr=$(hostname -I | awk '{print $1}')
        msg_ok "Portainer installed"
        echo -e "  ${CYAN}Access Portainer at:${NC} https://${ip_addr}:9443"
    fi

    draw_section_end
}

install_gpu_drivers() {
    draw_section "GPU Drivers"

    msg_info "Detecting GPU..."
    local gpu_type
    gpu_type=$(lspci | grep -E "(VGA|3D|Display)" | head -1 || true)

    if [[ -z "$gpu_type" ]]; then
        msg_warn "No GPU detected"
        draw_section_end
        return
    fi

    echo -e "  ${DIM}Detected:${NC} $gpu_type"
    echo ""

    if echo "$gpu_type" | grep -qi nvidia; then
        # NVIDIA GPU
        msg_info "Installing NVIDIA drivers..."
        sudo apt install -y ubuntu-drivers-common
        sudo ubuntu-drivers autoinstall

        msg_ok "NVIDIA drivers installed"

        read -rp "  Install CUDA toolkit? (y/N): " install_cuda </dev/tty
        if [[ "$install_cuda" =~ ^[Yy]$ ]]; then
            msg_info "Installing CUDA toolkit..."
            sudo apt install -y nvidia-cuda-toolkit
            msg_ok "CUDA toolkit installed"
        fi

    elif echo "$gpu_type" | grep -qi intel; then
        # Intel GPU
        msg_info "Installing Intel GPU drivers..."
        sudo apt install -y va-driver-all intel-media-va-driver-non-free vainfo intel-gpu-tools
        msg_ok "Intel GPU drivers installed"

    elif echo "$gpu_type" | grep -qi "amd\|radeon"; then
        # AMD GPU
        msg_info "Installing AMD GPU drivers..."
        sudo apt install -y mesa-va-drivers va-driver-all vainfo radeontop
        msg_ok "AMD GPU drivers installed"

    else
        msg_warn "Unknown GPU type - no drivers installed"
    fi

    draw_section_end
}

install_dev_tools() {
    draw_section "Dev Tools"

    ensure_prerequisites

    # Node.js LTS
    msg_info "Installing Node.js LTS..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt install -y nodejs
    msg_ok "Node.js $(node --version) installed"

    # uv (Python package manager)
    msg_info "Installing uv (Python package manager)..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    msg_ok "uv installed"

    # GitHub CLI
    msg_info "Installing GitHub CLI..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
        sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
        sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install -y gh
    msg_ok "GitHub CLI installed"

    # VSCode
    msg_info "Installing VS Code..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
    sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
    echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
        sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
    sudo apt update
    sudo apt install -y code
    rm -f /tmp/packages.microsoft.gpg
    msg_ok "VS Code installed"

    # Database clients
    msg_info "Installing database clients..."
    sudo apt install -y mysql-client postgresql-client redis-tools
    msg_ok "Database clients installed"

    draw_section_end
}

install_modern_cli() {
    draw_section "Modern CLI Tools"

    # btop
    msg_info "Installing btop..."
    sudo apt install -y btop
    msg_ok "btop installed"

    # ripgrep
    msg_info "Installing ripgrep..."
    sudo apt install -y ripgrep
    msg_ok "ripgrep installed"

    # fd-find
    msg_info "Installing fd-find..."
    sudo apt install -y fd-find
    if ! grep -q "alias fd=fdfind" ~/.bashrc 2>/dev/null; then
        echo 'alias fd=fdfind' >> ~/.bashrc
    fi
    msg_ok "fd-find installed (aliased as 'fd')"

    # bat
    msg_info "Installing bat..."
    sudo apt install -y bat
    if ! grep -q "alias bat=batcat" ~/.bashrc 2>/dev/null; then
        echo 'alias bat=batcat' >> ~/.bashrc
    fi
    msg_ok "bat installed (aliased as 'bat')"

    # fzf
    msg_info "Installing fzf..."
    sudo apt install -y fzf
    msg_ok "fzf installed"

    # starship prompt
    msg_info "Installing starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
    if ! grep -q 'eval "$(starship init bash)"' ~/.bashrc 2>/dev/null; then
        echo 'eval "$(starship init bash)"' >> ~/.bashrc
    fi
    msg_ok "starship installed"

    msg_warn "Run 'source ~/.bashrc' or open a new terminal to apply changes"

    draw_section_end
}

install_tailscale() {
    draw_section "Tailscale VPN"

    if command -v tailscale &> /dev/null; then
        msg_warn "Tailscale is already installed"
        tailscale version
    else
        msg_info "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
        msg_ok "Tailscale installed"
    fi

    echo ""
    echo -e "  ${CYAN}To connect to your tailnet, run:${NC}"
    echo -e "    ${BOLD}sudo tailscale up${NC}"
    echo ""
    echo -e "  ${DIM}Then visit the URL shown to authenticate.${NC}"

    draw_section_end
}

install_everything() {
    draw_section "Installing Everything"
    echo ""
    msg_info "This will install all options (1-6)"
    read -rp "  Continue? (y/N): " confirm </dev/tty
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        draw_section_end
        return
    fi
    draw_section_end

    install_base_tools
    install_docker
    install_gpu_drivers
    install_dev_tools
    install_modern_cli
    install_tailscale

    echo ""
    msg_ok "All components installed successfully!"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Loop
# ─────────────────────────────────────────────────────────────────────────────

main() {
    check_root
    check_ubuntu

    while true; do
        clear_screen
        draw_header
        draw_menu

        read -rp "  Select an option: " choice </dev/tty

        case $choice in
            1)
                install_base_tools
                press_enter
                ;;
            2)
                install_docker
                press_enter
                ;;
            3)
                install_gpu_drivers
                press_enter
                ;;
            4)
                install_dev_tools
                press_enter
                ;;
            5)
                install_modern_cli
                press_enter
                ;;
            6)
                install_tailscale
                press_enter
                ;;
            7)
                install_everything
                press_enter
                ;;
            0|q|Q)
                echo ""
                msg_ok "Goodbye!"
                echo ""
                exit 0
                ;;
            *)
                msg_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Run main function
main "$@"
