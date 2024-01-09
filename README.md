# bash_scripts-that-helped-me

## these are some bash scripts that helped me to make my life easier

1. the one is used for copying my ipset from one list to another
   ```bash
   for ip in $(ipset list oldset | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'); do ipset add newset $ip; done
   ```
