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
    jq -r '[(.dependencies // {}), (.devDependencies // {})] | add | keys[]' "$file" | sort | uniq |
    while read -r pkg; do
        if npm view "$pkg" &>/dev/null; then
            continue
        else
            echo -e "\e[32m [+] $pkg does NOT exist on npm\e[0m"
        fi
    done
}


check_pip_reqs() {
    local file="$1"
    grep -oP '^[a-zA-Z0-9_\-]+' "$file" | sort | uniq |
    while read -r pkg; do
        pkg_lc=$(echo "$pkg" | tr '[:upper:]' '[:lower:]')
        if curl -s -f "https://pypi.org/pypi/${pkg_lc}/json" >/dev/null; then
            continue
        else
             echo -e "\e[32m [+] $pkg does NOT exist on PyPI\e[0m"
        fi
    done
}

check_gemfile() {
    local file="$1"
    grep -oP "gem\s+['\"]\K[^'\"]+" "$file" | sort | uniq |
    while read -r pkg; do
        pkg_lc=$(echo "$pkg" | tr '[:upper:]' '[:lower:]')
        if curl -s -f "https://rubygems.org/api/v1/gems/${pkg_lc}.json" >/dev/null; then
            continue
        else
             echo -e "\e[32m [+] $pkg does NOT exist on RubyGem\e[0m"
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
