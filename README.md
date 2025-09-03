# bash_scripts-that-helped-me

## these are some bash scripts that helped me to make my life easier

1. the one is used for copying my ipset from one list to another
   ```bash
   for ip in $(ipset list oldset | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'); do ipset add newset $ip; done
   ```


## files

1. nmap_service_scan.sh: This Bash script automates running Nmap TCP and UDP service scans against a list of target IPs provided in an input file. It requires an IP list file (-i <file>) and optionally allows saving the results into a custom output file (-o <file>). By default, it scans the top 100 TCP and UDP ports with service/version detection enabled. If no output file is specified, the results are displayed directly in the terminal.

2. nse_enumetation.sh: This script automates Nmap enumeration in two stages: it first scans all TCP ports on a target to find open ones, then runs Nmap NSE scripts (default,vuln) against those ports for deeper service and vulnerability detection, saving results to a file.

3. ipsweep.sh: a simple Bash script that pings all hosts in a given subnet range (e.g., 192.168.1.0/24) and lists the ones that respond, helping quickly identify live hosts.
