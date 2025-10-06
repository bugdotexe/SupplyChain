#!/bin/bash
RED="\e[31m"
RESET="\e[0m"
GREEN="\e[32m"

echo
echo -e "[+] World \e[31mOFF\e[0m,Terminal \e[32mON \e[0m"
echo -e " █████                             █████           █████
░░███                             ░░███           ░░███
 ░███████  █████ ████  ███████  ███████   ██████  ███████    ██████  █████ █████  ██████
 ░███░░███░░███ ░███  ███░░███ ███░░███  ███░░███░░░███░    ███░░███░░███ ░░███  ███░░███
 ░███ ░███ ░███ ░███ ░███ ░███░███ ░███ ░███ ░███  ░███    ░███████  ░░░█████░  ░███████
 ░███ ░███ ░███ ░███ ░███ ░███░███ ░███ ░███ ░███  ░███ ███░███░░░    ███░░░███ ░███░░░
 ████████  ░░████████░░███████░░████████░░██████   ░░█████ ░░██████  █████ █████░░██████
░░░░░░░░    ░░░░░░░░  ░░░░░███ ░░░░░░░░  ░░░░░░     ░░░░░   ░░░░░░  ░░░░░ ░░░░░  ░░░░░░
                      ███ ░███
                     ░░██████
                      ░░░░░░                                                             "
echo -e "[+] Make \e[31mCritical\e[0m great again"
echo

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <github_org>"
    exit 1
fi
ORG=$1

LOWER=$(echo "${ORG}" | tr '[:upper:]' '[:lower:]')
bash ghClone.sh $ORG
bash main.sh $ORG "/tmp/$ORG/REPOS/${LOWER}"
bash depChecker.sh $ORG "/tmp/$ORG/REPOS"

echo -e "${GREEN}[-]Scanning with Trufflehog : [-]${RESET}$NAME"
trufflehog github --only-verified --token=$GITHUB_TOKEN --issue-comments --pr-comments --gist-comments --include-members --archive-max-depth=50 --org=$ORG

echo -e "${GREEN}[-]Scanning Secrets : [-]${RESET}$NAME"
find "/tmp/$ORG/REPOS/${LOWER}" -name "*.js" | xargs -I {} bash JsLeak.sh {} | sort -u | anew "/tmp/$ORG/secrets.potential"

while IFS= read -r member; do
LOWER=$(echo "${member}" | tr '[:upper:]' '[:lower:]')
bash main.sh ${member} "/tmp/$ORG/${member}/REPOS/${LOWER}"
bash depChecker.sh ${member} "/tmp/$ORG/${member}/REPOS"

for f in "/tmp/$ORG/${member}/REPOS/${LOWER}/*"; do
  [ -e "$f" ] || continue
  echo -e "${GREEN}[-]Scanning Secrets : [-]${RESET}${member}"
  trufflehog git file://"/tmp/$ORG/${member}/REPOS/${LOWER}/${f##*/}" --only-verified --archive-max-depth=150
  echo -e "${GREEN}[-]Scanning Secrets : [-]${RESET}${member}"
find "/tmp/$ORG/${member}/REPOS/${LOWER}/" -name "*.js" | xargs -I {} bash JsLeak.sh {} | sort -u | anew "/tmp/$ORG/${member}/secrets.potential"
done
done < "/tmp/$ORG/member.usernames"
