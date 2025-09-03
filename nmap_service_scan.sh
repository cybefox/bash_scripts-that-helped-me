#!/bin/bash

# Usage: ./nmap_service_scan.sh -i iplist.txt [-o output.txt]

usage() {
    echo "Usage: $0 -i <ip_list_file> [-o <output_file>]"
    exit 1
}

# Parse arguments
while getopts "i:o:" opt; do
  case $opt in
    i) input_file=$OPTARG ;;
    o) output_file=$OPTARG ;;
    *) usage ;;
  esac
done

# Input file required
if [ -z "$input_file" ]; then
    echo "[!] Input file not specified"
    usage
fi

if [ ! -f "$input_file" ]; then
    echo "[!] Input file '$input_file' not found"
    exit 1
fi

# Function to run Nmap scan
run_scan() {
    ip=$1
    echo "Scanning $ip..."
    nmap -sS -sU -sV -vv -Pn --top-ports 100 $ip
}

# If output file provided → write results there
if [ -n "$output_file" ]; then
    echo "[*] Results will be saved to $output_file"
    while read -r ip; do
        echo "===== $ip =====" >> "$output_file"
        nmap -sS -sU -sV --top-ports 100 "$ip" >> "$output_file"
        echo "" >> "$output_file"
    done < "$input_file"
    echo "[*] Scanning complete. Results saved in $output_file"
else
    while read -r ip; do
        run_scan "$ip"
    done < "$input_file"
fi
