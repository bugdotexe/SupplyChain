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
bash find_employees.sh ${DOMAIN} ${ORG}
EMPLOYEE_FILE="${ORG}_employees.txt"

if [[ ! -f "$EMPLOYEE_FILE" ]]; then
    echo -e "\e[31m[!] Employee file not found: $EMPLOYEE_FILE\e[0m"
    exit 1
fi

OUTPUT_DIR="$ORG"
mkdir -p "$OUTPUT_DIR"

echo -e "\e[34m[+] Scanning organization: $ORG\e[0m"
bash gitSearch.sh "$ORG"
python3 force-push-scanner/force_push_scanner.py --scan --db-file=force-push-scanner/force_push_commits.sqlite3 $ORG

echo -e "\e[34m[+] Scanning JavaScript Files \e[0m"
bash JsScan.sh $OUTPUT_DIR/*.js | 
while read -r package; do
  if npm view "$package" >/dev/null 2>&1; then
  sleep 0.1
  else
    echo -e "\e[32m [+]\e[0m \e[31m$package\e[0m does NOT exist on NPM\e[0m"
  fi
done

if ls "$OUTPUT_DIR"/*.yml >/dev/null 2>&1; then
echo -e "\e[32m\n[+] Extracting Docker images from docker-compose.yml \e[0m"
grep -h "image:" "$OUTPUT_DIR"/*.yml 2>/dev/null | awk '{print $2}' | cut -d ":" | sort -u | while read -r IMAGE; do
    if [[ -n "$IMAGE" ]]; then
        bash docker.sh "$IMAGE"
    fi
done
else
echo
fi


while IFS= read -r user; do
    [[ -z "$user" ]] && continue
    
    echo -e "\e[32m[+] Scanning user: $user\e[0m"
    bash gitSearch.sh "$user"
    python3 force-push-scanner/force_push_scanner.py --scan --db-file=force-push-scanner/force_push_commits.sqlite3 $user
    echo -e "\e[34m[+] Scanning JavaScript Files \e[0m"
       bash JsScan.sh $user/*.js | while read -r package; do
       if npm view "$package" >/dev/null 2>&1; then
         sleep 0.1
       else
         echo -e "\e[32m [+]\e[0m \e[31m$package\e[0m does NOT exist on NPM\e[0m"
       fi
       done


if ls "$user"/*.yml >/dev/null 2>&1; then
echo -e "\e[32m\n[+] Extracting Docker images from docker-compose.yml \e[0m"
grep -h "image:" "$user"/*.yml 2>/dev/null | awk '{print $2}' | cut -d ":" | sort -u | while read -r IMAGE; do
    if [[ -n "$IMAGE" ]]; then
        bash docker.sh "$IMAGE"
    fi
done
else
echo
fi

done < "$EMPLOYEE_FILE"

echo -e "\e[34m[+] Running dependency checks\e[0m"

ext=(
    "json:NPM Dependencies"
    "txt:Python Dependencies"
    "rb:Ruby Dependencies"
)

for entry in "$OUTPUT_DIR" $(cat "$EMPLOYEE_FILE"); do
    [ ! -d "$entry" ] && continue
    
    echo -e "\e[34m[+] Running dependency checks for $entry\e[0m"

    for ext_entry in "${ext[@]}"; do
        ext_type="${ext_entry%%:*}"
        label="${ext_entry#*:}"
        
        echo -e "\e[31m[-] Checking $label\e[0m"
        
        while IFS= read -r -d '' file; do
            filename=$(basename "$file")
            echo -e "\e[33m[→] Processing $filename\e[0m"
            
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
