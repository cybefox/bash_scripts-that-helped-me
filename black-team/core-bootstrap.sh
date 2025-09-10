#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
set -x

# ==============================
# Black Team / APT-Sim Bootstrap (v2)
# Adds:
# 1) Optional build/start for Havoc & Mythic (asks user)
# 2) Optional VirtualBox + Win11 VM (asks user)
# 3) GoPhish: always install (latest release)
# ==============================

# ---- Config / Layout ----
ROOT_DIR="/opt/blackteam"
BIN_DIR="/usr/local/bin"
TMP_DIR="/tmp/blackteam-tmp"
mkdir -p "$ROOT_DIR" "$TMP_DIR"

CHISEL_VER="1.9.1"
LIGOLO_VER="0.6.3"
GOST_VER="2.11.5"
SLIVER_VER="1.5.39"

is_installed() { dpkg -s "$1" >/dev/null 2>&1; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }
ensure_link() {
  local target="$1" link="$2"
  if [[ -x "$target" ]]; then
    ln -sf "$target" "$link"
  else
    echo "[warn] not executable: $target"
  fi
}
apt_update_once() {
  if [[ ! -f /var/lib/apt/periodic/update-success-stamp ]] || \
     [[ $(find /var/lib/apt/periodic/update-success-stamp -mmin +60 -print -quit) ]]; then
    apt-get update -y
  fi
}

# ---- APT base tools ----
APT_PKGS=(
  nmap masscan dnsrecon dnsutils whois
  ldap-utils kerbrute
  bloodhound neo4j
  crackmapexec responder hashcat john smbmap evil-winrm
  mitm6 wireshark iodine
  git wget curl jq unzip xz-utils python3-venv python3-pip make ca-certificates
)

echo "[*] Installing APT packages (skipping already-installed)..."
apt_update_once
for pkg in "${APT_PKGS[@]}"; do
  if is_installed "$pkg"; then
    echo "[=] $pkg already installed, skipping."
  else
    apt-get install -y "$pkg"
  fi
done

# ---- pipx (Python app runner) ----
if ! has_cmd pipx; then
  su - "$SUDO_USER" -c "python3 -m pip install --user pipx"
  su - "$SUDO_USER" -c "python3 -m pipx ensurepath" || true
fi

# Ensure PATH for pipx binaries in this shell
export PATH="/home/${SUDO_USER:-$USER}/.local/bin:$PATH"

# ---- Python CLI (pipx) ----
PIPX_TOOLS=( impacket coercer bloodhound-python lsassy pypykatz )
echo "[*] Installing Python-based tools via pipx (user-scoped)..."
for tool in "${PIPX_TOOLS[@]}"; do
  if su - "$SUDO_USER" -c "pipx list" 2>/dev/null | grep -qiE "package $tool "; then
    echo "[=] pipx $tool already installed."
  else
    su - "$SUDO_USER" -c "pipx install $tool"
  fi
done

# Symlink pipx bins into /usr/local/bin
PIPX_BIN="/home/${SUDO_USER:-$USER}/.local/bin"
for exe in impacket-* bloodhound-python coercer lsassy pypykatz; do
  if [[ -x "$PIPX_BIN/$exe" ]]; then
    ln -sf "$PIPX_BIN/$exe" "$BIN_DIR/$exe"
  fi
done

# ==============================
# GROUP 1: Recon & Discovery
# ==============================
mkdir -p "$ROOT_DIR/recon"

# ==============================
# GROUP 2: Credentials & Auth
# ==============================
mkdir -p "$ROOT_DIR/creds"
if [[ ! -f "$ROOT_DIR/creds/gpp-decrypt.py" ]]; then
  wget -qO "$ROOT_DIR/creds/gpp-decrypt.py" https://raw.githubusercontent.com/t0thkr1s/gpp-decrypt/master/gpp-decrypt.py || true
  chmod +x "$ROOT_DIR/creds/gpp-decrypt.py" || true
  ensure_link "$ROOT_DIR/creds/gpp-decrypt.py" "$BIN_DIR/gpp-decrypt"
fi

# ==============================
# GROUP 3: Coercion & Relaying
# ==============================
mkdir -p "$ROOT_DIR/coerce"
pushd "$ROOT_DIR/coerce" >/dev/null

if [[ ! -d PetitPotam ]]; then
  git clone https://github.com/topotam/PetitPotam.git
fi
ensure_link "$ROOT_DIR/coerce/PetitPotam/petitpotam.py" "$BIN_DIR/petitpotam.py"

if [[ ! -d krbrelayx ]]; then
  git clone https://github.com/dirkjanm/krbrelayx.git
else
  pushd krbrelayx >/dev/null && git pull --ff-only || true; popd >/dev/null
fi
ensure_link "$ROOT_DIR/coerce/krbrelayx/printerbug.py" "$BIN_DIR/printerbug.py"
popd >/dev/null

# ==============================
# GROUP 4: Priv Esc & Lateral
# ==============================
mkdir -p "$ROOT_DIR/privmove"

# ==============================
# GROUP 5: Stealth / Tradecraft
# ==============================
mkdir -p "$ROOT_DIR/stealth"
pushd "$ROOT_DIR/stealth" >/dev/null

# dnscat2
if [[ ! -d dnscat2 ]]; then
  git clone https://github.com/iagox86/dnscat2.git
else
  pushd dnscat2 >/dev/null && git pull --ff-only || true; popd >/dev/null
fi

# chisel
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) CHISEL_ARCH="amd64" ;;
  aarch64|arm64) CHISEL_ARCH="arm64" ;;
  *) CHISEL_ARCH="amd64" ;;
esac
if [[ ! -x "$ROOT_DIR/stealth/chisel" ]]; then
  wget -O "$TMP_DIR/chisel.gz" "https://github.com/jpillora/chisel/releases/download/v${CHISEL_VER}/chisel_${CHISEL_VER}_linux_${CHISEL_ARCH}.gz"
  gunzip -f "$TMP_DIR/chisel.gz"
  mv "$TMP_DIR/chisel_${CHISEL_VER}_linux_${CHISEL_ARCH}" "$ROOT_DIR/stealth/chisel"
  chmod +x "$ROOT_DIR/stealth/chisel"
fi
ensure_link "$ROOT_DIR/stealth/chisel" "$BIN_DIR/chisel"

# ligolo-ng
if [[ ! -x "$ROOT_DIR/stealth/ligolo-proxy" || ! -x "$ROOT_DIR/stealth/ligolo-agent" ]]; then
  case "$ARCH" in
    x86_64|amd64) LIGOLO_ARCH="linux-amd64" ;;
    aarch64|arm64) LIGOLO_ARCH="linux-arm64" ;;
    *) LIGOLO_ARCH="linux-amd64" ;;
  esac
  wget -O "$TMP_DIR/ligolo.zip" "https://github.com/nicocha30/ligolo-ng/releases/download/v${LIGOLO_VER}/ligolo-ng_${LIGOLO_VER}_${LIGOLO_ARCH}.zip"
  unzip -o "$TMP_DIR/ligolo.zip" -d "$ROOT_DIR/stealth"
  chmod +x "$ROOT_DIR/stealth/ligolo-*"
fi
ensure_link "$ROOT_DIR/stealth/ligolo-proxy" "$BIN_DIR/ligolo-proxy"
ensure_link "$ROOT_DIR/stealth/ligolo-agent" "$BIN_DIR/ligolo-agent"

# gost
if [[ ! -x "$ROOT_DIR/stealth/gost" ]]; then
  case "$ARCH" in
    x86_64|amd64) GOST_ARCH="linux-amd64" ;;
    aarch64|arm64) GOST_ARCH="linux-arm64" ;;
    *) GOST_ARCH="linux-amd64" ;;
  esac
  wget -O "$TMP_DIR/gost.tar.gz" "https://github.com/go-gost/gost/releases/download/v${GOST_VER}/gost_${GOST_VER}_${GOST_ARCH}.tar.gz"
  tar -xzf "$TMP_DIR/gost.tar.gz" -c -f - 2>/dev/null || true
  tar -xzf "$TMP_DIR/gost.tar.gz" -C "$TMP_DIR"
  find "$TMP_DIR" -maxdepth 2 -type f -name gost -exec mv {} "$ROOT_DIR/stealth/gost" \; || true
  chmod +x "$ROOT_DIR/stealth/gost" || true
fi
ensure_link "$ROOT_DIR/stealth/gost" "$BIN_DIR/gost"
popd >/dev/null

# ==============================
# GROUP 6: C2 & Evasion
# ==============================
mkdir -p "$ROOT_DIR/c2"
pushd "$ROOT_DIR/c2" >/dev/null

# Sliver (prebuilt)
if [[ ! -x "$ROOT_DIR/c2/sliver-server" ]]; then
  case "$ARCH" in
    x86_64|amd64) SLIVER_ARCH="linux" ;;
    aarch64|arm64) SLIVER_ARCH="linux-arm64" ;;
    *) SLIVER_ARCH="linux" ;;
  esac
  wget -O "$TMP_DIR/sliver.zip" "https://github.com/BishopFox/sliver/releases/download/v${SLIVER_VER}/sliver-server_${SLIVER_ARCH}.zip" || true
  wget -O "$TMP_DIR/sliver-client.zip" "https://github.com/BishopFox/sliver/releases/download/v${SLIVER_VER}/sliver-client_${SLIVER_ARCH}.zip" || true
  if [[ -f "$TMP_DIR/sliver.zip" ]]; then unzip -o "$TMP_DIR/sliver.zip" -d "$ROOT_DIR/c2"; fi
  if [[ -f "$TMP_DIR/sliver-client.zip" ]]; then unzip -o "$TMP_DIR/sliver-client.zip" -d "$ROOT_DIR/c2"; fi
  chmod +x "$ROOT_DIR/c2/"sliver-* || true
fi
ensure_link "$ROOT_DIR/c2/sliver-server" "$BIN_DIR/sliver-server" || true
ensure_link "$ROOT_DIR/c2/sliver-client" "$BIN_DIR/sliver-client" || true

# Havoc (clone; optionally build)
if [[ ! -d Havoc ]]; then
  git clone https://github.com/HavocFramework/Havoc.git
else
  pushd Havoc >/dev/null && git pull --ff-only || true; popd >/dev/null
fi

# Mythic (clone; optionally install via docker)
if [[ ! -d mythic ]]; then
  git clone https://github.com/its-a-feature/Mythic.git mythic
else
  pushd mythic >/dev/null && git pull --ff-only || true; popd >/dev/null
fi

# Ask to build Havoc & Mythic
read -rp "Do you want to build Havoc now? (y/N): " BUILD_HAVOC
if [[ "${BUILD_HAVOC,,}" == "y" ]]; then
  apt_update_once
  apt-get install -y build-essential cmake clang golang nodejs npm yarnpkg mingw-w64 libssl-dev
  pushd Havoc >/dev/null
  # Typical build steps (may vary as upstream changes)
  make || true
  popd >/dev/null
fi

read -rp "Do you want to install & start Mythic (Docker-heavy)? (y/N): " BUILD_MYTHIC
if [[ "${BUILD_MYTHIC,,}" == "y" ]]; then
  apt_update_once
  apt-get install -y docker.io docker-compose-plugin
  systemctl enable --now docker
  pushd mythic >/dev/null
  # Install and start Mythic via mythic-cli (script in repo)
  if [[ -x ./mythic-cli ]]; then
    ./mythic-cli install || true
    ./mythic-cli start || true
  else
    # Fallback: typical start script
    ./start_mythic.sh || true
  fi
  popd >/dev/null
fi
popd >/dev/null

# ==============================
# GROUP 7: GUI / Viz / Reporting
# ==============================
mkdir -p "$ROOT_DIR/gui"
pushd "$ROOT_DIR/gui" >/dev/null

# GoPhish (install no matter what): latest release for linux 64-bit
if [[ ! -x "$ROOT_DIR/gui/gophish/gophish" ]]; then
  mkdir -p gophish
  # Get latest tag and download
  GOPHISH_TAG=$(curl -sSL https://api.github.com/repos/gophish/gophish/releases/latest | jq -r '.tag_name')
  GOPHISH_URL=$(curl -sSL https://api.github.com/repos/gophish/gophish/releases/latest | jq -r '.assets[].browser_download_url' | grep -i linux-64bit | head -n1)
  if [[ -n "${GOPHISH_URL}" ]]; then
    wget -O "$TMP_DIR/gophish.tar.gz" "$GOPHISH_URL"
    tar -xzf "$TMP_DIR/gophish.tar.gz" -C gophish --strip-components=1
    chmod +x gophish/gophish
    ensure_link "$ROOT_DIR/gui/gophish/gophish" "$BIN_DIR/gophish"
  else
    echo "[!] Could not determine GoPhish latest release URL automatically."
  fi
fi
popd >/dev/null

# ==============================
# Optional: VirtualBox + Windows 11 VM
# ==============================
read -rp "Do you want to install VirtualBox and scaffold a Windows 11 VM? (y/N): " INSTALL_VBOX
if [[ "${INSTALL_VBOX,,}" == "y" ]]; then
  apt_update_once
  apt-get install -y virtualbox virtualbox-dkms
  VM_NAME="Win11-RedTeam"
  VM_DIR="$ROOT_DIR/vms"
  mkdir -p "$VM_DIR"

  # Prompt for ISO path
  read -rp "Enter absolute path to Windows 11 ISO (or leave blank to skip VM creation): " WIN_ISO
  if [[ -n "${WIN_ISO}" && -f "${WIN_ISO}" ]]; then
    # Create VM (no unattended setup; user completes GUI install)
    VBoxManage createvm --name "$VM_NAME" --register
    VBoxManage modifyvm "$VM_NAME" --ostype Windows11_64 --memory 8192 --vram 128 --cpus 4 --ioapic on --boot1 dvd --nic1 nat
    VBoxManage createmedium disk --filename "$VM_DIR/${VM_NAME}.vdi" --size 81920 --format VDI
    VBoxManage storagectl "$VM_NAME" --name "SATA Controller" --add sata --controller IntelAhci
    VBoxManage storageattach "$VM_NAME" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$VM_DIR/${VM_NAME}.vdi"
    VBoxManage storageattach "$VM_NAME" --storagectl "SATA Controller" --port 1 --device 0 --type dvddrive --medium "$WIN_ISO"
    echo "[*] VM created. Start it with: VBoxManage startvm \"$VM_NAME\" --type gui"
  else
    echo "[i] Skipping VM creation (no ISO provided). VirtualBox installed."
  fi
fi

# ---- Clean up temp files ----
rm -rf "$TMP_DIR"

echo
echo "========= READY ========="
echo "Root tools dir: $ROOT_DIR"
echo "Binaries linked under: $BIN_DIR"
echo "Quick checks:"
echo "  which impacket-smbclient || true"
echo "  which bloodhound-python || true"
echo "  which mitm6 || true"
echo "  which responder || true"
echo "  which chisel || true"
echo "  which ligolo-proxy || true"
echo "  which gophish || true"
echo "=========================="
