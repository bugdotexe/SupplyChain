#!/bin/bash

# Enhanced NPM Scanner with Full File Analysis
# Supports both organizations and users with proper URL handling

set -euo pipefail

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required but not installed."; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "Error: npm is required but not installed."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Error: curl is required but not installed."; exit 1; }

if [ $# -lt 2 ]; then
    echo "Usage: $0 [--org|--user] [name] [output_dir]"
    echo "Example: $0 --org replit ./scan_results"
    echo "Example: $0 --user replit ./scan_results"
    exit 1
fi

# Parse arguments
TYPE=$1
NAME=$2
OUTPUT_DIR=${3:-./scan_results}
SCAN_DIR="$NAME"
REGEX_FILE="./regex.json"  # Update path if needed

# Create directories
mkdir -p "$SCAN_DIR"
mkdir -p "$SCAN_DIR/packages"
mkdir -p "$SCAN_DIR/results"
mkdir -p "$SCAN_DIR/logs"

# Logging functions
log() {
    echo "[*] $1" | tee -a "$SCAN_DIR/logs/scan.log"
}

error() {
    echo "[!] $1" | tee -a "$SCAN_DIR/logs/errors.log"
}

# Function to fetch organization packages
fetch_org_packages() {
    local org_name=$1
    log "Fetching organization packages for @$org_name"

    # Safely extract package names; only output if items is an array
    curl -s "https://registry.npmjs.org/-/org/$org_name/packages" \
    | jq -r 'if (.items | type == "array") then .items[].name else empty end' \
    > "$SCAN_DIR/package_list.txt"

    # If still empty, try alternative scraping method
    if [ ! -s "$SCAN_DIR/package_list.txt" ]; then
        log "Trying alternative approach to fetch organization packages"
        curl -s "https://www.npmjs.com/org/$org_name" \
        | grep -oP '"name":"@'"$org_name"'/[^"]+"' \
        | cut -d'"' -f4 | sort -u \
        > "$SCAN_DIR/package_list.txt" || true
    fi
}

# Function to fetch user packages
fetch_user_packages() {
    local user_name=$1
    log "Fetching user packages for ~$user_name"
    
    # Try multiple approaches to get user packages
    curl -s "https://registry.npmjs.org/-/v1/search?text=maintainer:$user_name&size=250" | \
    jq -r '.objects[].package.name' > "$SCAN_DIR/package_list.txt"
    
    # If empty, try alternative approach
    if [ ! -s "$SCAN_DIR/package_list.txt" ]; then
        log "Trying alternative approach to fetch user packages"
        # This approach might not work as well, but we try
        curl -s "https://www.npmjs.com/~$user_name" | grep -oP 'package":"[^"]+"' | \
        cut -d'"' -f3 | sort -u > "$SCAN_DIR/package_list.txt" || true
    fi
}

# Function to scan all files in a package
scan_all_files() {
    local pkg=$1
    local pkg_dir=$2
    
    log "Scanning all files in $pkg"
    
    # Find all files in the package
    find "$pkg_dir" -type f > "$SCAN_DIR/results/${pkg//\//_}_all_files.txt"
    
    # Check each file for sensitive information
    while IFS= read -r file; do
        # Skip binary files
        if file "$file" | grep -q "text"; then
            # Check for secrets using regex patterns
            if [ -f "$REGEX_FILE" ]; then
                jq -r '.[]' "$REGEX_FILE" | while read -r pattern; do
                    if [ -n "$pattern" ]; then
                        grep -n -H -e "$pattern" "$file" >> "$SCAN_DIR/results/${pkg//\//_}_secrets.txt" 2>/dev/null || true
                    fi
                done
            else
                # Fallback to common patterns
                grep -n -H -i -E "api[_-]?key|secret[_-]?key|password|token|auth|credential|access[_-]?key|private[_-]?key" \
                "$file" >> "$SCAN_DIR/results/${pkg//\//_}_secrets.txt" 2>/dev/null || true
            fi
            
            # Check for hardcoded URLs and IPs
            grep -n -H -E "(https?://|ftp://)|([0-9]{1,3}\.){3}[0-9]{1,3}" "$file" \
            >> "$SCAN_DIR/results/${pkg//\//_}_urls_ips.txt" 2>/dev/null || true
        fi
    done < "$SCAN_DIR/results/${pkg//\//_}_all_files.txt"
}

# Function to scan a package
scan_package() {
    local pkg=$1
    log "Scanning package: $pkg"
    
    # Create package directory
    local pkg_dir="$SCAN_DIR/packages/${pkg//\//_}"
    mkdir -p "$pkg_dir"
    
    # Download package
    log "Downloading $pkg"
    if npm pack "$pkg" --pack-destination "$pkg_dir" 2>> "$SCAN_DIR/logs/errors.log"; then
        # Get the tarball name
        local tarball=$(ls "$pkg_dir"/*.tgz 2>/dev/null | head -n 1)
        if [ -z "$tarball" ]; then
            error "No tarball found for $pkg"
            return 1
        fi
        
        # Extract package
        log "Extracting $pkg"
        if tar -xzf "$tarball" -C "$pkg_dir" --strip-components=1 2>> "$SCAN_DIR/logs/errors.log"; then
            # Remove tarball
            rm "$tarball"
            
            # Perform security checks on ALL files
            scan_all_files "$pkg" "$pkg_dir"
            check_sensitive_files "$pkg" "$pkg_dir"
            check_source_maps "$pkg" "$pkg_dir"
            check_package_json "$pkg" "$pkg_dir"
            
            log "Completed scanning $pkg"
        else
            error "Failed to extract $pkg"
            return 1
        fi
    else
        error "Failed to download $pkg"
        return 1
    fi
}

# Function to check for sensitive files
check_sensitive_files() {
    local pkg=$1
    local pkg_dir=$2
    
    log "Checking for sensitive files in $pkg"
    local sensitive_files=(
        ".env" ".npmrc" ".gitignore" ".DS_Store" "*.key" "*.pem" "*.crt" "id_rsa" "id_dsa"
        "*.log" "npm-debug.log" "yarn-error.log" "package-lock.json" "yarn.lock"
        "webpack.config.js" "tsconfig.json" "jsconfig.json" ".eslintrc" ".babelrc" "setting.js" "app.js" "debug.log" "config.js"
        "credentials.json" "firebase.json" "config.json" "settings.json"
        "*.sql" "*.db" "*.sqlite" "*.sqlite3" "*.dump"
    )
    
    for pattern in "${sensitive_files[@]}"; do
        find "$pkg_dir" -name "$pattern" -type f >> "$SCAN_DIR/results/${pkg//\//_}_sensitive_files.txt"
    done
}

# Function to check for source maps
check_source_maps() {
    local pkg=$1
    local pkg_dir=$2
    
    log "Checking for source maps in $pkg"
    find "$pkg_dir" -name "*.map" -type f > "$SCAN_DIR/results/${pkg//\//_}_source_maps.txt"
}

# Function to check package.json for sensitive info
check_package_json() {
    local pkg=$1
    local pkg_dir=$2
    
    log "Checking package.json for sensitive info in $pkg"
    if [ -f "$pkg_dir/package.json" ]; then
        # Check for sensitive fields
        jq '.' "$pkg_dir/package.json" | grep -i -E "password|secret|key|token|auth|credential" \
        > "$SCAN_DIR/results/${pkg//\//_}_package_json_issues.txt" || true
        
        # Check for scripts that might be dangerous
        jq '.scripts' "$pkg_dir/package.json" | grep -i -E "preinstall|postinstall|prepublish" \
        > "$SCAN_DIR/results/${pkg//\//_}_package_scripts.txt" || true
    fi
}

# Function to generate summary report
generate_summary() {
    log "Generating summary report"
    local summary_file="$SCAN_DIR/summary_report.txt"
    
    echo "NPM Scan Summary Report" > "$summary_file"
    echo "======================" >> "$summary_file"
    echo "Scan Date: $(date)" >> "$summary_file"
    echo "Target: $TYPE $NAME" >> "$summary_file"
    echo "Total Packages: $(wc -l < "$SCAN_DIR/package_list.txt")" >> "$summary_file"
    echo "" >> "$summary_file"
    
    echo "Findings Summary:" >> "$summary_file"
    echo "----------------" >> "$summary_file"
    
    # Count findings
    local secret_count=$(find "$SCAN_DIR/results" -name "*_secrets.txt" -exec wc -l {} \; | awk '{total += $1} END {print total}')
    local sensitive_files_count=$(find "$SCAN_DIR/results" -name "*_sensitive_files.txt" -exec wc -l {} \; | awk '{total += $1} END {print total}')
    local source_maps_count=$(find "$SCAN_DIR/results" -name "*_source_maps.txt" -exec wc -l {} \; | awk '{total += $1} END {print total}')
    local package_issues_count=$(find "$SCAN_DIR/results" -name "*_package_json_issues.txt" -exec wc -l {} \; | awk '{total += $1} END {print total}')
    local urls_ips_count=$(find "$SCAN_DIR/results" -name "*_urls_ips.txt" -exec wc -l {} \; | awk '{total += $1} END {print total}')
    
    echo "Potential secrets found: $secret_count" >> "$summary_file"
    echo "Sensitive files found: $sensitive_files_count" >> "$summary_file"
    echo "Source maps found: $source_maps_count" >> "$summary_file"
    echo "Package.json issues found: $package_issues_count" >> "$summary_file"
    echo "URLs and IPs found: $urls_ips_count" >> "$summary_file"
    echo "" >> "$summary_file"
    
    echo "Detailed findings are available in the results directory." >> "$summary_file"
    
    cat "$summary_file"
}

# Main execution
case $TYPE in
    --org)
        fetch_org_packages "$NAME"
        ;;
    --user)
        fetch_user_packages "$NAME"
        ;;
    *)
        error "First argument must be --org or --user"
        exit 1
        ;;
esac

# Check if we found any packages
if [ ! -s "$SCAN_DIR/package_list.txt" ]; then
    error "No packages found for $TYPE $NAME"
    exit 1
fi

# Count packages
PKG_COUNT=$(wc -l < "$SCAN_DIR/package_list.txt")
log "Found $PKG_COUNT packages to scan"

# Scan each package sequentially to avoid issues
while IFS= read -r pkg; do
    if [ -n "$pkg" ]; then
        scan_package "$pkg"
    fi
done < "$SCAN_DIR/package_list.txt"

# Generate summary report
generate_summary

log "Scan completed. Results saved to $SCAN_DIR/"
