#!/bin/bash

# Main linting script with an auto-fix option for indentation.
#
# Usage:
#   ./scripts/lint.sh       (Run checks only)
#   ./scripts/lint.sh --fix (Run checks and fix indentation issues)

set -e
set -o pipefail

# --- Constants & Global Variables ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_NC='\033[0m' # No Color

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT="$SCRIPT_DIR/.."
CSV_DIR="$PROJECT_ROOT/csv"

FIX_MODE=0
if [ "$1" == "--fix" ]; then
    FIX_MODE=1
fi

# --- Functions ---

run_indent_check() {
    echo -e "${C_BLUE}INFO: Starting self-contained indentation check...${C_NC}"
    local total_errors=0
    local files_fixed=0
    local editorconfig_file="$PROJECT_ROOT/.editorconfig"

    if [ ! -f "$editorconfig_file" ]; then
        echo -e "${C_RED}ERROR: .editorconfig file not found!${C_NC}"
        return 1
    fi

    local indent_style=$(grep 'indent_style' "$editorconfig_file" | cut -d '=' -f 2 | tr -d '[:space:]')
    local indent_size=$(grep 'indent_size' "$editorconfig_file" | cut -d '=' -f 2 | tr -d '[:space:]')

    echo -e "${C_BLUE}INFO: Applying rule: indent_style = $indent_style, indent_size = $indent_size${C_NC}"

    local file_list_tmp=$(mktemp)
    find "$PROJECT_ROOT" -type f -not -path "*/.git/*" -not -name "*.png" -not -name "*.jpg" > "$file_list_tmp"

    while read -r file; do
        local file_errors=0
        local file_modified=0
        local tmp_file=$(mktemp)
        local line_num=0

        while IFS= read -r line; do
            line_num=$((line_num + 1))
            if [ "$indent_style" == "space" ]; then
                if [[ "$line" == $'	'* ]]; then
                    if [ $FIX_MODE -eq 1 ]; then
                        local space_indent=""
                        for (( c=0; c<$indent_size; c++ )); do space_indent+=" "; done
                        line=$(echo "$line" | sed -e ":a;s/^\t/$space_indent/;ta")
                        file_modified=1
                        echo -e "${C_CYAN}FIXED: [$(basename "$file"):$line_num] Replaced leading tab(s) with spaces.${C_NC}"
                    else
                        echo -e "${C_RED}ERROR: [$(basename "$file"):$line_num] Line starts with a tab, but style is set to 'space'.${C_NC}"
                        file_errors=$((file_errors + 1))
                    fi
                fi
                local leading_spaces=$(expr "$line" : '\( *\)')
                if [ $(( ${#leading_spaces} % indent_size )) -ne 0 ]; then
                    echo -e "${C_RED}ERROR: [$(basename "$file"):$line_num] Invalid indentation size. Found ${#leading_spaces} spaces. (Auto-fix not supported)${C_NC}"
                    file_errors=$((file_errors + 1))
                fi
            fi
            echo "$line" >> "$tmp_file"
        done < "$file"

        if [ $file_modified -eq 1 ]; then
            mv "$tmp_file" "$file"
            files_fixed=$((files_fixed + 1))
        else
            rm "$tmp_file"
        fi
        total_errors=$((total_errors + file_errors))
    done < "$file_list_tmp"

    rm "$file_list_tmp"

    if [ $files_fixed -gt 0 ]; then
        echo -e "${C_GREEN}SUCCESS: Automatically fixed indentation in $files_fixed file(s).${C_NC}"
    fi
    if [ $total_errors -gt 0 ]; then
        echo -e "${C_RED}Indentation check failed with $total_errors unfixable error(s).${C_NC}"
        return 1
    fi

    echo -e "${C_GREEN}SUCCESS: All files adhere to the parsed .editorconfig rules.${C_NC}"
    return 0
}

run_data_validation() {
    echo -e "\n${C_BLUE}INFO: Starting CSV data validation...${C_NC}"
    local total_errors=0
    local tmp_dir="$SCRIPT_DIR/tmp_ids"
    mkdir -p "$tmp_dir"

    # --- 1. Validate provinces.csv ---
    echo -e "${C_BLUE}INFO: Validating provinces.csv...${C_NC}"
    if awk -F, 'BEGIN {err=0} NR > 1 { if ($1 !~ /^[0-9]+$/) { printf "ERROR: [provinces.csv:%d] Column 'id' ('%s') is invalid.\n", NR, $1; err=1 } } END { exit err }' "$CSV_DIR/provinces.csv"; then
        awk -F, 'NR > 1 {print $1}' "$CSV_DIR/provinces.csv" > "$tmp_dir/province_ids.txt"
        echo -e "${C_GREEN}SUCCESS: No issues found in provinces.csv.${C_NC}"
    else
        total_errors=1
    fi
    echo "---"

    # --- 2. Validate regencies.csv ---
    echo -e "${C_BLUE}INFO: Validating regencies.csv...${C_NC}"
    local regency_errors=0
    awk -F, -v file="regencies.csv" 'BEGIN {err=0} NR > 1 { if ($1 !~ /^[0-9]+$/) {err=1} if ($2 !~ /^[0-9]+$/) {err=1} if (substr($1, 1, length($2)) != $2) {err=1} } END { exit err }' "$CSV_DIR/regencies.csv" || regency_errors=1
    while IFS=, read -r id province_id name; do
        if ! grep -q -x "$province_id" "$tmp_dir/province_ids.txt"; then echo -e "${C_RED}ERROR: [regencies.csv] Referential integrity fail: 'province_id' '$province_id' not found.${C_NC}"; regency_errors=1; fi
    done < <(tail -n +2 "$CSV_DIR/regencies.csv") || true
    if [ $regency_errors -eq 0 ]; then
        awk -F, 'NR > 1 {print $1}' "$CSV_DIR/regencies.csv" > "$tmp_dir/regency_ids.txt"
        echo -e "${C_GREEN}SUCCESS: No issues found in regencies.csv.${C_NC}"
    else
        total_errors=$((total_errors + 1))
    fi
    echo "---"

    # --- 3. Validate districts.csv ---
    echo -e "${C_BLUE}INFO: Validating districts.csv...${C_NC}"
    local district_errors=0
    awk -F, -v file="districts.csv" 'BEGIN {err=0} NR > 1 { if ($1 !~ /^[0-9]+$/) {err=1} if ($2 !~ /^[0-9]+$/) {err=1} if (substr($1, 1, length($2)) != $2) {err=1} } END { exit err }' "$CSV_DIR/districts.csv" || district_errors=1
    while IFS=, read -r id regency_id name; do
        if ! grep -q -x "$regency_id" "$tmp_dir/regency_ids.txt"; then echo -e "${C_RED}ERROR: [districts.csv] Referential integrity fail: 'regency_id' '$regency_id' not found.${C_NC}"; district_errors=1; fi
    done < <(tail -n +2 "$CSV_DIR/districts.csv") || true
    if [ $district_errors -eq 0 ]; then
        awk -F, 'NR > 1 {print $1}' "$CSV_DIR/districts.csv" > "$tmp_dir/district_ids.txt"
        echo -e "${C_GREEN}SUCCESS: No issues found in districts.csv.${C_NC}"
    else
        total_errors=$((total_errors + 1))
    fi
    echo "---"

    # --- 4. Validate villages.csv (This will be VERY slow) ---
    echo -e "${C_BLUE}INFO: Validating villages.csv... (This may take a while)${C_NC}"
    local village_errors=0
    awk -F, -v file="villages.csv" 'BEGIN {err=0} NR > 1 { if ($1 !~ /^[0-9]+$/) {err=1} if ($2 !~ /^[0-9]+$/) {err=1} if (substr($1, 1, length($2)) != $2) {err=1} } END { exit err }' "$CSV_DIR/villages.csv" || village_errors=1
    while IFS=, read -r id district_id name; do
        if ! grep -q -x "$district_id" "$tmp_dir/district_ids.txt"; then echo -e "${C_RED}ERROR: [villages.csv] Referential integrity fail: 'district_id' '$district_id' not found.${C_NC}"; village_errors=1; fi
    done < <(tail -n +2 "$CSV_DIR/villages.csv") || true
    if [ $village_errors -eq 0 ]; then
        echo -e "${C_GREEN}SUCCESS: No issues found in villages.csv.${C_NC}"
    else
        total_errors=$((total_errors + 1))
    fi
    echo "---"

    rm -rf "$tmp_dir"
    return $total_errors
}

# --- Main Execution Logic ---
main() {
    if ! run_indent_check; then
        if [ $FIX_MODE -eq 0 ]; then exit 1; fi
    fi
    
    if ! run_data_validation; then
        echo -e "\n${C_RED}LINT FAIL: Data validation failed with one or more errors.${C_NC}"
        exit 1
    fi

    echo -e "\n${C_GREEN}LINT CHECKS COMPLETE.${C_NC}"
    if [ $FIX_MODE -eq 1 ]; then
        echo "Review fixed files and commit the changes."
    fi
}

main