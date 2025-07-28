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
ORG="${1:-}"
[ -z "$ORG" ] && { echo "Usage: $0 <organization>"; exit 1; }

bash supplyChain.sh $ORG
echo
echo -e "[+] World \e[31mOFF\e[0m,Terminal \e[32mON \e[0m"
dir="${ORG}_supplyChain"
[ ! -d "$dir" ] && { echo "Error: Directory '$dir' not found"; exit 1; }

ext=(
json
rb
txt
)

for a in "${ext[@]}"; do
    if [[ "$a" == "json" ]];then
             echo -e "\e[31m[-] Checking NPM Dependencies\e[0m"
        elif [[ "$a" == "pip" ]];then
             echo -e "\e[31m[-] Checking Python Dependencies\e[0m"
        elif [[ "$a" == "rb" ]];then
             echo -e "\e[31m[-] Checking Ruby Dependencies\e[0m"
        else
         exit 1
        fi

    while IFS= read -r -d '' file; do
        filename=$(basename "$file")
        if [[ "$a" == "json" ]];then
            bash depChecker.sh --npm $dir/$filename
        elif [[ "$a" == "pip" ]];then
            bash depChecker.sh --pip $dir/$filename
        elif [[ "$a" == "rb" ]];then
            bash depChecker.sh --gem $dir/$filename
        else
         exit 1
        fi
    done < <(find "$dir" -maxdepth 1 -type f -name "*.$a" -print0 2>/dev/null)
done
