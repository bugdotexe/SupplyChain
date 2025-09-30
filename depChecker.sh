#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAME=$1
OUTPUT=$2

echo -e "${BLUE}Checking NPM Dependencies $NAME ${NC}"
while IFS= read -r pkg; do
if npm view "$pkg" >/dev/null 2>&1; then
    echo -e "${BLUE}[NPM]${NC} ${BLUE}$pkg${NC} ${BLUE}[AVAILABLE]${NC}"
    echo "${pkg}" | anew $OUT_PUT/npm.potential >/dev/null 2>&1
  fi
done < "$OUT_PUT/npm.deps" | sed 's/[[:space:]]//g' | awk '{print $1}'


echo -e "${BLUE}Checking Python Dependencies $NAME ${NC}"
while IFS= read -r pkg; do
if pip show "$pkg" >/dev/null 2>&1; then
    echo -e "${BLUE}[PIP]${NC} ${BLUE}$pkg${NC} ${BLUE}[AVAILABLE]${NC}"
echo "${pkg}" | anew $OUT_PUT/pip.potential >/dev/null 2>&1
  fi
done < "$OUT_PUT/pip.deps" | sed 's/[[:space:]]//g' | awk '{print $1}'



echo -e "${BLUE}Checking Ruby Gem Dependencies $NAME ${NC}"
while IFS= read -r pkg; do

if gem info "$pkg" >/dev/null 2>&1; then
    echo -e "${BLUE}[GEM]${NC} ${BLUE}$pkg${NC} ${BLUE}[AVAILABLE]${NC}"
   echo "${pkg}" | anew $OUT_PUT/ruby.potential >/dev/null 2>&1
 fi
done < "$OUT_PUT/ruby.deps" | sed 's/[[:space:]]//g' | awk '{print $1}'

echo -e "${BLUE}Scanning Broken GITHUB link $NAME ${NC}"
cat $OUT_PUT/github.account | cut -d "/" -f1,2,3,4 | sort | uniq | xargs -I {} sh scan-broken.sh {} | anew $OUT_PUT/github.potential
#cat $OUT_PUT/github.account | grep -v ajax.googleapis.com\|awscli.amazonaws.com\|docs.aws.amazon.com\|ec2.amazonaws.com\|fonts.googleapis.com\|maps.googleapis.com\|oauth2.googleapis.com\|openidconnect.googleapis.com\|play.googleapis.com\|sns.amazonaws.com\|go-integration-test" | grep "actions-contrib\|googleapis\|amazonaws\|vercel.app\|netlify\|herokuapp\|surge.sh\|now.sh\|plugins.svn.wordpress.org\|npmjs.org\/package"
