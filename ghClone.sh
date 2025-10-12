#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ORG=$1
mkdir -p /tmp/$ORG/
mkdir -p /tmp/$ORG/REPOS

OUTPUT_DIR="/tmp/$ORG/REPOS/"
ROOT_DIR="/tmp/$ORG/"

org() {
echo -e "${BLUE}[-]Cloning Github Repositories [-] :${NC} ${RED}$ORG ${NC}"
ghorg clone $ORG --fetch-all --quiet -p $OUTPUT_DIR -t $GITHUB_TOKEN --color enabled --skip-forks
}

member() {
echo -e "${BLUE}[-]Searching Members [-] :${NC} ${RED}$ORG ${NC}"
bash findEmployees.sh $ORG

while IFS= read -r NAME; do
mkdir -p "$ROOT_DIR/$NAME"
local OUTPUT_DIR="$ROOT_DIR/$NAME/REPOS"
echo -e "${BLUE}[-]Cloning Github Repositories [-]:${NC} ${RED}$NAME ${NC}"
ghorg clone $NAME --clone-type=user --fetch-all --quiet -p $OUTPUT_DIR -t $GITHUB_TOKEN --color enabled --skip-forks
done < $ROOT_DIR/member.usernames
}

org
member
