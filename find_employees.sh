#!/bin/bash
set -euo pipefail

HUNTER_API_KEY="eecaf22699bf4895331d3ef88ed58a1b04e898771337"
GITHUB_TOKEN=github_pat_11BVL74EY0RYypJOvd2cpO_z5O8dftv
USER_AGENT_FILE=""
USE_PROXY=0

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <domain> <github_org>"
    exit 1
fi

DOMAIN=$1
ORG=$2
OUTPUT="GITHUB/$ORG"

mkdir -p "$OUTPUT"
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
PURPLE=$(tput setaf 5)
ORANGE=$(tput setaf 214 2>/dev/null || echo "$YELLOW")
NC=$(tput sgr0)

random_ip() {
    echo $((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256))
}

get_random_ua() {
    if [[ -f "$USER_AGENT_FILE" && -s "$USER_AGENT_FILE" ]]; then
        shuf -n 1 "$USER_AGENT_FILE"
    else
        cat <<EOF | shuf -n 1
Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/115.0
Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15
Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) Safari/604.1
Mozilla/5.0 (Linux; Android 13; SM-S901B) Chrome/112.0.0.0
Mozilla/5.0 (X11; Linux x86_64) Firefox/115.0
EOF
    fi
}

make_api_request() {
    local endpoint="$1"
    local form_field="$2"
    local domain="$3"
    local rand_ip=$(random_ip)
    local rand_ua=$(get_random_ua)

    curl -s --location --request POST "$endpoint" \
        --header "User-Agent: $rand_ua" \
        --header "Accept: application/json" \
        --header "X-Forwarded-For: $rand_ip" \
        --header "X-Real-IP: $rand_ip" \
        --form "${form_field}=${domain}" \
        --compressed \
        --connect-timeout 15 \
        --max-time 30
}

collect_emails() {
    echo -e "${YELLOW}[*] Searching emails for $DOMAIN...${NC}"
    > "$OUTPUT/${ORG}.emails"

    response=$(make_api_request "https://api.ful.io/email-search-website" "domain_url" "$DOMAIN")
    results=$(echo "$response" | jq -c '.results_found[]?')
    while IFS= read -r result; do
        email=$(echo "$result" | jq -r '.Email')
        [[ -n "$email" ]] && echo "$email" >> "$OUTPUT/${ORG}.emails"
        echo -e "${CYAN}â†³ $email${NC}"
    done <<< "$results"

    curl -s "https://api.hunter.io/v2/domain-search?domain=${DOMAIN}&api_key=${HUNTER_API_KEY}" |
        jq -r '.data.emails[].value' |
        tee -a "$OUTPUT/${ORG}.emails" |
        while IFS= read -r email; do
            echo -e "${CYAN}â†³ $email${NC}"
        done

    sort -u "$OUTPUT/${ORG}.emails" -o "$OUTPUT/${ORG}.emails"
}

# GitHub API helper with robust header handling
github_api_request() {
    local url="$1"
    local max_retries=5
    local retry_delay=10
    local retry_count=0
    local response
    local http_status
    local headers

    while [[ $retry_count -lt $max_retries ]]; do
        headers=$(mktemp)
        response=$(curl -s -D "$headers" -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" "$url")
        http_status=${response: -3}
        body=${response%???}
        
        if [[ "$http_status" == "200" ]]; then
            echo "$body"
            rm -f "$headers"
            return 0
        fi
        
        # Handle rate limits
        if [[ "$http_status" == "403" ]]; then
            reset_time=$(grep -i 'x-ratelimit-reset' "$headers" | awk '{print $2}' | tr -d '\r')
            if [[ -n "$reset_time" ]]; then
                local now=$(date +%s)
                local wait_seconds=$((reset_time - now + 10))
                if [[ $wait_seconds -lt 0 ]]; then
                    wait_seconds=10
                fi
                echo -e "${RED}âœ— GitHub rate limit exceeded. Waiting ${wait_seconds} seconds...${NC}" >&2
                sleep "$wait_seconds"
                retry_count=$((retry_count + 1))
                rm -f "$headers"
                continue
            fi
        fi
        
        # Handle other errors
        if [[ "$http_status" == "403" ]]; then
            echo -e "${RED}âœ— GitHub rate limit exceeded. Retrying in ${retry_delay} seconds...${NC}" >&2
        else
            echo -e "${RED}âœ— GitHub API error: HTTP ${http_status}${NC}" >&2
        fi
        
        sleep "$retry_delay"
        retry_delay=$((retry_delay * 2))
        retry_count=$((retry_count + 1))
        rm -f "$headers"
    done

    echo -e "${RED}âœ— Failed after ${max_retries} retries for ${url}${NC}" >&2
    rm -f "$headers"
    return 1
}

fetch_org_members() {
    echo -e "${YELLOW}[*] Fetching GitHub org members for $ORG...${NC}"
    local page=1
    > "$OUTPUT/${ORG}.employees"

    while :; do
        response=$(github_api_request "https://api.github.com/orgs/${ORG}/members?per_page=100&page=${page}")
        [[ -z "$response" ]] && break
        
        echo "$response" | jq -r '.[].login' >> "$OUTPUT/${ORG}.employees"
        
        # Check for next page using headers
        next_url=$(curl -sI -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/orgs/${ORG}/members?per_page=100&page=${page}" |
            grep -i '^link:.*rel="next"' | sed -n 's/.*<\([^>]*\)>; rel="next".*/\1/p')
        
        if [[ -z "$next_url" ]]; then
            break
        fi
        ((page++))
        sleep 1
    done
}

search_by_email() {
    echo -e "${YELLOW}[*] Searching GitHub by collected emails...${NC}"
    while IFS= read -r email; do
        [[ -z "$email" ]] && continue
        github_api_request "https://api.github.com/search/users?q=${email}" |
            jq -r '.items[].login' >> "$OUTPUT/${ORG}.employees"
        sleep 1
    done < "$OUTPUT/${ORG}.emails"
}

validate_users() {
    echo -e "${YELLOW}[*] Validating GitHub usernames...${NC}"
    local input_file="$OUTPUT/${ORG}.employees"
    local output_file="$OUTPUT/${ORG}-employees.valid"
    > "$output_file"
    sort -u "$input_file" -o "$input_file"
    sed -i '/^$/d' "$input_file"

    while IFS= read -r username; do
        [[ -z "$username" ]] && continue
        if ! [[ "$username" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
            echo -e "${RED}âœ— INVALID: '$username' (format)${NC}"
            continue
        fi

        http_status=$(curl -s -w "%{http_code}" -o /dev/null \
            -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/users/$username") || true

        if [[ "$http_status" -ne 200 ]]; then
            echo -e "${RED}âœ— INVALID: '$username' (not found)${NC}"
            continue
        fi

        if curl -sfS -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/orgs/${ORG}/members/${username}" > /dev/null; then
            echo "$username" >> "$output_file"
            echo -e "${GREEN}âœ“ VALID: $username${NC}"
        else
            echo -e "${YELLOW}- Valid GitHub user but not in $ORG: $username${NC}"
        fi
    done < "$input_file"

    echo -e "${GREEN}[*] Validation done. Results saved in: $OUTPUT/${ORG}-employees.valid${NC}"
}

main() {
    if [[ -z "${GITHUB_TOKEN}" || -z "${HUNTER_API_KEY}" ]]; then
        echo -e "${RED}Error: GITHUB_TOKEN or HUNTER_API_KEY not set.${NC}"
        exit 1
    fi

    collect_emails
    fetch_org_members
    search_by_email
    validate_users
}

# Check arguments before proceeding
if [[ $# -lt 2 ]]; then
    echo -e "${RED}Usage: $0 <domain> <github_org>${NC}"
    exit 1
fi

main
