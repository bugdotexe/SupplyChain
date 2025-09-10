#!/bin/bash

echo
echo -e "[+] World \e[31mOFF\e[0m,Terminal \e[32mON \e[0m"
echo -e "                                 _____
   ____   ____   ____   ____    /  |  |   ___________ ___.__.
  / ___\ /  _ \ /    \ /    \  /   |  |__/ ___\_  __ <   |  |
 / /_/  >  <_> )   |  \   |  \/    ^   /\  \___|  | \/\___  |
 \___  / \____/|___|  /___|  /\____   |  \___  >__|   / ____|
/_____/             \/     \/      |__|      \/       \/
"
echo -e "[+] Make \e[31mCritical\e[0m great again"
echo

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <domain> <github_org>"
    exit 1
fi

DOMAIN="$1"
ORG="$2"

OUTPUT="GITHUB/$ORG"
mkdir -p "$OUTPUT"

bash find_employees.sh ${DOMAIN} ${ORG}
EMPLOYEE_FILE="$OUTPUT/${ORG}.employees"

if [[ ! -f "$EMPLOYEE_FILE" ]]; then
    echo -e "\e[31m[!] Employee file not found: $EMPLOYEE_FILE\e[0m"
    exit 1
fi

echo -e "\e[34m[+] Scanning organization: $ORG\e[0m"
bash gitSearch.sh "$ORG"
python3 force_push_scanner.py --scan --db-file=force_push_commits.sqlite3 $ORG


echo -e "\e[34m[+] Scanning JavaScript Files \e[0m"
for file in $(ls GITHUB/$ORG | grep ".js$");do  
bash JsLeak.sh $OUTPUT/$file
done

for file in $(ls GITHUB/$ORG | grep ".js$");do   
bash JsScan.sh $OUTPUT/$file
done | 
while read -r package; do
  if npm view "$package" >/dev/null 2>&1; then
  sleep 0.1
  else
    echo -e "\e[32m [+]\e[0m \e[31m$package\e[0m does NOT exist on NPM\e[0m"
  fi
done

echo -e "\e[32m\n[+] Extracting Docker images from docker-compose.yml \e[0m"
grep -h "image:" "$OUTPUT"/*.yml 2>/dev/null | awk '{print $2}' | cut -d ":" | sort -u | while read -r IMAGE; do
    if [[ -n "$IMAGE" ]]; then
        bash docker.sh "$IMAGE"
    fi
done

while IFS= read -r user; do
    [[ -z "$user" ]] && continue
    
    echo -e "\e[32m[+] Scanning user: $user\e[0m"
    bash gitSearch.sh "$user"
    python3 force_push_scanner.py --scan --db-file=force_push_commits.sqlite3 $user
    echo -e "\e[34m[+] Scanning JavaScript Files \e[0m"
       for file in $(ls GITHUB/$user | grep ".js$");do  
          bash JsLeak.sh GITHUB/$user/$file
       done

       for file in $(ls GITHUB/$user | grep ".js$");do
         bash JsScan.sh GITHUB/$user/$file
       done | while read -r package; do
       if npm view "$package" >/dev/null 2>&1; then
         sleep 0.1
       else
         echo -e "\e[32m [+]\e[0m \e[31m$package\e[0m does NOT exist on NPM\e[0m"
       fi
       done

echo -e "\e[32m\n[+] Extracting Docker images from docker-compose.yml \e[0m"
grep -h "image:" "GITHUB/$user"/*.yml 2>/dev/null | awk '{print $2}' | cut -d ":" | sort -u | while read -r IMAGE; do
    if [[ -n "$IMAGE" ]]; then
        bash docker.sh "$IMAGE"
    fi
done

done < "$EMPLOYEE_FILE"

echo -e "\e[34m[+] Running dependency checks\e[0m"

ext=(
    "json:NPM Dependencies"
    "txt:Python Dependencies"
    "rb:Ruby Dependencies"
)

for entry in "$OUTPUT" $(cat "$EMPLOYEE_FILE"); do
    [ ! -d "$entry" ] && continue
    
    echo -e "\e[34m[+] Running dependency checks for $entry\e[0m"

    for ext_entry in "${ext[@]}"; do
        ext_type="${ext_entry%%:*}"
        label="${ext_entry#*:}"
        
        echo -e "\e[31m[-] Checking $label\e[0m"
        
        while IFS= read -r -d '' file; do
            filename=$(basename "$file")
            echo -e "\e[33m[â†’] Processing $filename\e[0m"
            
            case "$ext_type" in
                "json") bash depChecker.sh --npm "$file" ;;
                "txt")  bash depChecker.sh --pip "$file" ;;
                "rb")   bash depChecker.sh --gem "$file" ;;
            esac
        done < <(find "$entry" -type f -name "*.$ext_type" -print0 2>/dev/null)
    done
done

echo
echo -e "[+] World \e[31mOFF\e[0m,Terminal \e[32mON \e[0m"
