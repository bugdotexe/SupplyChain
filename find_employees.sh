#!/bin/bash
set -euo pipefail
"
HUNTER_API_KEY=""
USER_AGENT_FILE=""
USE_PROXY=0

DOMAIN=$1
ORG=$2

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
        local uas=(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/115.0"
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15"
            "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) Safari/604.1"
            "Mozilla/5.0 (Linux; Android 13; SM-S901B) Chrome/112.0.0.0"
            "Mozilla/5.0 (X11; Linux x86_64) Firefox/115.0"
        )
        echo "${uas[$RANDOM % ${#uas[@]}]}"
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
    > "${DOMAIN}.emails"

    response=$(make_api_request "https://api.ful.io/email-search-website" "domain_url" "$DOMAIN")
    results=$(echo "$response" | jq -c '.results_found[]?')
    while IFS= read -r result; do
        email=$(echo "$result" | jq -r '.Email')
        [[ -n "$email" ]] && echo "$email" >> "${DOMAIN}.emails"
        echo -e "${CYAN}↳ $email${NC}"
    done <<< "$results"

    curl -s "https://api.hunter.io/v2/domain-search?domain=${DOMAIN}&api_key=${HUNTER_API_KEY}" |
        jq -r '.data.emails[].value' |
        tee -a "${DOMAIN}.emails" |
        while IFS= read -r email; do
            echo -e "${CYAN}↳ $email${NC}"
        done

    sort -u "${DOMAIN}.emails" -o "${DOMAIN}.emails"
}

fetch_org_members() {
    echo -e "${YELLOW}[*] Fetching GitHub org members for $ORG...${NC}"
    local page=1
    > "${DOMAIN}_employees.txt"

    while :; do
        response=$(curl -sfS -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/orgs/${ORG}/members?per_page=100&page=${page}")
        echo "$response" | jq -r '.[].login' >> "${DOMAIN}_employees.txt"

        link_header=$(curl -sI -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/orgs/${ORG}/members?per_page=100&page=${page}")
        if ! grep -q 'rel="next"' <<< "$link_header"; then
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
        curl -sfS -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/search/users?q=${email}" |
            jq -r '.items[].login' >> "${DOMAIN}_employees.txt"
        sleep 1
    done < "${DOMAIN}.emails"
}

validate_users() {
    echo -e "${YELLOW}[*] Validating GitHub usernames...${NC}"
    local input_file="${DOMAIN}_employees.txt"
    local output_file="${ORG}_valid_employees.txt"
    > "$output_file"
    sort -u "$input_file" -o "$input_file"
    sed -i '/^$/d' "$input_file"

    while IFS= read -r username; do
        [[ -z "$username" ]] && continue
        if ! [[ "$username" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
            echo -e "${RED}✗ INVALID: '$username' (format)${NC}"
            continue
        fi

        code=$(curl -sfS -w "%{http_code}" -o /dev/null \
            -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/users/$username") || true

        if [[ "$code" -ne 200 ]]; then
            echo -e "${RED}✗ INVALID: '$username' (not found)${NC}"
            continue
        fi

        if curl -sfS -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/orgs/${ORG}/members/${username}" > /dev/null; then
            echo "$username" >> "$output_file"
            echo -e "${GREEN}✓ VALID: $username${NC}"
        else
            echo -e "${YELLOW}- Valid GitHub user but not in $ORG: $username${NC}"
        fi
    done < "$input_file"

    echo -e "${GREEN}[*] Validation done. Results saved in: ${ORG}_valid_employees.txt${NC}"
}

main() {
    if [[ -z "$DOMAIN" || -z "$ORG" ]]; then
        echo -e "${RED}Usage: $0 <domain> <github_org>${NC}"
        exit 1
    fi

    if [[ -z "${GITHUB_TOKEN}" || -z "${HUNTER_API_KEY}" ]]; then
        echo -e "${RED}Error: GITHUB_TOKEN or HUNTER_API_KEY not set.${NC}"
        exit 1
    fi

    collect_emails
    fetch_org_members
    search_by_email
    validate_users
}

main
