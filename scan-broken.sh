#!/bin/bash

GREEN='\033[1;32m'
RED='\033[1;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'
HTTP_CODE=404

response_code=$(curl -Ls -o /dev/null -w "%{http_code}" $1)

if [ $response_code -eq $HTTP_CODE ]; then
    echo "${RED}|-BROKEN-|${BLUE}" $1 "${NC} => ${YELLOW}" $response_code "${NC}"
else
    echo "${GREEN}|---OK---|${BLUE}" $1 "${NC} => ${BLUE}" $response_code "${NC}"
fi
