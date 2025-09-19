#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "$1"; }

usage() {
  cat <<USAGE
Usage:
  ./scanner_gh.sh --org <ORG> [options]
  ./scanner_gh.sh --user <USER> [options]

Options:
  --org <ORG>                 Target organization name on GitHub
  --user <USER>               Target GitHub username
  --token <TOKEN>             GitHub Personal Access Token (optional; if provided, used by gh)
  --output <DIR>              Directory to clone repos into (default: scanned_repos)
  --regex-json <PATH>         Path to regex.json (default: regex.json)
  --mode <urls|secrets|both>   What to scan (default: both)
  --include-archived            Include archived repos (default: skip)
  --skip-clone                  Do not clone repos (assumes repos exist under --output)
  --timeout <SECONDS>           HTTP timeout for URL checks (default: 12)
USAGE
}

# Defaults
OUTPUT_DIR="scanned_repos"
REGEX_JSON="regex.json"
MODE="both"
INCLUDE_ARCHIVED=0
SKIP_CLONE=0
TIMEOUT=12

ORG=""
USER=""

# Parse arguments
if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) ORG="$2"; shift 2 ;;
    --user) USER="$2"; shift 2 ;;
    --token) TOKEN="$2"; shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --regex-json) REGEX_JSON="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --include-archived) INCLUDE_ARCHIVED=1; shift 1 ;;
    --skip-clone) SKIP_CLONE=1; shift 1 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$ORG" && -z "$USER" ]]; then
  echo "Error: You must specify --org or --user."
  usage
  exit 1
fi

if [[ ! -f "$REGEX_JSON" ]]; then
  echo "Error: regex.json not found at $REGEX_JSON"
  exit 1
fi

# If token provided, export for gh to use
if [[ -n "${TOKEN:-}" ]]; then
  export GITHUB_TOKEN="$TOKEN"
fi

# Step 1: Fetch repos via gh api (paginated)
REPOS_LIST_FILE="repos.list.$(date +%s).txt"
> "$REPOS_LIST_FILE"

echo -e "${BLUE}Fetching repos for target using gh...${NC}"
if [[ -n "$ORG" ]]; then
  gh api "orgs/$ORG/repos?type=all&per_page=100" --paginate \
    --jq '.[] | "\(.name)|\(.clone_url)|\(.archived)"' >> "$REPOS_LIST_FILE"
else
  gh api "users/$USER/repos?type=all&per_page=100" --paginate \
    --jq '.[] | "\(.name)|\(.clone_url)|\(.archived)"' >> "$REPOS_LIST_FILE"
fi

if [[ ! -s "$REPOS_LIST_FILE" ]]; then
  echo "No repositories found or API returned nothing."
  exit 0
fi

# Step 2: Clone repos (serial)
OUTPUT_DIR_ABS="$(realpath "$OUTPUT_DIR")"
mkdir -p "$OUTPUT_DIR_ABS"

if [[ "$SKIP_CLONE" -ne 1 ]]; then
  echo -e "${BLUE}Cloning repositories (depth 1) serially...${NC}"
  while IFS='|' read -r NAME CLONE_URL ARCHIVED; do
    if [[ "$INCLUDE_ARCHIVED" -ne 1 && "$ARCHIVED" == "true" ]]; then
      continue
    fi
    DEST="$OUTPUT_DIR_ABS/$NAME"
    if [[ -d "$DEST/.git" ]]; then
      echo -e "${YELLOW}Already cloned: $NAME (skipping)${NC}"
      continue
    fi
    local_url="$CLONE_URL"
    if [[ -n "${TOKEN:-}" ]]; then
      # Inject token into HTTPS URL for authentication
      local_url="${CLONE_URL/https:\/\//https:\/\/$TOKEN@}"
    fi
    echo "Cloning $NAME..."
    if git clone --depth 1 "$local_url" "$DEST" >/dev/null 2>&1; then
      echo -e "${GREEN}[OK] Cloned: $NAME${NC}"
    else
      echo -e "${RED}[ERROR] Failed to clone: $NAME${NC}"
    fi
  done < "$REPOS_LIST_FILE"
else
  echo -e "${YELLOW}Skipping cloning as per --skip-clone.${NC}"
fi

# Step 3: Scan repos for URLs and secrets
echo -e "${BLUE}Scanning downloaded repos for URLs and secrets...${NC}"

# Load secret patterns from regex.json (PCRE)
declare -a SECRET_PATTERNS
while IFS=$'\t' read -r key value; do
  SECRET_PATTERNS+=("$key|$value")
done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$REGEX_JSON")

# URL regex for GitHub links
GH_URL_REGEX='https?://github\.com/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?'

TOTAL_URLS=0
TOTAL_BROKEN=0
TOTAL_GOOD=0
TOTAL_SECRETS=0

# Ensure clipboard-free cleanup file
URLS_TMP="/tmp/gh_scanner_urls_$RANDOM.txt"

for repo_dir in "$OUTPUT_DIR_ABS"/*; do
  [[ -d "$repo_dir" ]] || continue
  if [[ ! -d "$repo_dir/.git" ]]; then
    continue
  fi

  # 1) Secrets (PCRE with grep -P if available)
  if [[ "$MODE" == "secrets" || "$MODE" == "both" ]]; then
    for pat in "${SECRET_PATTERNS[@]}"; do
      if [[ -n "$pat" ]]; then
        name="${pat%%|*}"
        pattern="${pat#*|}"
        if grep -P -RIn --no-heading -e "$pattern" "$repo_dir" >/dev/null 2>&1; then
          grep -RInP --no-heading -H -n -e "$pattern" "$repo_dir" 2>/dev/null | while IFS= read -r line; do
            file=$(echo "$line" | cut -d: -f1)
            line_no=$(echo "$line" | cut -d: -f2)
            value=$(echo "$line" | cut -d: -f3-)
            echo -e "${BLUE}[SECRET]${NC} $name in ${file}:${line_no} -> ${value}"
            TOTAL_SECRETS=$((TOTAL_SECRETS + 1))
          done
        fi
      fi
    done
  fi

  # 2) URLs (serial)
  if [[ "$MODE" == "urls" || "$MODE" == "both" ]]; then
    # Collect URLs from text files (avoid binaries)
    find "$repo_dir" -type f -print0 2>/dev/null | while IFS= read -r -d '' f; do
      mime=$(file -b --mime-type "$f" 2>/dev/null || echo "application/octet-stream")
      if [[ "$mime" != text/* && "$mime" != "message/*" ]]; then
        continue
      fi
      # Extract GitHub URLs from this file
      if grep -P -q "$GH_URL_REGEX" "$f" 2>/dev/null; then
        urls_in_file=$(grep -P -o -h "$GH_URL_REGEX" "$f" 2>/dev/null || true)
        if [[ -n "$urls_in_file" ]]; then
          while IFS= read -r url; do
            if [[ -z "${URL_SEEN:-}" ]]; then
              declare -A URL_SEEN
            fi
            if [[ -z "${URL_SEEN[$url]:-}" ]]; then
              URL_SEEN["$url"]=1
              TOTAL_URLS=$((TOTAL_URLS + 1))
              code=$(curl -sS -I -L -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
              if [[ "$code" =~ ^([23][0-9][0-9]|200)$ ]]; then
                TOTAL_GOOD=$((TOTAL_GOOD + 1))
              else
                TOTAL_BROKEN=$((TOTAL_BROKEN + 1))
                echo -e "${RED}[BROKEN] ${url} (in ${f}) [HTTP ${code}]${NC}"
              fi
            fi
          done <<< "$urls_in_file"
        fi
      fi
    done
  fi
done

echo -e "${BLUE}Scan complete.${NC}"
echo "Summary:"
echo "  Total URLs scanned: ${TOTAL_URLS}"
echo "  Broken URLs: ${TOTAL_BROKEN}"
echo "  Good URLs: ${TOTAL_GOOD}"
echo "  Secrets found: ${TOTAL_SECRETS}"
