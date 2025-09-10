#!/bin/bash

usage() {
    echo "Usage: $0 [--user USERNAME | --org ORGNAME]"
    exit 1
}

fetch_repos() {
    local target=$1
    local target_type=$2
    
    # Try multiple API endpoints
    local models=$(curl -s "https://huggingface.co/api/models?author=$target" | jq -r '.[].modelId' 2>/dev/null)
    local datasets=$(curl -s "https://huggingface.co/api/datasets?author=$target" | jq -r '.[].id' 2>/dev/null)
    local spaces=$(curl -s "https://huggingface.co/api/spaces?author=$target" | jq -r '.[].id' 2>/dev/null)

    echo -e "$models\n$datasets\n$spaces" | grep -v '^$' | sort -u
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --user)
            target="$2"
            target_type="user"
            shift 2
            ;;
        --org)
            target="$2"
            target_type="org"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

if [ -z "$target" ] || [ -z "$target_type" ]; then
    usage
fi

if [ ! -f "regex.json" ]; then
    echo "Error: regex.json file not found"
    exit 1
fi

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

# Fetch repositories
echo "Fetching repositories for $target_type: $target"
repos=$(fetch_repos "$target" "$target_type")

if [ -z "$repos" ]; then
    echo "No repositories found via API, trying web scraping..."
    repos=$(curl -s "https://huggingface.co/$target" | \
            grep -o 'href="/[^"]*"' | \
            grep -E "(models|datasets|spaces)/" | \
            cut -d'"' -f2 | \
            sed 's/^\///' | \
            sort -u)
fi

if [ -z "$repos" ]; then
    echo "No repositories found. The target might not exist or the API might have changed."
    exit 1
fi

echo "Found $(echo "$repos" | wc -l) repositories to scan"
patterns=$(jq -r '.[]' regex.json 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "Error: Invalid JSON format in regex.json"
    patterns=$(jq -r '.[]' regex.json)
fi

for repo in $repos; do
    echo "Scanning $repo..."
    repo_url="https://huggingface.co/$repo"
    clone_dir="$temp_dir/$(echo "$repo" | tr '/' '_')"
    
    GIT_TERMINAL_PROMPT=0 git clone --quiet --depth 1 "$repo_url" "$clone_dir" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "Skipping $repo (private or requires authentication)"
        continue
    fi
    while IFS= read -r pattern; do
        if [ -n "$pattern" ]; then
            grep --color=always -H -r -n -E --binary-files=without-match "$pattern" "$clone_dir" --exclude-dir=.git 2>/dev/null | while read -r match; do
                echo "FOUND in $repo: => $match" | notify -silent
            done
        fi
    done <<< "$patterns"

    rm -rf "$clone_dir"
done
