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
echo -e "${GREEN}[+] Results will be saved in: $RESULTS_DIR${NC}"

domain_to_org_names() {
    local domain=$1
    local base_name=$(echo "$domain" | cut -d. -f1)
    local tld=$(echo "$domain" | cut -d. -f2)
    local no_dots=$(echo "$domain" | tr -d '.')

    echo "$no_dots"
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

echo -e "${CYAN}[+] Searching for repositories that clearly belong to $DOMAIN${NC}"
search_github "repositories" "$DOMAIN" | jq . > "$RESULTS_DIR/domain_repositories_response.json"
repos_count=$(count_items "$RESULTS_DIR/domain_repositories_response.json")
echo -e "${GREEN}[+] Found $repos_count repositories mentioning $DOMAIN${NC}"

jq -r '.items[].owner.login' "$RESULTS_DIR/domain_repositories_response.json" 2>/dev/null | sort -u > "$RESULTS_DIR/potential_orgs_from_repos.txt"

echo -e "${CYAN}[+] Searching for organizations with $DOMAIN in their website/blog${NC}"
search_github "users" "type:org $DOMAIN in:blog" | jq . > "$RESULTS_DIR/orgs_with_domain_in_blog.json"
orgs_blog_count=$(count_items "$RESULTS_DIR/orgs_with_domain_in_blog.json")
echo -e "${GREEN}[+] Found $orgs_blog_count organizations with $DOMAIN in their blog${NC}"

jq -r '.items[].login' "$RESULTS_DIR/orgs_with_domain_in_blog.json" 2>/dev/null >> "$RESULTS_DIR/potential_orgs_from_repos.txt"

sort -u "$RESULTS_DIR/potential_orgs_from_repos.txt" > "$RESULTS_DIR/potential_orgs.txt"

echo -e "${CYAN}[+] Checking potential organizations from repositories and blog links${NC}"
CONFIRMED_ORG=""
BEST_MATCH=""
BEST_MATCH_SCORE=0

while read -r org_name; do
    if [ -n "$org_name" ]; then
        echo -e "${BLUE}[+] Checking organization: $org_name${NC}"
        org_result=$(github_api "orgs/$org_name")
        if [ "$(echo "$org_result" | jq -r '.message' 2>/dev/null)" != "Not Found" ]; then
            echo "$org_result" | jq . > "$RESULTS_DIR/organization.json"
            org_url=$(echo "$org_result" | jq -r '.html_url')
            blog_url=$(echo "$org_result" | jq -r '.blog')
            echo -e "${GREEN}[+] Found organization: $org_url${NC}"
            
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
    echo -e "${YELLOW}[+] No confirmed organization found, trying common patterns${NC}"
    
    ORG_NAMES=($(domain_to_org_names "$DOMAIN" | sort -u))
    
    for org_name in "${ORG_NAMES[@]}"; do
        echo -e "${BLUE}[+] Trying pattern: $org_name${NC}"
        org_result=$(github_api "orgs/$org_name")
        if [ "$(echo "$org_result" | jq -r '.message' 2>/dev/null)" != "Not Found" ]; then
            echo "$org_result" | jq . > "$RESULTS_DIR/organization.json"
            org_url=$(echo "$org_result" | jq -r '.html_url')
            blog_url=$(echo "$org_result" | jq -r '.blog')
            echo -e "${GREEN}[+] Found organization: $org_url${NC}"
            
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
fi

# 7. Search for users with company matching the domain
echo -e "${CYAN}[+] Searching for users associated with $DOMAIN${NC}"
search_github "users" "$DOMAIN" | jq . > "$RESULTS_DIR/users_response.json"
users_count=$(count_items "$RESULTS_DIR/users_response.json")
echo -e "${GREEN}[+] Found $users_count users${NC}"

# 8. Search for code containing the domain
echo -e "${CYAN}[+] Searching for code containing $DOMAIN${NC}"
search_github "code" "$DOMAIN" | jq . > "$RESULTS_DIR/code_mentions_response.json"
code_count=$(count_items "$RESULTS_DIR/code_mentions_response.json")
echo -e "${GREEN}[+] Found $code_count code mentions${NC}"

# 9. Search for employees mentioning the domain in their profiles
echo -e "${CYAN}[+] Searching for users with $DOMAIN in their profile${NC}"
search_github "users" "in:email $DOMAIN" | jq . > "$RESULTS_DIR/email_users_response.json"
search_github "users" "in:bio $DOMAIN" | jq . > "$RESULTS_DIR/bio_users_response.json"
email_users_count=$(count_items "$RESULTS_DIR/email_users_response.json")
bio_users_count=$(count_items "$RESULTS_DIR/bio_users_response.json")
echo -e "${GREEN}[+] Found $email_users_count users with email from $DOMAIN${NC}"
echo -e "${GREEN}[+] Found $bio_users_count users with $DOMAIN in bio${NC}"

# 10. Search for commits containing the domain
echo -e "${CYAN}[+] Searching for commits mentioning $DOMAIN${NC}"
search_github "commits" "$DOMAIN" | jq . > "$RESULTS_DIR/commits_response.json"
commits_count=$(count_items "$RESULTS_DIR/commits_response.json")
echo -e "${GREEN}[+] Found $commits_count commits${NC}"

# Extract just the items from responses for easier processing
jq '.items' "$RESULTS_DIR/users_response.json" > "$RESULTS_DIR/users.json" 2>/dev/null
jq '.items' "$RESULTS_DIR/domain_repositories_response.json" > "$RESULTS_DIR/domain_repositories.json" 2>/dev/null
jq '.items' "$RESULTS_DIR/code_mentions_response.json" > "$RESULTS_DIR/code_mentions.json" 2>/dev/null
jq '.items' "$RESULTS_DIR/email_users_response.json" > "$RESULTS_DIR/email_users.json" 2>/dev/null
jq '.items' "$RESULTS_DIR/bio_users_response.json" > "$RESULTS_DIR/bio_users.json" 2>/dev/null
jq '.items' "$RESULTS_DIR/commits_response.json" > "$RESULTS_DIR/commits.json" 2>/dev/null

# 11. Generate summary report
echo -e "${CYAN}[+] Generating summary report${NC}"
{
    echo "GitHub OSINT Report for $DOMAIN"
    echo "Generated on: $(date)"
    echo ""
    echo "Organization:"
    if [ -n "$CONFIRMED_ORG" ]; then
        echo "  Name: $CONFIRMED_ORG"
        echo "  URL: $(jq -r '.html_url' "$RESULTS_DIR/organization.json" 2>/dev/null || echo "Unknown")"
        echo "  Repositories: $org_repos_count"
    else
        echo "  Not found directly"
        echo "  Repositories mentioning domain: $repos_count"
        echo "  Orgs with $DOMAIN in blog: $orgs_blog_count"
    fi
    echo ""
    echo "Users associated with domain: $users_count"
    echo "Repositories mentioning domain: $repos_count"
    echo "Code mentions: $code_count"
    echo "Users with domain in email: $email_users_count"
    echo "Users with domain in bio: $bio_users_count"
    echo "Commits mentioning domain: $commits_count"
    echo ""
    echo "Potential organizations:"
    if [ -f "$RESULTS_DIR/potential_orgs.txt" ]; then
        cat "$RESULTS_DIR/potential_orgs.txt" | while read line; do
            echo "  $line"
        done
    else
        echo "  None found"
    fi
} > "$RESULTS_DIR/summary.txt"

echo -e "${GREEN}[+] OSINT complete! Results saved in $RESULTS_DIR/${NC}"
echo -e "${GREEN}[+] Review the files for potential sensitive information${NC}"

# Display a quick summary
echo -e "\n${CYAN}=== QUICK SUMMARY ===${NC}"
if [ -n "$CONFIRMED_ORG" ]; then
    echo -e "${GREEN}Organization: $CONFIRMED_ORG${NC}"
else
    echo -e "${YELLOW}Organization: Not directly found${NC}"
fi
echo -e "${GREEN}Repositories: $repos_count${NC}"
echo -e "${GREEN}Code mentions: $code_count${NC}"
echo -e "${GREEN}Users: $users_count${NC}"
echo -e "${GREEN}Commits: $commits_count${NC}"
