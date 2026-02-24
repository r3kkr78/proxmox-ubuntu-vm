#!/usr/bin/env bash

# Headless Ubuntu 24.04 VM Creator
# Based on create-vm.sh — stripped of whiptail, driven by CLI args
# Run on the Proxmox host via SSH from Chuck.
#
# Usage:
#   bash create-vm-headless.sh --name my-vm [options]
#
# Options:
#   --name         VM hostname (required)
#   --cores        CPU cores (default: 4)
#   --memory       RAM in MiB (default: 4096)
#   --disk         Disk size (default: 20G)
#   --storage      Storage pool (default: valhalla)
#   --bridge       Network bridge (default: vmbr0)
#   --vlan         VLAN tag (default: 90)
#   --machine      Machine type: i440fx or q35 (default: i440fx)
#   --cpu          CPU type: kvm64 or host (default: kvm64)
#   --gpu          GPU PCI address for passthrough, e.g. 01:00.0 (default: none)
#   --no-start     Don't start VM after creation
#   --tailscale    Tailscale auth key for auto-install (optional)
#   --vmid         Override auto-assigned VMID (optional)

set -e

# ── Defaults ────────────────────────────────────────────────────────────────
HN=""
CORE_COUNT=4
RAM_SIZE=4096
DISK_SIZE="20G"
STORAGE="valhalla"
BRG="vmbr0"
VLAN_TAG="90"
MACHINE_TYPE="i440fx"
CPU_TYPE_ARG="kvm64"
GPU_DEVICE=""
START_VM="yes"
TAILSCALE_KEY=""
VMID_OVERRIDE=""

# ── Parse args ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)       HN="$2";           shift 2 ;;
    --cores)      CORE_COUNT="$2";   shift 2 ;;
    --memory)     RAM_SIZE="$2";     shift 2 ;;
    --disk)       DISK_SIZE="$2";    shift 2 ;;
    --storage)    STORAGE="$2";      shift 2 ;;
    --bridge)     BRG="$2";          shift 2 ;;
    --vlan)       VLAN_TAG="$2";     shift 2 ;;
    --machine)    MACHINE_TYPE="$2"; shift 2 ;;
    --cpu)        CPU_TYPE_ARG="$2"; shift 2 ;;
    --gpu)        GPU_DEVICE="$2";   shift 2 ;;
    --no-start)   START_VM="no";     shift   ;;
    --tailscale)  TAILSCALE_KEY="$2"; shift 2 ;;
    --vmid)       VMID_OVERRIDE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$HN" ]; then
  echo "Error: --name is required"
  echo "Usage: $0 --name my-vm [--cores 4] [--memory 4096] [--disk 20G] ..."
  exit 1
fi

# ── Helpers ──────────────────────────────────────────────────────────────────
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')

function msg_info()  { echo "  ⏳ $1"; }
function msg_ok()    { echo "  ✅ $1"; }
function msg_error() { echo "  ❌ $1"; exit 1; }

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1)); continue
    fi
    if lvs --noheadings -o lv_name 2>/dev/null | grep -qE "(^|[-_])${try_id}($|[-_])"; then
      try_id=$((try_id + 1)); continue
    fi
    break
  done
  echo "$try_id"
}

function cleanup_vmid() {
  if qm status $VMID &>/dev/null; then
    qm stop $VMID &>/dev/null || true
    qm destroy $VMID &>/dev/null || true
    echo "  🧹 Cleaned up VM $VMID"
  fi
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null

trap 'popd >/dev/null; rm -rf $TEMP_DIR' EXIT
trap 'echo "Error on line $LINENO — cleaning up..."; cleanup_vmid; exit 1' ERR

# ── Checks ───────────────────────────────────────────────────────────────────
if [[ "$(id -u)" -ne 0 ]]; then
  msg_error "Must run as root"
fi

if ! pveversion | grep -Eq "pve-manager/([8]\.[1-9]|[9-9]\.[0-9]+)(\.[0-9]+)*"; then
  msg_error "Requires Proxmox VE 8.1 or later"
fi

if [ "$(dpkg --print-architecture)" != "amd64" ]; then
  msg_error "Only supported on amd64"
fi

# ── VMID ─────────────────────────────────────────────────────────────────────
if [ -n "$VMID_OVERRIDE" ]; then
  VMID="$VMID_OVERRIDE"
  if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
    msg_error "VMID $VMID is already in use"
  fi
else
  VMID=$(get_valid_nextid)
fi

# ── Machine / CPU flags ───────────────────────────────────────────────────────
if [ "$MACHINE_TYPE" = "q35" ]; then
  MACHINE=" -machine q35"
  FORMAT=""
else
  MACHINE=""
  FORMAT=",efitype=4m"
fi

if [ "$CPU_TYPE_ARG" = "host" ]; then
  CPU_TYPE=" -cpu host"
else
  CPU_TYPE=""
fi

VLAN=",tag=${VLAN_TAG}"
MAC="$GEN_MAC"
THIN="discard=on,ssd=1,"
DISK_CACHE=""

# ── Print config ──────────────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   Headless Ubuntu 24.04 VM Creator  ⚡   ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""
echo "  VMID:      $VMID"
echo "  Hostname:  $HN"
echo "  CPU:       $CORE_COUNT cores ($CPU_TYPE_ARG)"
echo "  RAM:       ${RAM_SIZE}MiB"
echo "  Disk:      $DISK_SIZE on $STORAGE"
echo "  Network:   $BRG VLAN $VLAN_TAG | MAC $MAC"
echo "  Machine:   $MACHINE_TYPE"
[ -n "$GPU_DEVICE" ] && echo "  GPU:       $GPU_DEVICE (passthrough)"
echo "  Start:     $START_VM"
[ -n "$TAILSCALE_KEY" ] && echo "  Tailscale: auto-install"
echo ""

# ── Validate storage ──────────────────────────────────────────────────────────
msg_info "Validating storage pool '$STORAGE'"
if ! pvesm status -storage "$STORAGE" &>/dev/null; then
  msg_error "Storage pool '$STORAGE' not found. Available: $(pvesm status -content images | awk 'NR>1 {print $1}' | tr '\n' ' ')"
fi
msg_ok "Storage '$STORAGE' OK"

# ── Detect storage type for disk format ───────────────────────────────────────
STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
  nfs | dir | cifs)
    DISK_EXT=".qcow2"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format qcow2"
    THIN=""
    ;;
  btrfs)
    DISK_EXT=".raw"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format raw"
    FORMAT=",efitype=4m"
    THIN=""
    ;;
  *)
    DISK_EXT=""
    DISK_REF=""
    DISK_IMPORT=""
    ;;
esac

for i in {0,1}; do
  eval DISK${i}="vm-${VMID}-disk-${i}${DISK_EXT:-}"
  eval DISK${i}_REF="${STORAGE}:${DISK_REF:-}vm-${VMID}-disk-${i}${DISK_EXT:-}"
done

# ── Download Ubuntu 24.04 cloud image ────────────────────────────────────────
URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
FILE=$(basename "$URL")

msg_info "Downloading Ubuntu 24.04 cloud image"
curl -f#SL -o "$FILE" "$URL"
echo -en "\e[1A\e[0K"
msg_ok "Downloaded $FILE"

# ── Create VM ─────────────────────────────────────────────────────────────────
msg_info "Creating VM $VMID ($HN)"
qm create $VMID \
  -agent 1 \
  ${MACHINE} \
  -tablet 0 \
  -localtime 1 \
  -bios ovmf \
  ${CPU_TYPE} \
  -cores $CORE_COUNT \
  -memory $RAM_SIZE \
  -name $HN \
  -tags proxmox-ubuntu,chuck-created \
  -net0 virtio,bridge=$BRG,macaddr=$MAC${VLAN} \
  -onboot 1 \
  -ostype l26 \
  -scsihw virtio-scsi-pci

pvesm alloc $STORAGE $VMID $DISK0 4M 1>/dev/null
qm importdisk $VMID "$FILE" $STORAGE ${DISK_IMPORT:-} 1>/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
  -ide2 ${STORAGE}:cloudinit \
  -boot order=scsi0 \
  -serial0 socket >/dev/null

qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null
msg_ok "Created VM $VMID"

# ── GPU passthrough ───────────────────────────────────────────────────────────
if [ -n "$GPU_DEVICE" ]; then
  msg_info "Configuring GPU passthrough ($GPU_DEVICE)"
  qm set $VMID -hostpci0 $GPU_DEVICE,pcie=1,rombar=1,x-vga=1 >/dev/null
  msg_ok "GPU passthrough configured"
fi

# ── Description ───────────────────────────────────────────────────────────────
CREATED_DATE=$(date +%Y-%m-%d)
qm set "$VMID" -description "Created by Chuck ⚡ ${CREATED_DATE} | ${HN} | ${CORE_COUNT}c/${RAM_SIZE}MB/${DISK_SIZE}" >/dev/null

# ── Start VM ──────────────────────────────────────────────────────────────────
if [ "$START_VM" = "yes" ]; then
  msg_info "Starting VM $VMID"
  qm start $VMID
  msg_ok "VM $VMID started"
fi

# ── Tailscale auto-install ────────────────────────────────────────────────────
if [ -n "$TAILSCALE_KEY" ]; then
  echo ""
  msg_info "Waiting for VM to boot and get an IP (up to 5 min)..."
  IP=""
  for i in $(seq 1 30); do
    IP=$(qm guest cmd $VMID network-get-interfaces 2>/dev/null | \
      python3 -c "
import sys, json
try:
    ifaces = json.load(sys.stdin)
    for iface in ifaces:
        if iface.get('name','') not in ('lo',''):
            for addr in iface.get('ip-addresses',[]):
                if addr.get('ip-address-type') == 'ipv4':
                    ip = addr['ip-address']
                    if not ip.startswith('127.'):
                        print(ip)
                        raise SystemExit
except: pass
" 2>/dev/null)
    if [ -n "$IP" ]; then
      msg_ok "VM IP: $IP"
      break
    fi
    echo "    Waiting for guest agent... ($i/30)"
    sleep 10
  done

  if [ -n "$IP" ]; then
    msg_info "Installing Tailscale on $IP"
    ssh -i /root/.ssh/authorized_keys \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=30 \
        -o BatchMode=yes \
        root@$IP \
        "curl -fsSL https://tailscale.com/install.sh | sh && \
         tailscale up --authkey=${TAILSCALE_KEY} --hostname=${HN} --accept-routes" \
      && msg_ok "Tailscale installed and connected on $HN" \
      || echo "  ⚠️  Tailscale install failed — SSH to $IP and run manually"
  else
    echo "  ⚠️  Could not get VM IP — Tailscale install skipped"
    echo "       SSH into the VM manually and run:"
    echo "       curl -fsSL https://tailscale.com/install.sh | sh"
    echo "       tailscale up --authkey=<key> --hostname=${HN} --accept-routes"
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║              VM Ready ✅                  ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""
echo "  VMID:     $VMID"
echo "  Name:     $HN"
[ -n "$IP" ] && echo "  IP:       $IP"
echo ""
echo "  Cloud-Init still needs:"
echo "    qm set $VMID --ciuser danny --cipassword 'yourpass'"
echo "    qm set $VMID --sshkeys /path/to/pubkey"
echo "    qm set $VMID --ipconfig0 ip=dhcp"
echo "    qm reboot $VMID   # apply cloud-init"
echo ""
echo "  Post-setup script:"
echo "    curl -fsSL https://raw.githubusercontent.com/r3kkr78/proxmox-ubuntu-vm/main/setup/setup.sh | bash"
echo ""
