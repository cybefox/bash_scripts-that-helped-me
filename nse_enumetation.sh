#!/usr/bin/env bash
#
# nse_enumeration.sh
# ------------------
# Description:
#   1. Performs an initial Nmap scan to find open ports on a target.
#   2. Parses the open ports from the scan results.
#   3. Runs a second Nmap scan with NSE scripts against the discovered ports.
#
# Usage:
#   ./nse_enumeration.sh <target_ip_or_domain>
#
# Example:
#   ./nse_enumeration.sh 192.168.1.10
#
# Requirements:
#   - nmap

TARGET="$1"
if [ -z "$TARGET" ]; then
  echo "[!] Usage: $0 <target_ip_or_domain>"
  exit 1
fi

# -------------------------------------------------------------------
# 1) Initial Scan: Find open ports
# -------------------------------------------------------------------
echo "[*] Starting initial scan on $TARGET..."

# -sV : Service/version detection
# -T4 : Faster timing template; adjust if you need stealth
# -oG : Grepable output, easier to parse
# -p- : Scan all 65535 TCP ports (you can limit to top ports if you wish)
nmap -sV -T4 -p- -oG initial_scan.grep "$TARGET"

echo "[*] Parsing open ports from initial scan..."

# Parse the grepable output to extract open ports.
# Explanation:
#  - grep "Ports:" lines
#  - cut/awk to isolate the open ports section
#  - filter out "filtered" or "closed" ports
#  - extract just the port number (before the slash)
OPEN_PORTS=$(grep -i "Ports:" initial_scan.grep | \
  awk -F 'Ports: ' '{print $2}' | \
  awk -F 'Ignored ' '{print $1}' | \
  sed 's/, /,/g' | tr ' ' '\n' | \
  grep open | \
  cut -d '/' -f1 | \
  tr '\n' ',' | sed 's/,$//')

if [ -z "$OPEN_PORTS" ]; then
  echo "[!] No open ports found or parsing failed."
  echo "[!] Check initial_scan.grep for details."
  exit 1
fi

echo "[*] Found open ports: $OPEN_PORTS"

# -------------------------------------------------------------------
# 2) Run NSE scripts on discovered open ports
# -------------------------------------------------------------------
echo "[*] Running NSE scripts on open ports..."

# Examples of NSE script categories you can run:
#   - default:    Basic scripts (safe scanning)
#   - vuln:       Vulnerability checks
#   - safe:       Scripts deemed “safe” by nmap
#   - auth, brute, discovery, etc.
#
# Here we run "default,vuln" for demonstration. Feel free to adjust.
nmap -sV -p "$OPEN_PORTS" \
     --script=default,vuln \
     -oN nse_scan_results.txt \
     "$TARGET"

echo "[*] NSE scan complete."
echo "    Results saved to: nse_scan_results.txt"
