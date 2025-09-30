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

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <github_org>"
    exit 1
fi
ORG=$1

bash ghClone.sh $ORG
bash main.sh $ORG "/tmp/$ORG/REPOS"
bash depChecker.sh $ORG "/tmp/$ORG/"
trufflehog github --only-verified --token=$GITHUB_TOKEN --issue-comments --pr-comments --gist-comments --include-members --archive-max-depth=50 --org=$ORG

while IFS= read -r member; do
bash main.sh ${member} "/tmp/$ORG/${member}/"
bash depChecker.sh ${member} "/tmp/$ORG/${member}/"

for f in "/tmp/$ORG/${member}/REPOS/*"; do
  [ -e "$f" ] || continue
  trufflehog git file://"/tmp/$ORG/${member}/REPOS/${f##*/}" --only-verified --archive-max-depth=150
done
done < "/tmp/$ORG/member.usernames"
