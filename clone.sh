#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat << 'USAGE'
Usage:
  ./scan_github.sh --org ORG_NAME --output OUTPUT_DIR [--token TOKEN] [--parallel N]
  ./scan_github.sh --user USER_NAME --output OUTPUT_DIR [--token TOKEN] [--parallel N]

Options:
  --org NAME       scan an organization
  --user NAME      scan a user account
  --output PATH    base output directory
  --token TOKEN    GitHub token to access private repos (optional if gh auth is set)
  --parallel N     number of parallel downloads (default 4)
USAGE
  exit 1
}

ORG=""
USER=""
OUTPUT="."
TOKEN="${GITHUB_TOKEN:-}"
PARALLEL=4

# parse long options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)
      ORG="$2"; shift 2 ;;
    --user)
      USER="$2"; shift 2 ;;
    --output)
      OUTPUT="$2"; shift 2 ;;
    --token)
      TOKEN="$2"; shift 2 ;;
    --parallel)
      PARALLEL="$2"; shift 2 ;;
    *)
      echo "Unknown option: $1" >&2
      usage ;;
  esac
done

if { [[ -n "$ORG" && -n "$USER" ]]; } || { [[ -z "$ORG" && -z "$USER" ]]; }; then
  echo "Error: You must provide exactly one of --org or --user." >&2
  usage
fi

NAME=""
TYPE=""

if [[ -n "$ORG" ]]; then
  TYPE="org"
  NAME="$ORG"
elif [[ -n "$USER" ]]; then
  TYPE="user"
  NAME="$USER"
fi

ROOT_DIR="${OUTPUT%/}/.${NAME}"
REPO_ROOT="${ROOT_DIR}/REPO"
LOGS_DIR="${ROOT_DIR}/logs"

# create dirs
mkdir -p "$ROOT_DIR" "$LOGS_DIR" "$REPO_ROOT"

# log setup
LOG_FILE="${LOGS_DIR}/scanner.log"
exec 3>&1 4>&2
exec >>"$LOG_FILE" 2>&1

echo "[$(date)] Starting scan: type=$TYPE, name=$NAME, root=$ROOT_DIR" || true

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI is not installed." >&2
  exit 1
fi

# token fallback: if not provided, rely on gh auth
if [[ -z "$TOKEN" ]]; then
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    TOKEN="$GITHUB_TOKEN"
  fi
fi

# Prepare clone lists
clone_org_list="${ROOT_DIR}/clone_org_repos.txt"
clone_member_list="${ROOT_DIR}/clone_member_repos.txt"
clone_user_list="${ROOT_DIR}/clone_user_repos.txt"

ORG_REPOS_DIR="${ROOT_DIR}/REPO/ORG_REPOS"
MEMBER_ROOT="${ROOT_DIR}/MEMBER"

mkdir -p "$ORG_REPOS_DIR" "$MEMBER_ROOT"

if [[ "$TYPE" == "org" ]]; then
  echo "Listing org repos for $NAME"
  mapfile -t ORG_REPOS < <(gh repo list "$NAME" --limit 4000 --json name --jq '.[].name' 2>/dev/null || true)

  : > "$clone_org_list"

  for REPO in "${ORG_REPOS[@]}"; do
    DEST="${ORG_REPOS_DIR}/${REPO}"
    mkdir -p "$ORG_REPOS_DIR"  # ensure parent
    if [[ -d "$DEST/.git" ]]; then
      echo "exists: $DEST" >> "$LOG_FILE"
      continue
    fi
    if [[ -n "$TOKEN" ]]; then
      URL="https://${TOKEN}@github.com/${NAME}/${REPO}.git"
    else
      URL="https://github.com/${NAME}/${REPO}.git"
    fi
    printf "git clone %s '%s'\n" "$URL" "$DEST" >> "$clone_org_list"
  done

  if [[ -s "$clone_org_list" ]]; then
    echo "Starting parallel clone of org repos (par=$PARALLEL)"
    cat "$clone_org_list" | xargs -I CMD -P "$PARALLEL" bash -lc 'CMD' 2>&1 | tee -a "$LOG_FILE"
  else
    echo "No org repos found or nothing to clone."
  fi

  # fetch org members
  MEMBERS_FILE="${ROOT_DIR}/MEMBERS.txt"
  echo "Fetching members of org: $NAME"
  if gh api "orgs/$NAME/members" --paginate --jq '.[].login' 2>/dev/null > "$MEMBERS_FILE"; then
    :
  else
    echo "Failed to fetch members."
    MEMBERS_FILE=""
  fi

  if [[ -z "$MEMBERS_FILE" || ! -s "$MEMBERS_FILE" ]]; then
    echo "No members found; skipping member repos."
  else
    : > "$clone_member_list"
    while IFS= read -r MEMBER; do
      if [[ -z "$MEMBER" ]]; then continue; fi
      MEMBER_REPO_DEST="${MEMBER_ROOT}/${MEMBER}/REPOS"
      mkdir -p "$MEMBER_REPO_DEST"
      MEM_REPOS_JSON=$(gh repo list "$MEMBER" --limit 2000 --json name --jq '.[].name' 2>/dev/null || echo "")
      if [[ -z "$MEM_REPOS_JSON" ]]; then
        echo "No repos for member: $MEMBER" >> "$LOG_FILE"
        continue
      fi
      mapfile -t MEM_REPOS < <(echo "$MEM_REPOS_JSON" | tr ' ' '\n')
      for MR in "${MEM_REPOS[@]}"; do
        DEST="${MEMBER_REPO_DEST}/${MR}"
        if [[ -d "$DEST/.git" ]]; then
          echo "exists: $DEST" >> "$LOG_FILE"
          continue
        fi
        if [[ -n "$TOKEN" ]]; then
          URL="https://${TOKEN}@github.com/${MEMBER}/${MR}.git"
        else
          URL="https://github.com/${MEMBER}/${MR}.git"
        fi
        printf "git clone %s '%s'\n" "$URL" "$DEST" >> "$clone_member_list"
      done
    done < "$MEMBERS_FILE"

    if [[ -s "$clone_member_list" ]]; then
      echo "Starting parallel clone of member repos (par=$PARALLEL)"
      cat "$clone_member_list" | xargs -I CMD -P "$PARALLEL" bash -lc 'CMD' 2>&1 | tee -a "$LOG_FILE"
    else
      echo "No member repos to clone."
    fi
  fi

else
  # USER mode
  USER_REPOS_DIR="${ROOT_DIR}/REPO/USER_REPOS"
  mkdir -p "$USER_REPOS_DIR"
  echo "Fetching repos for user: $NAME"
  mapfile -t USER_REPOS < <(gh repo list "$NAME" --limit 4000 --json name --jq '.[].name' 2>/dev/null || true)
  : > "$clone_user_list"

  for REPO in "${USER_REPOS[@]}"; do
    DEST="${USER_REPOS_DIR}/${REPO}"
    mkdir -p "$USER_REPOS_DIR"
    if [[ -d "$DEST/.git" ]]; then
      echo "exists: $DEST" >> "$LOG_FILE"
      continue
    fi
    if [[ -n "$TOKEN" ]]; then
      URL="https://${TOKEN}@github.com/${NAME}/${REPO}.git"
    else
      URL="https://github.com/${NAME}/${REPO}.git"
    fi
    printf "git clone %s '%s'\n" "$URL" "$DEST" >> "$clone_user_list"
  done

  if [[ -s "$clone_user_list" ]]; then
    echo "Starting parallel clone of user repos (par=$PARALLEL)"
    cat "$clone_user_list" | xargs -I CMD -P "$PARALLEL" bash -lc 'CMD' 2>&1 | tee -a "$LOG_FILE"
  else
    echo "No repos found for user or nothing to clone."
  fi
fi

echo "Done."
exit 0
