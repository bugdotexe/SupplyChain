#!/usr/bin/env bash

YELLOW="\033[93m"
RESET="\033[0m"

NAME="$1"
PAGE=1

while true; do
  RESPONSE=$(curl -s "https://hub.docker.com/v2/repositories/${NAME}/tags?page_size=100&page=${PAGE}")

  TAGS=$(echo "$RESPONSE" | jq -c '.results[]?')
  NEXT=$(echo "$RESPONSE" | jq -r '.next')

  if [ -z "$TAGS" ]; then
    break
  fi

  echo "$TAGS" | while read -r TAG; do
    TAG_NAME=$(echo "$TAG" | jq -r '.name')

    if [[ "$TAG_NAME" == *.sig || "$TAG_NAME" == *.enc ]]; then
      continue
    fi

    echo "$TAG" | jq -c '.images[]?' | while read -r IMG; do
      ARCH=$(echo "$IMG" | jq -r '.architecture')
      DIGEST=$(echo "$IMG" | jq -r '.digest')

      echo "--------------------------------------------------"
      echo -e "Scanning tag ${YELLOW}${TAG_NAME}${RESET} with architecture ${YELLOW}${ARCH}${RESET} for secrets...\n"
      
      trufflehog docker --image "${NAME}@${DIGEST}" --only-verified --no-update
    done
  done

  if [ "$NEXT" == "null" ]; then
    break
  fi

  PAGE=$((PAGE+1))
done
