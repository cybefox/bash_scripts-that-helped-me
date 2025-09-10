#!/usr/bin/env bash
# Minimal Black-Team Toolkit Bootstrap (stealth dropbox)
# Visual + Secure edition

set -Eeuo pipefail
IFS=$'\n\t'
umask 027

# -------- Visuals --------
if command -v tput >/dev/null 2>&1 && [ -n "${TERM:-}" ]; then
  B=$(tput bold); R=$(tput setaf 1); G=$(tput setaf 2); Y=$(tput setaf 3); C=$(tput setaf 6); N=$(tput sgr0)
else B=""; R=""; G=""; Y=""; C=""; N=""; fi
ok(){ echo -e "${G}✔${N} $*"; }
warn(){ echo -e "${Y}⚠${N} $*" >&2; }
err(){ echo -e "${R}✘${N} $*" >&2; }
info(){ echo -e "${C}➜${N} $*"; }
title(){ echo -e "\n${B}${C}▞▞ $* ▚▚${N}\n"; }

# -------- Safety/Context --------
[ "${EUID}" -eq 0 ] || { err "Run as root (sudo)."; exit 1; }
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
LOG="/tmp/blackteam-minimal-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

ROOT_DIR="/opt/blackteam"
BIN_DIR="/usr/local/bin"
TMP_DIR="$(mktemp -d -t blackteam-min-XXXXXX)"
trap 'rc=$?; rm -rf "$TMP_DIR"; [ $rc -eq 0 ] && ok "Cleanup done." || err "Exited with status $rc"; exit $rc' EXIT INT TERM

set -x  # verbose

# -------- Helpers --------
has(){ command -v "$1" >/dev/null 2>&1; }
is_installed(){ dpkg -s "$1" >/dev/null 2>&1 || rpm -q "$1" >/dev/null 2>&1 || return 1; }
apt_update(){ has apt-get && apt-get update -y || warn "apt update failed (continuing)"; }
apt_install(){ local p="$1"; has apt-get || { warn "apt missing; skip $p"; return; }
  is_installed "$p" && { info "$p already installed"; return; }
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$p" || warn "apt failed for $p (skip)"
}
fetch(){ # fetch <url> <out>
  local u="$1" o="$2"
  if has curl; then
    curl --proto '=https' --tlsv1.2 -fsSLo "$o" "$u" || { warn "curl failed $u"; return 1; }
  elif has wget; then
    wget --https-only -qO "$o" "$u" || { warn "wget failed $u"; return 1; }
  else warn "no curl/wget available"; return 1; fi
}
link_bin(){ local t="$1" l="$2"; [ -x "$t" ] && ln -sf "$t" "$l" || warn "not executable: $t"; }
git_clone(){ # git_clone <url> <dir>
  has git || { warn "git missing; cannot clone $1"; return; }
  if [ -d "$2/.git" ]; then (cd "$2" && git pull --ff-only) || warn "git pull failed: $2"
  else git clone --depth 1 "$1" "$2" || warn "git clone failed: $1"; fi
}

# -------- Layout --------
mkdir -p "$ROOT_DIR" "$BIN_DIR"

title "Group 0 • Base packages"
apt_update
for p in nmap masscan dnsrecon dnsutils whois ldap-utils bloodhound neo4j \
         crackmapexec responder hashcat john smbmap evil-winrm mitm6 wireshark iodine \
         git wget curl jq unzip xz-utils python3-venv python3-pip; do
  apt_install "$p"
done
ok "Base packages processed."

title "Group 1 • Python CLIs via pipx"
if ! has pipx; then
  if has python3; then
    su - "${SUDO_USER:-root}" -c "python3 -m pip install --user pipx" || warn "pipx install failed"
    su - "${SUDO_USER:-root}" -c "python3 -m pipx ensurepath" || true
  else warn "python3 missing; skipping pipx"; fi
fi
export PATH="/home/${SUDO_USER:-root}/.local/bin:$PATH"
pipx_install(){ local pkg="$1"
  if has pipx; then
    pipx list 2>/dev/null | grep -qiE "package ${pkg} " && info "pipx $pkg already installed" || \
    pipx install "$pkg" || warn "pipx failed for $pkg (skip)"
  fi
}
pipx_install impacket
pipx_install coercer
pipx_install bloodhound-python
pipx_install lsassy
pipx_install pypykatz
for exe in impacket-* bloodhound-python coercer lsassy pypykatz; do
  [ -x "/home/${SUDO_USER:-root}/.local/bin/$exe" ] && link_bin "/home/${SUDO_USER:-root}/.local/bin/$exe" "$BIN_DIR/$exe"
done
ok "Python tools ready."

title "Group 2 • Coercion & Relaying"
mkdir -p "$ROOT_DIR/coerce"
git_clone https://github.com/topotam/PetitPotam.git "$ROOT_DIR/coerce/PetitPotam"
link_bin "$ROOT_DIR/coerce/PetitPotam/petitpotam.py" "$BIN_DIR/petitpotam.py"
git_clone https://github.com/dirkjanm/krbrelayx.git "$ROOT_DIR/coerce/krbrelayx"
link_bin "$ROOT_DIR/coerce/krbrelayx/printerbug.py" "$BIN_DIR/printerbug.py"
ok "Coercion utilities staged."

title "Group 3 • Stealth / Pivot (chisel, ligolo-ng, gost)"
mkdir -p "$ROOT_DIR/stealth"
ARCH="$(uname -m)"; CARCH="amd64"; [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ] && CARCH="arm64"

# chisel
CHISEL_VER="1.9.1"
if [ ! -x "$ROOT_DIR/stealth/chisel" ]; then
  if fetch "https://github.com/jpillora/chisel/releases/download/v${CHISEL_VER}/chisel_${CHISEL_VER}_linux_${CARCH}.gz" "$TMP_DIR/chisel.gz"; then
    gunzip -f "$TMP_DIR/chisel.gz" || warn "gunzip chisel failed"
    mv "$TMP_DIR/chisel_${CHISEL_VER}_linux_${CARCH}" "$ROOT_DIR/stealth/chisel" 2>/dev/null || true
    chmod +x "$ROOT_DIR/stealth/chisel" 2>/dev/null || true
  fi
fi
link_bin "$ROOT_DIR/stealth/chisel" "$BIN_DIR/chisel"

# ligolo-ng
LIGOLO_VER="0.6.3"; LARCH="linux-amd64"; [ "$CARCH" = "arm64" ] && LARCH="linux-arm64"
if [ ! -x "$ROOT_DIR/stealth/ligolo-proxy" ] || [ ! -x "$ROOT_DIR/stealth/ligolo-agent" ]; then
  if fetch "https://github.com/nicocha30/ligolo-ng/releases/download/v${LIGOLO_VER}/ligolo-ng_${LIGOLO_VER}_${LARCH}.zip" "$TMP_DIR/ligolo.zip"; then
    unzip -o "$TMP_DIR/ligolo.zip" -d "$ROOT_DIR/stealth" || warn "unzip ligolo failed"
    chmod +x "$ROOT_DIR/stealth/ligolo-"* 2>/dev/null || true
  fi
fi
link_bin "$ROOT_DIR/stealth/ligolo-proxy" "$BIN_DIR/ligolo-proxy"
link_bin "$ROOT_DIR/stealth/ligolo-agent" "$BIN_DIR/ligolo-agent"

# gost
GOST_VER="2.11.5"; GARCH="linux-amd64"; [ "$CARCH" = "arm64" ] && GARCH="linux-arm64"
if [ ! -x "$ROOT_DIR/stealth/gost" ]; then
  if fetch "https://github.com/go-gost/gost/releases/download/v${GOST_VER}/gost_${GOST_VER}_${GARCH}.tar.gz" "$TMP_DIR/gost.tgz"; then
    tar -xzf "$TMP_DIR/gost.tgz" -C "$TMP_DIR" || warn "tar gost failed"
    find "$TMP_DIR" -type f -name gost -exec mv {} "$ROOT_DIR/stealth/gost" \; 2>/dev/null || true
    chmod +x "$ROOT_DIR/stealth/gost" 2>/dev/null || true
  fi
fi
link_bin "$ROOT_DIR/stealth/gost" "$BIN_DIR/gost"
ok "Stealth tooling ready."

title "Done"
ok "Minimal toolkit ready. Log: $LOG"
echo -e "${B}Try:${N} impacket-smbclient, bloodhound-python, mitm6, responder."
