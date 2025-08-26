#!/bin/bash
#export GITHUB_TOKEN=

ORG="${1:-}"
[ -z "$ORG" ] && { echo "Usage: $0 <organization>"; exit 1; }

OUTPUT_DIR="output/${ORG}_supplyChain"
mkdir -p "$OUTPUT_DIR"

declare -A COUNTERS
COUNTERS["json"]=1
COUNTERS["txt"]=1
COUNTERS["rb"]=1
COUNTERS["xml"]=1
COUNTERS["yml"]=1
COUNTERS["js"]=1

echo -e "\e[33m🔍\e[0m Searching \e[31m$ORG\e[0m repositories..."
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

    echo -e "\e[32m✅ \e[0m$path →  $filename "
    ((COUNTERS[$ext]++))
}

while IFS= read -r REPO; do
    echo -e "\e[31m📦\e[0m Processing $REPO"
    BRANCH=$(gh repo view "$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name')

    for FILE in "package.json" "package-lock.json" "Pipfile" "pyproject.toml" "poetry.lock" "Pipfile.lock" "requirements.txt" "Gemfile" "*.gemspec" "Gemfile.lock" "pom.xml" "setting.xml" "docker-compose.yml"; do
        EXT="${FILE##*.}"
        [[ "$FILE" == "Gemfile" || "$FILE" == "*.gemspec" || "$FILE" == "Gemfile.lock" ]] && EXT="rb"
        [[ "$FILE" == "Pipfile" || "$FILE" == "pyproject.toml" || "$FILE" == "poetry.lock" || "$FILE" == "Pipfile.lock" ]] && EXT="txt"
        if gh api "repos/$REPO/contents/$FILE?ref=$BRANCH" &>/dev/null; then
            download_file "$REPO" "$BRANCH" "$FILE" "$EXT"
        fi
    done

    gh api "repos/$REPO/git/trees/$BRANCH?recursive=1" --jq '.tree[] | .path' 2>/dev/null | while read -r NESTED_PATH; do
        EXT="${NESTED_PATH##*.}"
        
        if [[ "$NESTED_PATH" =~ (package.json|package-lock.json|Pipfile|pyproject.toml|poetry.lock|Pipfile.lock|requirements.txt|Gemfile|Gemfile.lock|\.gemspec|pom.xml|setting.xml|docker-compose.yml)$ ]]; then
            [[ "$NESTED_PATH" == *Gemfile || "$NESTED_PATH" == *Gemfile.lock || "$NESTED_PATH" == *.gemspec ]] && EXT="rb"
            [[ "$NESTED_PATH" == *Pipfile || "$NESTED_PATH" == *Pipfile.lock || "$NESTED_PATH" == *poetry.lock || "$NESTED_PATH" == *pyproject.toml ]] && EXT="txt"
            download_file "$REPO" "$BRANCH" "$NESTED_PATH" "$EXT"
        fi

    
        if [[ "$EXT" == "js" ]]; then
            download_file "$REPO" "$BRANCH" "$NESTED_PATH" "js"
        fi
    done

done <<< "$REPO_LIST"

# ---- Final stats ----
echo -e "✨ Downloaded : \e[32m$(ls $OUTPUT_DIR/ | grep "json" | wc -l)\e[0m package.json"
echo -e "✨ Downloaded : \e[32m$(ls $OUTPUT_DIR/ | grep "txt" | wc -l)\e[0m requirements.txt"
echo -e "✨ Downloaded : \e[32m$(ls $OUTPUT_DIR/ | grep "rb" | wc -l)\e[0m Gemfiles"
echo -e "✨ Downloaded : \e[32m$(ls $OUTPUT_DIR/ | grep "xml" | wc -l)\e[0m Maven files"
echo -e "✨ Downloaded : \e[32m$(ls $OUTPUT_DIR/ | grep "yml" | wc -l)\e[0m Docker files"
echo -e "✨ Downloaded : \e[32m$(ls $OUTPUT_DIR/ | grep "js" | wc -l)\e[0m JS files"
echo
