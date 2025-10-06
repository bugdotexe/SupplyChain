#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scan_namespace.sh <namespace>
# Example: ./scan_namespace.sh mozilla

NAMESPACE="$1"
OUTDIR="TRUFFLE_${NAMESPACE}"
mkdir -p "$OUTDIR"

YELLOW='\033[93m'
RESET='\033[0m'

# Get all repositories under a namespace
get_repos() {
  local page=1
  while true; do
    local url="https://hub.docker.com/v2/repositories/${NAMESPACE}/?page_size=100&page=${page}"
    local resp
    resp=$(curl -s "$url")

    echo "$resp" | jq -r '.results[].name'

    local next
    next=$(echo "$resp" | jq -r '.next')
    [[ "$next" == "null" ]] && break
    page=$((page+1))
  done
}

# Get all tags for a repo
get_tags() {
  local repo=$1
  local page=1
  while true; do
    local url="https://hub.docker.com/v2/repositories/${NAMESPACE}/${repo}/tags?page_size=100&page=${page}"
    local resp
    resp=$(curl -s "$url")

    echo "$resp" | jq -c '.results[]'

    local next
    next=$(echo "$resp" | jq -r '.next')
    [[ "$next" == "null" ]] && break
    page=$((page+1))
  done
}

echo "[*] Enumerating repositories in namespace: ${NAMESPACE}"
for repo in $(get_repos); do
  echo -e "\n=== Repo: ${YELLOW}${NAMESPACE}/${repo}${RESET} ==="

  for tag in $(get_tags "$repo"); do
    name=$(echo "$tag" | jq -r '.name')
    for digest in $(echo "$tag" | jq -r '.images[].digest'); do
      arch=$(echo "$tag" | jq -r --arg d "$digest" '.images[] | select(.digest==$d) | .architecture')

      echo -e "\n--- Scanning ${YELLOW}${NAMESPACE}/${repo}:${name} [${arch}]${RESET} ---"
      logfile="${OUTDIR}/${repo}_${name}_${arch}.log"

      # Run trufflehog scan
      if trufflehog docker --image "${NAMESPACE}/${repo}@${digest}" --only-verified --no-update >"$logfile" 2>&1; then
        if grep -q "Source" "$logfile"; then
          echo "[!] Potential secret found → $logfile"
        else
          rm -f "$logfile"
          echo "[OK] No verified secrets."
        fi
      else
        echo "[ERR] Trufflehog failed for ${repo}:${name} (${arch}), see $logfile"
      fi
    done
  done
done

echo -e "\n[*] Completed. Logs in: $OUTDIR"
