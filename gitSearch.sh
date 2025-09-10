#!/bin/bash
#export GITHUB_TOKEN=

ORG="${1:-}"
[ -z "$ORG" ] && { echo "Usage: $0 <organization>"; exit 1; }

OUTPUT_DIR="GITHUB/$ORG/$DOMAIN"
mkdir -p "$OUTPUT_DIR"

echo -e "\e[33mðŸ”\e[0m Searching \e[31m$ORG\e[0m repositories..."
REPO_LIST=$(gh search repos --owner "$ORG" --json name,owner --jq '.[] | .owner.login + "/" + .name' --limit 1000)

# Create a safe unique filename from repo + branch + path
make_safe_filename() {
    local repo="$1"
    local branch="$2"
    local path="$3"
    local ext="$4"

    # Replace / with _
    local safe_repo=$(echo "$repo" | tr '/:' '_')
    local safe_path=$(echo "$path" | tr '/:' '_')
    local safe_branch=$(echo "$branch" | tr '/:' '_')

    echo "${safe_repo}_${safe_branch}_${safe_path}.${ext}"
}

download_file() {
    local repo="$1"
    local branch="$2"
    local path="$3"
    local ext="$4"

    local filename
    filename=$(make_safe_filename "$repo" "$branch" "$path" "$ext")

    # If somehow the filename exists, add timestamp suffix
    if [[ -e "$OUTPUT_DIR/$filename" ]]; then
        filename="${filename%.*}_$(date +%s%N).$ext"
    fi

    gh api "repos/$repo/contents/$path?ref=$branch" --jq '.content' 2>/dev/null | \
        base64 --decode > "$OUTPUT_DIR/$filename"

    echo -e "\e[32mâœ… \e[0m$path â†’ $filename "
}

while IFS= read -r REPO; do
    echo -e "\e[31mðŸ“¦\e[0m Processing $REPO"
    BRANCH=$(gh repo view "$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name')

    for FILE in "package.json" "package-lock.json" "Pipfile" "pyproject.toml" "poetry.lock" "Pipfile.lock" "requirements.txt" "Gemfile" "*.gemspec" "Gemfile.lock" "pom.xml" "setting.xml" "docker-compose.yml" "docker-*.yml"; do
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

echo -e "âœ¨ Downloaded : \e[32m$(ls $OUTPUT_DIR/ | grep "json" | wc -l)\e[0m package.json"
echo -e "âœ¨ Downloaded : \e[32m$(ls $OUTPUT_DIR/ | grep "txt" | wc -l)\e[0m requirements.txt"
echo -e "âœ¨ Downloaded : \e[32m$(ls $OUTPUT_DIR/ | grep "rb" | wc -l)\e[0m Gemfiles"
echo -e "âœ¨ Downloaded : \e[32m$(ls $OUTPUT_DIR/ | grep "xml" | wc -l)\e[0m Maven files"
echo -e "âœ¨ Downloaded : \e[32m$(ls $OUTPUT_DIR/ | grep "yml" | wc -l)\e[0m Docker files"
echo -e "âœ¨ Downloaded : \e[32m$(ls $OUTPUT_DIR/ | grep "js" | wc -l)\e[0m JS files"
