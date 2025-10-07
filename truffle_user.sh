#!/usr/bin/env bash

GITHUB_TOKEN=${GITHUB_TOKEN}
set -euo pipefail

if ! command -v gh &>/dev/null; then
    echo "[-] GitHub CLI (gh) not found. Install from https://cli.github.com/"
    exit 1
fi

if ! command -v trufflehog &>/dev/null; then
    echo "[-] TruffleHog not found. Install from https://github.com/trufflesecurity/trufflehog"
    exit 1
fi

scan_user() {
    local user="$1"
    echo "[*] Fetching repos for user: $user"

    gh repo list "$user" --limit 1000 --json name,isFork,isArchived,url | \
    jq -r '.[] | [.name, .isFork, .isArchived, .url] | @tsv' | while IFS=$'\t' read -r name isFork isArchived url; do
        echo "---------------------------------------------------"
        echo "[*] Repo: $name"
        echo "    Fork: $isFork"
        echo " Archived: $isArchived"
        echo "     URL: $url"

        echo "[*] Running TruffleHog..."
        trufflehog git "$url" --results=verified || {
            echo "[!] TruffleHog scan failed for $url"
        }
    done
}

if [[ $# -eq 1 && $1 != "-f" ]]; then
    scan_user "$1"
elif [[ $# -eq 2 && $1 == "-f" ]]; then
    while IFS= read -r username; do
        [[ -z "$username" ]] && continue
        scan_user "$username"
    done < "$2"
else
    echo "Usage: $0 <github_username>"
    echo "       $0 -f usernames.txt"
    exit 1
fi
