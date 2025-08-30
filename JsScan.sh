#!/bin/bash

if [ $# -eq 0 ]; then
    echo "Usage: $0 <javascript-file>"
    exit 1
fi

FILE="$1"
if [ ! -f "$FILE" ]; then
    echo "Error: File '$FILE' not found"
    exit 1
fi
BUILTINS=$(node -e '                              const { builtinModules } = require("node:module");                                              console.log(builtinModules.join("|"));
')                                              
BUILTIN_REGEX="^($(echo "$BUILTINS" | sed "s/|/\\|/g"))$"
grep -Eo "require\(['\"][^'/\"]+['\"]\)|from\s+['\"][^'/\"]+['\"]" "$FILE" | \
sed -E "s/.*require\(['\"]([^'/\"]+)['\"]\).*/\1/" | \
sed -E "s/.*from\s+['\"]([^'/\"]+)['\"].*/\1/" | grep -vE "$BUILTIN_REGEX" | \
sort -u
