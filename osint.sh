#!/bin/bash

# GitHub OSINT script for bug bounty targets

if [ $# -eq 0 ]; then
    echo "Usage: $0 <domain>"
    echo "Example: $0 fofa.info"
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

DOMAIN=$1
TOKEN="${GITHUB_TOKEN}"
RESULTS_DIR="$DOMAIN"
mkdir -p "$RESULTS_DIR"

echo -e "${GREEN}[+] Starting GitHub OSINT for domain: $DOMAIN${NC}"
domain_to_org_names() {
    local domain=$1
    local base_name=$(echo "$domain" | cut -d. -f1)
    local tld=$(echo "$domain" | cut -d. -f2)
    local no_dots=$(echo "$domain" | tr -d '.')
    
    echo "$base_name"
    echo "${base_name}-${tld}"
    echo "${base_name}-inc"
    echo "${base_name}-org"
    echo "${base_name}-tech"
    echo "${base_name}-labs"
    echo "${base_name}-corp"
    echo "${base_name}0x01"
    echo "${base_name}io"
    echo "${base_name}app"
    echo "${base_name}cloud"
    echo "${base_name}-Cash"
    echo "${base_name}-protocol"
    echo "${base_name}-dao"
    echo "${base_name}-pool"
    echo "${base_name}-network"
    echo "${base_name}-labs"
    echo "${base_name}-fi"
    echo "$no_dots"
}

github_api() {
    local endpoint=$1
    local url="https://api.github.com/$endpoint"
    
    if [ -z "$TOKEN" ]; then
        curl -s -H "Accept: application/vnd.github.v3+json" "$url"
    else
        curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" "$url"
    fi
}

search_github() {
    local type=$1
    local query=$2
    local url="https://api.github.com/search/$type?q=$query&per_page=100"
    
    if [ -z "$TOKEN" ]; then
        curl -s -H "Accept: application/vnd.github.v3+json" "$url"
    else
        curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" "$url"
    fi
}

count_items() {
    local file=$1
    if [ -f "$file" ] && [ -s "$file" ]; then
        count=$(jq '.items | length' "$file" 2>/dev/null)
        echo "${count:-0}"
    else
        echo "0"
    fi
}

search_github "repositories" "$DOMAIN" | jq . > "$RESULTS_DIR/domain_repositories_response.json"
repos_count=$(count_items "$RESULTS_DIR/domain_repositories_response.json")

jq -r '.items[].owner.login' "$RESULTS_DIR/domain_repositories_response.json" 2>/dev/null | sort -u > "$RESULTS_DIR/potential_orgs_from_repos.txt"

search_github "users" "type:org $DOMAIN in:blog" | jq . > "$RESULTS_DIR/orgs_with_domain_in_blog.json"
orgs_blog_count=$(count_items "$RESULTS_DIR/orgs_with_domain_in_blog.json")

jq -r '.items[].login' "$RESULTS_DIR/orgs_with_domain_in_blog.json" 2>/dev/null >> "$RESULTS_DIR/potential_orgs_from_repos.txt"

sort -u "$RESULTS_DIR/potential_orgs_from_repos.txt" > "$RESULTS_DIR/potential_orgs.txt"

CONFIRMED_ORG=""
BEST_MATCH=""
BEST_MATCH_SCORE=0

while read -r org_name; do
    if [ -n "$org_name" ]; then
        org_result=$(github_api "orgs/$org_name")
        if [ "$(echo "$org_result" | jq -r '.message' 2>/dev/null)" != "Not Found" ]; then
            echo "$org_result" | jq . > "$RESULTS_DIR/organization.json"
            org_url=$(echo "$org_result" | jq -r '.html_url')
            blog_url=$(echo "$org_result" | jq -r '.blog')
            
            match_score=0
            
            if [[ "$blog_url" == *"$DOMAIN"* ]]; then
                echo -e "${GREEN}[+] CONFIRMED: $org_name has $DOMAIN in their blog URL${NC}"
                CONFIRMED_ORG="$org_name"
                break
            else
                repo_check=$(search_github "repositories" "user:$org_name $DOMAIN")
                repo_count=$(echo "$repo_check" | jq -r '.total_count' 2>/dev/null)
                if [ -n "$repo_count" ] && [ "$repo_count" -gt 0 ] 2>/dev/null; then
                    echo -e "${GREEN}[+] LIKELY: $org_name has $repo_count repositories mentioning $DOMAIN${NC}"
                    match_score=$((match_score + repo_count))
                fi
                if [[ "$org_name" == *"$(echo "$DOMAIN" | cut -d. -f1)"* ]]; then
                    match_score=$((match_score + 5))
                fi
                
                if [[ "$org_name" == "$(echo "$DOMAIN" | tr -d '.')" ]]; then
                    match_score=$((match_score + 10))
                fi
                
                if [ $match_score -gt $BEST_MATCH_SCORE ]; then
                    BEST_MATCH_SCORE=$match_score
                    BEST_MATCH="$org_name"
                fi
            fi
        fi
    fi
done < "$RESULTS_DIR/potential_orgs.txt"

if [ -z "$CONFIRMED_ORG" ]; then
    
    ORG_NAMES=($(domain_to_org_names "$DOMAIN" | sort -u))
    
    for org_name in "${ORG_NAMES[@]}"; do
        org_result=$(github_api "orgs/$org_name")
        if [ "$(echo "$org_result" | jq -r '.message' 2>/dev/null)" != "Not Found" ]; then
            echo "$org_result" | jq . > "$RESULTS_DIR/organization.json"
            org_url=$(echo "$org_result" | jq -r '.html_url')
            blog_url=$(echo "$org_result" | jq -r '.blog')
            
            match_score=0
            
            if [[ "$blog_url" == *"$DOMAIN"* ]]; then
                echo -e "${GREEN}[+] CONFIRMED: $org_name has $DOMAIN in their blog URL${NC}"
                CONFIRMED_ORG="$org_name"
                break
            else
                repo_check=$(search_github "repositories" "user:$org_name $DOMAIN")
                repo_count=$(echo "$repo_check" | jq -r '.total_count' 2>/dev/null)
                if [ -n "$repo_count" ] && [ "$repo_count" -gt 0 ] 2>/dev/null; then
                    echo -e "${GREEN}[+] LIKELY: $org_name has $repo_count repositories mentioning $DOMAIN${NC}"
                    match_score=$((match_score + repo_count))
                fi
                
                if [[ "$org_name" == *"$(echo "$DOMAIN" | cut -d. -f1)"* ]]; then
                    match_score=$((match_score + 5))
                fi
                
                if [[ "$org_name" == "$(echo "$DOMAIN" | tr -d '.')" ]]; then
                    match_score=$((match_score + 10))
                fi
                
                if [ $match_score -gt $BEST_MATCH_SCORE ]; then
                    BEST_MATCH_SCORE=$match_score
                    BEST_MATCH="$org_name"
                fi
            fi
        fi
    done
fi

if [ -z "$CONFIRMED_ORG" ] && [ -n "$BEST_MATCH" ] && [ $BEST_MATCH_SCORE -gt 0 ]; then
    echo -e "${PURPLE}[+] Using best match: $BEST_MATCH with score $BEST_MATCH_SCORE${NC}"
    CONFIRMED_ORG="$BEST_MATCH"
    org_result=$(github_api "orgs/$CONFIRMED_ORG")
    echo "$org_result" | jq . > "$RESULTS_DIR/organization.json"
    echo -e "${GREEN}[+] Confirmed : $CONFIRMED_ORG ${NC}"
fi

echo -e "${CYAN}[+] Searching for users associated with $DOMAIN${NC}"
search_github "users" "$DOMAIN" | jq . > "$RESULTS_DIR/users_response.json"
users_count=$(count_items "$RESULTS_DIR/users_response.json")
echo -e "${GREEN}[+] Found $users_count users${NC}"

