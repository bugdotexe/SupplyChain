#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAME=$1
OUT_PUT=$2

echo -e "${BLUE}Checking NPM Dependencies $NAME ${NC}" | notify
cat "$OUT_PUT/npm.deps" | sed 's/[[:space:]]//g' | awk '{print $1}' | xargs -I {} npm-name {} | anew $OUT_PUT/npm.checked
cat $OUT_PUT/npm.checked | grep "is available" | anew $OUT_PUT/npm.potential | notify

echo -e "${BLUE}Checking Python Dependencies $NAME ${NC}" | notify
cat "$OUT_PUT/pip.deps" | sed 's/[[:space:]]//g' | awk '{print $1}' | xargs -I {} pip-name {} | anew $OUT_PUT/pip.checked
cat $OUT_PUT/pip.checked | grep "is available" | anew $OUT_PUT/pip.potential | notify

echo -e "${BLUE}Checking Ruby Gem Dependencies $NAME ${NC}" | notify
cat "$OUT_PUT/ruby.deps" | xargs -I {} sh ruby-name.sh {} | anew $OUT_PUT/gem.checked
cat $OUT_PUT/gem.checked | grep "is available" | anew $OUT_PUT/gem.potential | notify

broken_github() {
echo -e "${BLUE}Scanning Broken GITHUB link $NAME ${NC}"
cat $OUT_PUT/github.account | cut -d "/" -f1,2,3,4 | sort | uniq | xargs -I {} sh scan-broken.sh {} | anew $OUT_PUT/github.potential

echo -e "${BLUE}Scanning Broken GITHUB Action $NAME ${NC}"
cat $OUT_PUT/github.action | cut -d "/" -f1,2,3,4 | sort | uniq | xargs -I {} sh scan-broken.sh {} | anew $OUT_PUT/github.potential
}
broken_github

echo -e "${BLUE}Scanning Broken docker name $NAME ${NC}"
cat $OUT_PUT/image.docker | cut -d "/" -f1 |cut -d ":" -f1 | sort -u | xargs -I {} sh docker-name.sh {} | anew $OUT_PUT/docker.potential
echo -e "${BLUE}Scanning Broken docker name : GHCR : $NAME ${NC}" | notify
cat $OUT_PUT | cut -d ":" -f2 | cut -d "/" -f2 | sort -u | xargs -I {} sh docker-name.sh {} | anew $OUT_PUT/docker.potential | notify
