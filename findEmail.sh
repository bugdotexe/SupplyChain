#!/bin/bash
set -euo pipefail

HUNTER_API_KEY="eecaf22699bf4895331d3ef88ed58a1b04e89877leet"
GITHUB_TOKEN=$GITHUB_TOKEN

DOMAIN=$1
ORG=$2
OUTPUT="/tmp/${ORG}"

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

make_api_request() {
    local endpoint="$1"
    local form_field="$2"
    local domain="$3"
    local rand_ip=$(random_ip)

    curl -s --location --request POST "$endpoint" \
        --header "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) Safari/604.1" \
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

    > "$OUTPUT/users.emails"

    response=$(make_api_request "https://api.ful.io/email-search-website" "domain_url" "$DOMAIN")
    results=$(echo "$response" | jq -c '.results_found[]?')
    while IFS= read -r result; do
        email=$(echo "$result" | jq -r '.Email')
        purified=$(echo ${email} | sed -E 's/u[0-9a-fA-F]{4}//g' | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
        [[ -n "$email" ]] && echo "$email" | sed -E 's/u[0-9a-fA-F]{4}//g' | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | anew "$OUTPUT/users.emails" >/dev/null
        echo -e "${CYAN}[Ful.io] ${purified}${NC}"
    done <<< "$results"

    curl -s "https://api.hunter.io/v2/domain-search?domain=${DOMAIN}&api_key=${HUNTER_API_KEY}" |
        jq -r '.data.emails[].value' | sed -E 's/u[0-9a-fA-F]{4}//g' | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | anew "$OUTPUT/users.emails" |
        while IFS= read -r email; do
            purified=$(echo ${email} | sed -E 's/u[0-9a-fA-F]{4}//g' | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
            echo -e "${CYAN}[Hunter.io] ${purified}${NC}"
        done

    sort -u "$OUTPUT/users.emails" -o "$OUTPUT/users.emails"
}
collect_emails
