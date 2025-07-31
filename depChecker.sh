#!/bin/bash

set -e

show_help() {
    echo "Usage: $0 [--npm <package.json>] [--pip <requirements.txt>] [--gem <Gemfile>] [--all]"
    echo ""
    echo "Options:"
    echo "  --npm <file>         Check dependencies in npm package.json"
    echo "  --pip <file>         Check dependencies in pip requirements.txt"
    echo "  --gem <file>         Check dependencies in Ruby Gemfile"
    echo "  -h, --help           Show this help message"
    exit 1
}

command -v jq >/dev/null || { echo "jq required, please install it."; exit 1; }

check_npm_deps() {
    local file="$1"
    jq -r '
        def extract_deps:
            [.dependencies? // {}, .devDependencies? // {}, .peerDependencies? // {}]
            | add // {}
            | keys[];

        if has("lockfileVersion") then
            if .lockfileVersion >= 3 then
                # For lockfileVersion 3: extract from all packages
                .packages | to_entries[] | .value | extract_deps
            else
                # For older lockfile versions: extract from dependencies
                .dependencies | keys[]
            end
        else
            # For package.json
            extract_deps
        end
    ' "$file" | sort -u |
    while read -r pkg; do
        if npm view "$pkg" &>/dev/null; then
            continue
        else
            echo -e "\e[32m [+]\e[0m \e[31m$pkg\e[0m does NOT exist on NPM\e[0m"
        fi
    done
}

extract_deps() {
  awk '
    BEGIN {
      in_deps = 0
      in_build = 0
      in_project = 0
    }

    # Section headers
    /\[.*\.dependencies\]/ || /\[dependencies\]/ {
      in_deps = 1; in_build = 0; in_project = 0; next
    }
    /\[build-system\]/ {
      in_build = 1; in_deps = 0; in_project = 0; next
    }
    /\[project\]/ {
      in_project = 1; in_deps = 0; in_build = 0; next
    }
    /^\[/ {
      in_deps = 0; in_build = 0; in_project = 0
    }

    # Dependency sections
    in_deps && /^[^#=]+[ \t]*=/ {
      pkg = $0
      sub(/[ \t]*=.*/, "", pkg)
      gsub(/^[ \t"'\'']+|[ \t"'\'']+$/, "", pkg)
      if (pkg != "python") print pkg
    }

    # Build-system requires
    in_build && /requires[ \t]*=[ \t]*\[/ {
      gsub(/^[^\[]+\[|\].*/, "", $0)
      split($0, deps, ",")
      for (i in deps) {
        gsub(/[ \t"'\''<>=\\!~]/, "", deps[i])
        if (deps[i] != "") print deps[i]
      }
    }

    # Project dependencies
    in_project && /dependencies[ \t]*=[ \t]*\[/ {
      gsub(/^[^\[]+\[|\].*/, "", $0)
      split($0, deps, ",")
      for (i in deps) {
        gsub(/^[ \t"'\'']+|[ \t"'\'']$/, "", deps[i])
        sub(/[<>=!~].*/, "", deps[i])
        if (deps[i] != "") print deps[i]
      }
    }

    # Project optional dependencies
    in_project && /^[a-zA-Z0-9_-]+[ \t]*=[ \t]*\[/ {
      gsub(/^[^[]+\[|\].*/, "", $0)
      split($0, deps, ",")
      for (i in deps) {
        gsub(/^[ \t"'\'']+|[ \t"'\'']$/, "", deps[i])
        sub(/[<>=!~].*/, "", deps[i])
        if (deps[i] != "") print deps[i]
      }
    }
  ' "$1"
}

check_pip_reqs() {
    local file="$1"

    if [[ $(cat $file | grep ".dependencies") ]];then
       extract_deps $file | sort | uniq |
    while read -r pkg; do
        pkg_lc=$(echo "$pkg" | tr '[:upper:]' '[:lower:]')
        if curl -s -f "https://pypi.org/pypi/${pkg_lc}/json" >/dev/null; then
            continue
        else
             echo -e "\e[32m [+]\e[0m \e[31m$pkg\e[0m does NOT exist on PyPI\e[0m"
        fi
    done

   else
    grep -oP '^[a-zA-Z0-9_\-]+' "$file" | sort | uniq |
    while read -r pkg; do
        pkg_lc=$(echo "$pkg" | tr '[:upper:]' '[:lower:]')
        if curl -s -f "https://pypi.org/pypi/${pkg_lc}/json" >/dev/null; then
            continue
        else
             echo -e "\e[32m [+]\e[0m \e[31m$pkg\e[0m does NOT exist on PyPI\e[0m"
        fi
    done
    fi
}

check_gemfile() {
    local file="$1"
    grep -oP "gem\s+['\"]\K[^'\"]+" "$file" | sort | uniq |
    while read -r pkg; do
        pkg_lc=$(echo "$pkg" | tr '[:upper:]' '[:lower:]')
        if curl -s -f "https://rubygems.org/api/v1/gems/${pkg_lc}.json" >/dev/null; then
            continue
        else
             echo -e "\e[32m [+]\e[0m \e[31m$pkg\e[0m does NOT exist on RubyGem\e[0m"
        fi
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --npm)
            npm_file="$2"
            shift 2
            ;;
        --pip)
            pip_file="$2"
            shift 2
            ;;
        --gem)
            gem_file="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

[ -n "$npm_file" ] && check_npm_deps "$npm_file"
[ -n "$pip_file" ] && check_pip_reqs "$pip_file"
[ -n "$gem_file" ] && check_gemfile "$gem_file"
