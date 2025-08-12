#!/bin/bash
GITHUB_TOKEN=""
AUTH_HEADER=()
[ -n "$GITHUB_TOKEN" ] && AUTH_HEADER=(-H "Authorization: token $GITHUB_TOKEN")

git clone --depth 1 https://github.com/infosec-us-team/Immunefi-Bug-Bounty-Programs-Unofficial tmp_repo >/dev/null
cd tmp_repo/project || exit 1

orgs=$(grep -hoP 'https://github\.com/\K[^/"]+' *.json \
    | sed 's/[^A-Za-z0-9._-]//g' \
    | sort -u)

echo "[*] Extracted $(echo "$orgs" | wc -l) unique candidates"
echo "[*] Validating via GitHub API..."

valid_orgs=()
while read -r org; do
    [ -z "$org" ] && continue

    status=$(curl -s -o /dev/null -w "%{http_code}" \
        "${AUTH_HEADER[@]}" \
        "https://api.github.com/orgs/$org")

    if [ "$status" -eq 200 ]; then
        echo "[VALID] $org"
        valid_orgs+=("$org")
    else
        echo "[INVALID] $org"
    fi
done <<< "$orgs"

echo
echo "[*] Final valid GitHub organizations:"
printf "%s\n" "${valid_orgs[@]}" | sort -u >> Immunefi_web3

cd ../..
rm -rf tmp_repo
