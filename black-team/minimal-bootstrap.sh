#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
set -x

# ==============================
# Black Team / APT-Sim Bootstrap
# Tested on Kali (Debian-based)
# ==============================

# ---- Config / Layout ----
ROOT_DIR="/opt/blackteam"
BIN_DIR="/usr/local/bin"
TMP_DIR="/tmp/blackteam-tmp"
mkdir -p "$ROOT_DIR" "$TMP_DIR"

# Versions for direct-download binaries (adjust if needed)
CHISEL_VER="1.9.1"
LIGOLO_VER="0.6.3"
GOST_VER="2.11.5"
SLIVER_VER="1.5.39"   # binary convenience; you can update later

# ---- Helpers ----
is_installed() { dpkg -s "$1" >/dev/null 2>&1; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }
ensure_link() {
  # ensure_link <target> <symlink>
  local target="$1" link="$2"
  if [[ -x "$target" ]]; then
    sudo ln -sf "$target" "$link"
  else
    echo "[warn] not executable: $target"
  fi
}
ensure_path_msg='
If you installed pipx for the first time, you may need to re-login OR:
  export PATH="$HOME/.local/bin:$PATH"
'

apt_update_once() {
  if [[ ! -f /var/lib/apt/periodic/update-success-stamp ]] || \
     [[ $(find /var/lib/apt/periodic/update-success-stamp -mmin +60 -print -quit) ]]; then
    sudo apt-get update -y
  fi
}

# ---- APT base tools ----
APT_PKGS=(
  # Recon & Discovery
  nmap masscan dnsrecon dnsutils whois
  # LDAP / Kerberos / AD helpers
  ldap-utils kerbrute
  # BloodHound GUI + Neo4j
  bloodhound neo4j
  # Creds & Auth
  crackmapexec responder hashcat john smbmap evil-winrm
  # mitm6, wireshark, iodine (tunneling)
  mitm6 wireshark iodine
  # Build/utility
  git wget curl jq unzip xz-utils python3-venv python3-pip
)

echo "[*] Installing APT packages (skipping already-installed)..."
apt_update_once
for pkg in "${APT_PKGS[@]}"; do
  if is_installed "$pkg"; then
    echo "[=] $pkg already installed, skipping."
  else
    sudo apt-get install -y "$pkg"
  fi
done

# ---- pipx (Python app runner) ----
if ! has_cmd pipx; then
  python3 -m pip install --user pipx
  python3 -m pipx ensurepath || true
  echo "$ensure_path_msg"
fi

# Ensure pipx works with sudo (we’ll call pipx as the current user)
if ! has_cmd pipx; then
  echo "[!] pipx not on PATH yet. Exporting PATH for this session."
  export PATH="$HOME/.local/bin:$PATH"
fi

# ---- Python CLI (pipx) ----
PIPX_TOOLS=(
  impacket
  coercer
  bloodhound-python
  lsassy
  pypykatz
)

echo "[*] Installing Python-based tools via pipx..."
for tool in "${PIPX_TOOLS[@]}"; do
  if pipx list 2>/dev/null | grep -qiE "package $tool "; then
    echo "[=] pipx $tool already installed."
  else
    pipx install "$tool"
  fi
done

# Symlink pipx binaries into /usr/local/bin (so root shells find them)
PIPX_BIN="$HOME/.local/bin"
for exe in impacket-* bloodhound-python coercer lsassy pypykatz; do
  if [[ -x "$PIPX_BIN/$exe" ]]; then
    sudo ln -sf "$PIPX_BIN/$exe" "$BIN_DIR/$exe"
  fi
done

# ==============================
# GROUP 1: Recon & Discovery
# ==============================
mkdir -p "$ROOT_DIR/recon"
pushd "$ROOT_DIR/recon" >/dev/null

# amass / subfinder / assetfinder via snap/go can be heavy; clone light OSINT helpers:
if [[ ! -d Maltego-note ]]; then
  echo "[i] (Optional) Maltego is GUI/proprietary; skip auto-install."
  mkdir -p Maltego-note && echo "Download Maltego manually if needed." > Maltego-note/README.txt
fi

popd >/dev/null

# ==============================
# GROUP 2: Credentials & Auth
# (impacket / cme installed above)
# ==============================
mkdir -p "$ROOT_DIR/creds"
pushd "$ROOT_DIR/creds" >/dev/null

# gpp-decrypt included with Kali (in kali-defaults), else we fetch a small helper:
if [[ ! -f gpp-decrypt.py ]]; then
  wget -qO gpp-decrypt.py https://raw.githubusercontent.com/t0thkr1s/gpp-decrypt/master/gpp-decrypt.py || true
  chmod +x gpp-decrypt.py || true
  ensure_link "$ROOT_DIR/creds/gpp-decrypt.py" "$BIN_DIR/gpp-decrypt"
fi
popd >/dev/null

# ==============================
# GROUP 3: Coercion & Relaying
# (responder, mitm6, coercer installed)
# ==============================
mkdir -p "$ROOT_DIR/coerce"
pushd "$ROOT_DIR/coerce" >/dev/null

# PetitPotam
if [[ ! -d PetitPotam ]]; then
  git clone https://github.com/topotam/PetitPotam.git
fi
ensure_link "$ROOT_DIR/coerce/PetitPotam/petitpotam.py" "$BIN_DIR/petitpotam.py"

# krbrelayx (contains printerbug.py and more)
if [[ ! -d krbrelayx ]]; then
  git clone https://github.com/dirkjanm/krbrelayx.git
else
  pushd krbrelayx >/dev/null && git pull --ff-only || true; popd >/dev/null
fi
ensure_link "$ROOT_DIR/coerce/krbrelayx/printerbug.py" "$BIN_DIR/printerbug.py"

popd >/dev/null

# ==============================
# GROUP 4: Priv Esc & Lateral
# (evil-winrm, smbmap, lsassy, pypykatz installed)
# ==============================
mkdir -p "$ROOT_DIR/privmove"
pushd "$ROOT_DIR/privmove" >/dev/null
# Nothing extra here; core tools are already installed & linked.
popd >/dev/null

# ==============================
# GROUP 5: Stealth / Tradecraft
# ==============================
mkdir -p "$ROOT_DIR/stealth"
pushd "$ROOT_DIR/stealth" >/dev/null

# dnscat2
if [[ ! -d dnscat2 ]]; then
  git clone https://github.com/iagox86/dnscat2.git
else
  pushd dnscat2 >/dev/null && git pull --ff-only || true; popd >/dev-null || true
fi

# chisel (prebuilt)
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

# ligolo-ng (prebuilt agent/proxy)
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

# gost (stealth proxy)
if [[ ! -x "$ROOT_DIR/stealth/gost" ]]; then
  case "$ARCH" in
    x86_64|amd64) GOST_ARCH="linux-amd64" ;;
    aarch64|arm64) GOST_ARCH="linux-arm64" ;;
    *) GOST_ARCH="linux-amd64" ;;
  esac
  wget -O "$TMP_DIR/gost.tar.gz" "https://github.com/go-gost/gost/releases/download/v${GOST_VER}/gost_${GOST_VER}_${GOST_ARCH}.tar.gz"
  tar -xzf "$TMP_DIR/gost.tar.gz" -C "$TMP_DIR"
  find "$TMP_DIR" -maxdepth 2 -type f -name gost -exec mv {} "$ROOT_DIR/stealth/gost" \;
  chmod +x "$ROOT_DIR/stealth/gost"
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
  chmod +x "$ROOT_DIR/c2/"sliver-*
fi
ensure_link "$ROOT_DIR/c2/sliver-server" "$BIN_DIR/sliver-server" || true
ensure_link "$ROOT_DIR/c2/sliver-client" "$BIN_DIR/sliver-client" || true

# Havoc (clone only; build manually if you want)
if [[ ! -d Havoc ]]; then
  git clone https://github.com/HavocFramework/Havoc.git
else
  pushd Havoc >/dev/null && git pull --ff-only || true; popd >/dev/null
fi

# Mythic (clone; dockerized—skip auto install in this script)
if [[ ! -d mythic ]]; then
  git clone https://github.com/its-a-feature/Mythic.git mythic
else
  pushd mythic >/dev/null && git pull --ff-only || true; popd >/dev/null
fi

popd >/dev/null

# ==============================
# GROUP 7: GUI / Viz / Reporting
# ==============================
mkdir -p "$ROOT_DIR/gui"
pushd "$ROOT_DIR/gui" >/dev/null
# BloodHound GUI installed via apt; PingCastle is Windows (run from a Windows jump host).
# GoPhish (optional download)
if [[ ! -d gophish ]]; then
  echo "[i] (Optional) Download GoPhish manually or add a fixed version URL here."
fi
popd >/dev/null

# ---- Symlink a few notable scripts from repos ----
ensure_link "$ROOT_DIR/coerce/PetitPotam/petitpotam.py" "$BIN_DIR/petitpotam.py"
ensure_link "$ROOT_DIR/coerce/krbrelayx/printerbug.py" "$BIN_DIR/printerbug.py"

# ---- Clean up temp files ----
rm -rf "$TMP_DIR"

# ---- Final sanity prints ----
echo
echo "========= READY ========="
echo "Root tools dir: $ROOT_DIR"
echo "Binaries linked under: $BIN_DIR"
echo "If pipx was newly installed, add to PATH for this session:"
echo '  export PATH="$HOME/.local/bin:$PATH"'
echo
echo "Quick checks:"
echo "  which impacket-smbclient || true"
echo "  which bloodhound-python || true"
echo "  which mitm6 || true"
echo "  which responder || true"
echo "  which chisel || true"
echo "  which ligolo-proxy || true"
echo "  which sliver-server || true"
echo "=========================="
