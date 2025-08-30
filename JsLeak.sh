#!/bin/bash

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Install jq first."
    exit 1
fi

SECRETS_FILE="regex.json"
TARGET_FILE="$1"   

if [ ! -f "$SECRETS_FILE" ]; then
    echo "Error: $SECRETS_FILE not found."
    exit 1
fi

if [ ! -f "$TARGET_FILE" ]; then
    echo "Error: Target file $TARGET_FILE not found."
    exit 1
fi

jq -r 'to_entries[] | "\(.key)|\(.value)"' "$SECRETS_FILE" | while IFS='|' read -r key pattern; do
    grep -H -n --color=always -E "$pattern" "$TARGET_FILE" 2>/dev/null | while read -r line; do
        echo "[$key] Found in $line"
    done
done
