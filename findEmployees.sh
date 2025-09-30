#!/usr/bin/env bash
set -euo pipefail
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ORG="${1:-}"
TOKEN="$GITHUB_TOKEN"
mkdir -p /tmp/$ORG
OUTFILE="/tmp/$ORG/member.usernames"


if [ -z "$ORG" ]; then
  echo "Usage: $0 <org_name>"
  exit 1
fi

# check deps
for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    exit 2
  fi
done

PAGE=1
> "$OUTFILE"

while :; do
  RESP="$(curl -sS -H "Authorization: token $TOKEN" \
                 -H "Accept: application/vnd.github+json" \
                 "https://api.github.com/orgs/${ORG}/members?per_page=100&page=${PAGE}")"

  # if response empty or error
  COUNT=$(echo "$RESP" | jq 'length')
  if [ "$COUNT" -eq 0 ]; then
    break
  fi

  echo "$RESP" | jq -r '.[].login' >> "$OUTFILE"

  PAGE=$((PAGE+1))
done
echo -e "${BLUE} Saved ${NC}${GREEN}$(wc -l < $OUTFILE)${NC}${BLUE} members to${NC} ${RED}$OUTFILE${NC}"
