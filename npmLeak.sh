#!/bin/bash

set -euo pipefail


ORG_SCOPE="${1:-}"
API_PAGE_SIZE=250
REPORT_FILE="npm_audit_report.json"


check_deps() {
  local missing_deps=0
  for dep in npm jq trufflehog curl; do
    if ! command -v "$dep" &>/dev/null; then
      echo "ERROR: Required dependency '$dep' is not installed or not in PATH." >&2
      missing_deps=1
    fi
  done
  if [[ "$missing_deps" -eq 1 ]]; then
    exit 1
  fi
}

process_package_version() {
  local package_name="$1"
  local version="$2"
  local temp_dir
  temp_dir=$(mktemp -d)
  trap 'rm -rf -- "$temp_dir"' EXIT

  echo "INFO: Scanning $package_name@$version"

  (
    cd "$temp_dir" || exit 1

    if ! npm pack "$package_name@$version" --quiet &>/dev/null; then
      echo "WARN: Failed to download $package_name@$version"
      return
    fi

    local tarball
    tarball=$(find . -name "*.tgz" | head -n 1)
    tar -xzf "$tarball"

    local package_path="package"

    local scan_output
    scan_output=$(trufflehog filesystem "$package_path" --only-verified --json || true)

    if [[ -n "$scan_output" ]]; then
      echo "!!! CRITICAL: Verified secrets found in $package_name@$version !!!"
      echo "$scan_output" | jq --arg pkg "$package_name" --arg ver "$version" \
        '. | {package:$pkg, version:$ver, secrets:.}' >>"$REPORT_FILE"
    else
      echo "INFO: No verified secrets found in $package_name@$version"
    fi
  )
}

process_package() {
  local package_name="$1"

  echo "INFO: Fetching all versions of $package_name..."
  local versions
  versions=$(npm view "$package_name" versions --json 2>/dev/null | jq -r '.[]' || true)

  if [[ -z "$versions" ]]; then
    echo "WARN: No versions found for $package_name"
    return
  fi

  while read -r version; do
    [[ -n "$version" ]] && process_package_version "$package_name" "$version"
  done <<<"$versions"
}


check_deps

if [[ -z "$ORG_SCOPE" ]]; then
  echo "Usage: $0 <npm_organization_scope>"
  exit 1
fi

echo "INFO: Starting full audit for organization scope: @$ORG_SCOPE"
echo "[]" >"$REPORT_FILE" 
curl -s "https://api.npms.io/v2/search?q=scope:$ORG_SCOPE&size=$API_PAGE_SIZE" | \
  jq -r '.results[].package.name' | \
  while read -r package_name; do
    [[ -n "$package_name" ]] && process_package "$package_name"
  done

if [[ -s "$REPORT_FILE" ]]; then
  echo "INFO: Secret findings summary:"
  jq '.' "$REPORT_FILE"
else
  echo "INFO: No verified secrets found across all packages."
fi

echo "INFO: Audit completed for @$ORG_SCOPE"
echo "Report saved at: $REPORT_FILE"
