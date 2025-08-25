#!/usr/bin/env bash
set -euo pipefail

BUILTINS=$(node -e '
  const { builtinModules } = require("node:module");
  console.log(builtinModules.join("|"));
')

BUILTIN_REGEX="^($(echo "$BUILTINS" | sed "s/|/\\|/g"))$"

if [ $# -eq 0 ]; then
  INPUT="/dev/stdin"
  GREP_TARGET="-"
else
  INPUT="$*"
  GREP_TARGET="--include=*.js"
fi

grep -rIhoP \
    'import\s+(?:[\w\{\},\s*]+\s+from\s+)?["'\'']([^"'\'']+)["'\'']|require\(\s*["'\'']([^"'\'']+)["'\'']\s*\)|import\(\s*["'\'']([^"'\'']+)["'\'']\s*\)' \
    . $GREP_TARGET $INPUT 2>/dev/null \
| sed -E 's/.*["'\'']([^"'\'']+)["'\''].*/\1/' \
| grep -vE '^(\.|\/)' \
| grep -vE "$BUILTIN_REGEX" \
| sort -u
