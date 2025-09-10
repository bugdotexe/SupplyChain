#!/bin/bash

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

fetch_org_packages() {
    local org_name=$1
    log "Fetching organization packages for @$org_name"
        curl -s "https://www.npmjs.com/org/$org_name" \
            | grep -oP '"name":"@'"$org_name"'/[^"]+"' \
            | cut -d'"' -f4 | sort -u \
            > "$SCAN_DIR/package_list.txt" || true
}

fetch_user_packages() {
    local user_name=$1
    log "Fetching user packages for $user_name"
        curl -s "https://www.npmjs.com/~$user_name" \
            | grep -oP '"name":"[^"]+"' \
            | cut -d'"' -f4 \
            | sort -u \
            > "$SCAN_DIR/package_list.txt" || true
}

fetch_versions() {
    local package=$1
    log "Fetching versions for $package"
    curl -s "https://registry.npmjs.org/$package" \
        | jq -r '.versions | keys[]' \
        > "$SCAN_DIR/versions.txt"
}

load_patterns() {
    local patterns_file=$1
    if jq -e 'type == "object"' "$patterns_file" >/dev/null 2>&1; then
        jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$patterns_file" > "$SCAN_DIR/patterns.tsv"
    elif jq -e 'type == "array"' "$patterns_file" >/dev/null 2>&1; then
        jq -r '.[] | "\(.name)\t\(.pattern)"' "$patterns_file" > "$SCAN_DIR/patterns.tsv"
    else
        log "Error: Invalid patterns file format"
        exit 1
    fi
}

scan_file() {
    local file=$1
    local package=$2
    local version=$3

    while IFS=$'\t' read -r pattern_name pattern; do
        if [ -z "$pattern_name" ] || [ -z "$pattern" ]; then
            continue
        fi
        grep -H -n -E -o "$pattern" "$file" 2>/dev/null | while read -r match; do
            echo "FOUND: $package@$version - $pattern_name - $match"
        done
    done < "$SCAN_DIR/patterns.tsv"
}

scan_package_version() {
    local package=$1
    local version=$2
    local tmp_dir=$(mktemp -d)
    log "Downloading $package@$version"
    local tarball_name
    if [[ "$package" == @* ]]; then
        tarball_name=$(echo "$package" | sed 's/^@//' | sed 's/\//-/g')
    else
        tarball_name="$package"
    fi
    local tar_file="$tmp_dir/package.tar.gz"
    curl -s "https://registry.npmjs.org/$package/-/$tarball_name-$version.tgz" -o "$tar_file"
    if [ -s "$tar_file" ]; then
        log "Extracting $package@$version"
        tar -xzf "$tar_file" -C "$tmp_dir" 2>/dev/null || true
        log "Scanning $package@$version"
        find "$tmp_dir" -type f \( -name "*.js" -o -name "*.json" -o -name "*.ts" -o -name "*.txt" \) | while read -r file; do
            while IFS=$'\t' read -r pattern_name pattern; do
                if [ -z "$pattern_name" ] || [ -z "$pattern" ]; then
                    continue
                fi
                grep --color=always -H -n -E -o "$pattern" "$file" 2>/dev/null | while read -r match; do
                    echo "FOUND: $package@$version - $pattern_name - $match"
                done
            done < "$SCAN_DIR/patterns.tsv"
        done
    else
        log "Failed to download $package@$version"
    fi
    
    rm -rf "$tmp_dir"
}
if [ $# -eq 0 ]; then
    echo "Usage: $0 --user <username> | --org <orgname> [--patterns <patterns_file>]"
    exit 1
fi

PATTERNS_FILE="regex.json"
SCAN_DIR=$(mktemp -d)
trap 'rm -rf "$SCAN_DIR"' EXIT

while [[ $# -gt 0 ]]; do
    case $1 in
        --user)
            TARGET_TYPE="user"
            TARGET="$2"
            shift 2
            ;;
        --org)
            TARGET_TYPE="org"
            TARGET="$2"
            shift 2
            ;;
        --patterns)
            PATTERNS_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ -z "$TARGET" ] || [ -z "$TARGET_TYPE" ]; then
    echo "Must specify either --user or --org with a target name"
    exit 1
fi

if [ ! -f "$PATTERNS_FILE" ]; then
    echo "Patterns file $PATTERNS_FILE not found"
    exit 1
fi

load_patterns "$PATTERNS_FILE"

if [ "$TARGET_TYPE" = "org" ]; then
    fetch_org_packages "$TARGET"
else
    fetch_user_packages "$TARGET"
fi

if [ ! -s "$SCAN_DIR/package_list.txt" ]; then
    log "No packages found for $TARGET"
    exit 1
fi

log "Found $(wc -l < "$SCAN_DIR/package_list.txt") packages"

while read -r package; do
    if [ -n "$package" ]; then
        log "Processing package: $package"
        fetch_versions "$package"
        if [ ! -s "$SCAN_DIR/versions.txt" ]; then
            log "No versions found for $package"
            continue
        fi
        while read -r version; do
            if [ -n "$version" ]; then
                scan_package_version "$package" "$version"
            fi
        done < "$SCAN_DIR/versions.txt"
    fi
done < "$SCAN_DIR/package_list.txt"
