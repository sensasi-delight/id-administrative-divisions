#!/bin/bash

# ----------------------------------------------------------------------
# Synchronization Script for Open Data (Shell Script Version)
# Detects which file (CSV or JSON) was modified most recently
# and updates the older one automatically.
#
# Dependencies: jq, csvkit
# ----------------------------------------------------------------------

# Function to check for required commands
check_deps() {
    if ! command -v jq &> /dev/null || ! command -v csvjson &> /dev/null; then
        echo "Error: 'jq' and 'csvkit' (for csvjson) are required." >&2
        echo "Please install them to continue." >&2
        echo "Example:" >&2
        echo "  - Ubuntu/Debian: sudo apt-get install jq csvkit" >&2
        echo "  - macOS (Homebrew): brew install jq csvkit" >&2
        echo "  - Python: pip install csvkit" >&2
        exit 1
    fi
}

# Function to get file modification time (cross-platform)
get_mtime() {
    if [[ -f "$1" ]]; then
        # Check for GNU stat (Linux) vs BSD stat (macOS)
        if stat -c %Y "$1" 2>/dev/null; then
            stat -c %Y "$1"
        else
            stat -f %m "$1"
        fi
    else
        echo 0
    fi
}

main() {
    # First, check dependencies
    check_deps

    local datasets=("provinces" "regencies" "districts" "villages")
    
    # Ensure directories exist
    mkdir -p csv json

    for dataset in "${datasets[@]}"; do
        local csv_file="csv/${dataset}.csv"
        local json_file="json/${dataset}.json"

        if [[ ! -f "$csv_file" && ! -f "$json_file" ]]; then
            echo "⚠️ Skipping $dataset (no data files found)"
            continue
        fi

        local csv_time=$(get_mtime "$csv_file")
        local json_time=$(get_mtime "$json_file")

        if (( csv_time > json_time )); then
            echo "↻ Converting CSV → JSON for $dataset"
            # csvjson automatically infers data types (numbers won't be quoted)
            # -i 4 adds indentation for readability
            csvjson -i 4 "$csv_file" > "$json_file"
        
        elif (( json_time > csv_time )); then
            echo "↻ Converting JSON → CSV for $dataset"
            # Use jq with @csv filter for minimal quoting
            # 1. Get headers from the first object's keys.
            # 2. Get all values from each object.
            # 3. Pipe both to the file.
            { 
                jq -r '.[0] | keys_unsorted | @csv' "$json_file"; 
                jq -r '.[] | @csv' "$json_file"; 
            } > "$csv_file"
        
        else
            echo "✅ $dataset already synchronized"
        fi
    done
}

# Run the main function
main
