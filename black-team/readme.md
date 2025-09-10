==========================================
 Cybefox Red Team Helper Bash Scripts
==========================================

These scripts bootstrap a full **black teaming / stealth red team / APT simulation toolkit** 
on Kali Linux or Debian, organized into minimal and core builds.

------------------------------------------
 🚀 Available Scripts
------------------------------------------

1. minimal-bootstrap.sh
   - Lightweight kit for quick drops, implants, or jumpboxes
   - Includes recon, relaying, credential harvesting, coercion tools
   - Good for stealth environments

2. core-bootstrap.sh
   - Full arsenal for red team operations
   - Adds heavy C2 frameworks (Havoc, Mythic, Sliver), 
     GUI tools (BloodHound, GoPhish), and option to install VirtualBox + Windows 11 VM
   - Best for operator systems and lab environments

------------------------------------------
 🧭 Usage
------------------------------------------
- Make executable: 
    chmod +x minimal-bootstrap.sh core-bootstrap.sh

- Run minimal install (stealth mode):
    sudo ./minimal-bootstrap.sh

- Run core install (full stack):
    sudo ./core-bootstrap.sh

- Both scripts are idempotent: re-running will skip already-installed packages.
- All tools are placed under /opt/blackteam and symlinked into /usr/local/bin 
  so they can be accessed from anywhere.

------------------------------------------
 📦 Tools Covered
------------------------------------------
- Recon & Discovery: nmap, masscan, dnsrecon, bloodhound-python, etc.
- Credential Harvesting: impacket, crackmapexec/netexec, kerbrute, responder, mitm6
- Coercion: PetitPotam, printerbug.py, coercer.py
- PrivEsc & Lateral: evil-winrm, smbmap, lsassy, pypykatz
- Stealth / Tradecraft: chisel, ligolo-ng, gost, dnscat2
- C2 & Evasion: Sliver, Havoc, Mythic
- GUI & Reporting: BloodHound GUI, GoPhish, optional Win11 VM for PingCastle

This repo is a collaboration: senior guiding, junior executing.  
Part of **Cybefox/bash_scripts-that-helped-me**.

------------------------------------------
 ⚠️ Disclaimer
------------------------------------------
These scripts are for **authorized red team operations and labs only**.  
Use responsibly, within scope of engagement and rules of engagement (RoE).
Unauthorized use against systems without consent may be illegal.
