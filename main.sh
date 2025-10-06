#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAME=$1
REPOS=$2

echo -e "${BLUE}Fetching docker images from $NAME ${NC}"
grep -roh -E "docker (pull|run|push) [-a-zA-Z0-9_]+/[-a-zA-Z0-9_]+" $REPOS | awk -F " " '{print $3}' | awk -F "/" '{print $1}' | sort | uniq | anew $REPOS/../image.docker
find $REPOS -name docker-compose.yml | xargs -I {} awk '{print}' {} | grep "image:" \
  | grep -v "^\s*#" \
  | sed -E 's/^[[:space:]]*image:[[:space:]]*"?([^" ]+)"?/\1/' \
  | grep -v '^$' \
  | sort -u | anew $REPOS/../image.docker


echo -e "${BLUE}Fetching NPM dependencies from $NAME ${NC}"
find $REPOS -name package.json | xargs -I {} get-dependencies {} | sort | uniq | anew $REPOS/../npm.deps
find $REPOS -name "*.js" | xargs -I {} bash JsScan.sh {} | anew $REPOS/../npm.deps

echo -e "${BLUE}Fetching PyPi dependencies from $NAME ${NC}"
find $REPOS -name requirements.txt | xargs -I {} awk '{print}' {} | grep -v "git:\|https\:\|http\:\|\#\|\""  | awk -F '=' '{print $1}' | awk -F ';' '{print $1}' | awk -F '(' '{print $1}' | awk -F '<' '{print $1}' | awk -F '>' '{print $1}' | awk -F '~' '{print $1}' | awk -F '[' '{print $1}' | awk NF | sed 's/ //g' | grep -v "^-" | sort | uniq | anew $REPOS/../pip.deps

find $REPOS -name requirements-dev.txt | xargs -I {} awk '{print}' {} | grep -v "git:\|https\:\|http\:\|\#\|\""  | awk -F '=' '{print $1}' | awk -F ';' '{print $1}' | awk -F '(' '{print $1}' | awk -F '<' '{print $1}' | awk -F '>' '{print $1}' | awk -F '~' '{print $1}' | awk -F '[' '{print $1}' | awk NF | sed 's/ //g' | grep -v "^-" | sort | uniq | anew $REPOS/../pip.deps


echo -e "${BLUE}Fetching Ruby dependencies from $NAME ${NC}"
find $REPOS -name Gemfile | xargs -I {} awk '{print}' {} | grep "^gem" | grep -v gemspec | sed "s/\"/\'/g" | awk -F "\'" '{print $2}' | awk NF | sort | uniq | anew $REPOS/../ruby.deps


echo -e "${BLUE}Fetching Bucket names from $NAME ${NC}"
grep -ro -E "(s3|gs)://[-a-zA-Z0-9_\.]+" $REPOS | grep -vi "example\|bucketname$\|bucket-name$\|BUCKET_NAME$\|mybucket$\|my_bucket$" | sort | uniq | anew $REPOS/../bucket.names

echo -e "${BLUE}Fetching urls from $NAME ${NC}"
grep -roh '(http.)?://(cdn.jsdelivr.net)\b([-a-zA-Z0-9@:%_\+.~#?&\/=]*)' $REPOS | sort | uniq | anew $REPOS/../github.urls

grep -roh '(http.)?://(raw.githubusercontent.com)\b([-a-zA-Z0-9@:%_\+.~#?&\/=]*)' $REPOS | sort | uniq | anew $REPOS/../github.urls

grep -roh '(http.)?://(raw.github.com)\b([-a-zA-Z0-9@:%_\+.~#?&\/=]*)' $REPOS | sort | uniq | anew $REPOS/../github.urls

grep -roh '(http.)?://(codecov.io)\b([-a-zA-Z0-9@:%_\+.~#?&\/=]*)' $REPOS | sort | uniq | anew $REPOS/../github.urls

grep -roh '(http.)?://(media.githubusercontent.com)\b([-a-zA-Z0-9@:%_\+.~#?&\/=]*)' $REPOS | sort | uniq | anew $REPOS/../github.urls

GH_URL_REGEX='https?://github\.com/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?'
grep -rhoE "$GH_URL_REGEX" "$REPOS" 2>/dev/null | sort -u | anew "$REPOS/../github.account"

echo -e "${BLUE}Fetching github registry from $NAME ${NC}"
grep -roP "(ghcr.io)/[-a-zA-Z0-9_\.\/]+" $REPOS  | anew $REPOS/../github.reg
grep -roP "(docker.pkg.github.com)/[-a-zA-Z0-9_\.\/]+" $REPOS | anew $REPOS/../github.reg
grep -roP "(rubygems.pkg.github.com)/[-a-zA-Z0-9_\.\/]+" $REPOS | anew $REPOS/../github.reg
grep -roP "(npm.pkg.github.com)/[-a-zA-Z0-9_\.\/]+" $REPOS | anew $REPOS/../github.reg
grep -roP "(maven.pkg.github.com)/[-a-zA-Z0-9_\.\/]+" $REPOS | anew $REPOS/../github.reg
grep -roP "(nuget.pkg.github.com)/[-a-zA-Z0-9_\.\/]+" $REPOS | anew $REPOS/../github.reg

echo -e "${BLUE}Fetching github action from $NAME ${NC}"
grep -roh -E "uses: [-a-zA-Z0-9\.]+/[-a-zA-Z0-9.]+\@[-a-zA-Z0-9\.]+" $REPOS | awk -F ": " '{print $2}' | awk -F "/" '{print "https://github.com/"$1}' | sort | uniq | grep -v "github.com/actions$" | anew $REPOS/../github.action
