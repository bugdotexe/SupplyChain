#!/bin/bash
export GITHUB_TOKEN=""

ORG="${1:-}"
[ -z "$ORG" ] && { echo "Usage: $0 <organization>"; exit 1; }

OUTPUT_DIR="${ORG}_supplyChain"
mkdir -p "$OUTPUT_DIR"

declare -A COUNTERS
COUNTERS["json"]=1
COUNTERS["txt"]=1
COUNTERS["rb"]=1

echo "🔍 Searching $ORG repositories..."
REPO_LIST=$(gh search repos --owner "$ORG" --json name,owner --jq '.[] | .owner.login + "/" + .name' --limit 1000)

next_available_filename() {
    local ext=$1
    while :; do
        local filename=$(printf "%s%04d.%s" "$ext" "${COUNTERS[$ext]}" "$ext")
        if [[ ! -e "$OUTPUT_DIR/$filename" ]]; then
            echo "$filename"
            return
        fi
        ((COUNTERS[$ext]++))
    done
}

download_file() {
    local repo="$1"
    local branch="$2"
    local path="$3"
    local ext="$4"

    local filename
    filename=$(next_available_filename "$ext")

    gh api "repos/$repo/contents/$path?ref=$branch" --jq '.content' 2>/dev/null | \
        base64 --decode > "$OUTPUT_DIR/$filename"

    echo "✅ $path → $filename"
    ((COUNTERS[$ext]++))
}

while IFS= read -r REPO; do
    echo "📦 Processing $REPO"
    BRANCH=$(gh repo view "$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name')

    for FILE in "package.json" "requirements.txt" "Gemfile"; do
        EXT="${FILE##*.}"
        [[ "$FILE" == "Gemfile" ]] && EXT="rb"

        if gh api "repos/$REPO/contents/$FILE?ref=$BRANCH" &>/dev/null; then
            download_file "$REPO" "$BRANCH" "$FILE" "$EXT"
        fi
    done

    gh api "repos/$REPO/git/trees/$BRANCH?recursive=1" --jq '.tree[] | select(.path | test("package.json$|requirements.txt$|Gemfile$")) | .path' 2>/dev/null | \
    while read -r NESTED_PATH; do
        EXT="${NESTED_PATH##*.}"
        [[ "$NESTED_PATH" == *Gemfile ]] && EXT="rb"
        download_file "$REPO" "$BRANCH" "$NESTED_PATH" "$EXT"
    done

done <<< "$REPO_LIST"


echo "✨ Download complete:"
echo "📂 Saved in: $OUTPUT_DIR/"
echo
echo
