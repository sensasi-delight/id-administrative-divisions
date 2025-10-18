#!/bin/bash

# Main linting script for the project (Shell Script version).
#
# This script performs two main checks:
# 1. Indentation Check: Ensures all files adhere to the .editorconfig rules.
# 2. Data Validation: Checks for data consistency in the CSV datasets.
#
# WARNING: The data validation part of this script can be very slow,
# especially on the villages.csv file, due to the limitations of shell scripting
# for complex data lookups. For better performance, consider using the .ps1 version
# in a PowerShell environment.

set -e
set -o pipefail

# --- Constants for colored output ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_BLUE='\033[0;34m'
C_NC='\033[0m' # No Color

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CSV_DIR="$SCRIPT_DIR/../csv"

# --- Functions ---

# Checks for all required command-line tools.
check_dependencies() {
    echo -e "${C_BLUE}INFO: Checking for dependencies...${C_NC}"
    if ! command -v editorconfig-checker &> /dev/null && ! command -v ec &> /dev/null; then
        echo -e "${C_RED}ERROR: 'editorconfig-checker' (or 'ec') not found.${C_NC}" >&2
        exit 1
    fi
    # awk and grep are assumed to exist in a bash environment.
    echo -e "${C_GREEN}SUCCESS: All dependencies are installed.${C_NC}"
}

# Runs the indentation check across all repository files.
run_indent_check() {
    echo -e "\n${C_BLUE}INFO: Starting indentation check...${C_NC}"
    local ec_command="editorconfig-checker"
    if command -v ec &> /dev/null; then ec_command="ec"; fi
    $ec_command
    echo -e "${C_GREEN}SUCCESS: All files adhere to .editorconfig rules.${C_NC}"
}

# Runs the data validation checks for all CSV files.
run_data_validation() {
    echo -e "\n${C_BLUE}INFO: Starting CSV data validation...${C_NC}"
    local total_errors=0
    
    # Create a temporary directory for parent ID lists
    local tmp_dir="$SCRIPT_DIR/tmp_ids"
    mkdir -p "$tmp_dir"

    # --- 1. Validate provinces.csv ---
    echo -e "${C_BLUE}INFO: Validating provinces.csv...${C_NC}"
    local province_errors=0
    awk -F, 'BEGIN {err=0} NR > 1 { 
        if ($1 !~ /^[0-9]+$/) { printf "ERROR: [provinces.csv:%d] Column 'id' ('%s') is invalid.\n", NR, $1; err=1 }
    } END { exit err }' "$CSV_DIR/provinces.csv" || province_errors=1
    
    if [ $province_errors -eq 0 ]; then
        # Store valid province IDs for referential checks
        awk -F, 'NR > 1 {print $1}' "$CSV_DIR/provinces.csv" > "$tmp_dir/province_ids.txt"
        echo -e "${C_GREEN}SUCCESS: No issues found in provinces.csv.${C_NC}"
    fi
    total_errors=$((total_errors + province_errors))
    echo "---"

    # --- 2. Validate regencies.csv ---
    echo -e "${C_BLUE}INFO: Validating regencies.csv...${C_NC}"
    local regency_errors=0
    awk -F, -v file="regencies.csv" 'BEGIN {err=0} NR > 1 { 
        if ($1 !~ /^[0-9]+$/) { printf "ERROR: [%s:%d] Column 'id' ('%s') is invalid.\n", file, NR, $1; err=1 }
        if ($2 !~ /^[0-9]+$/) { printf "ERROR: [%s:%d] Column 'province_id' ('%s') is invalid.\n", file, NR, $2; err=1 }
        if (substr($1, 1, length($2)) != $2) { printf "ERROR: [%s:%d] ID format inconsistency: id '%s' does not start with province_id '%s'.\n", file, NR, $1, $2; err=1 }
    } END { exit err }' "$CSV_DIR/regencies.csv" || regency_errors=1
    
    # Referential integrity check (slow part)
    while IFS=, read -r id province_id name; do
        if ! grep -q -x "$province_id" "$tmp_dir/province_ids.txt"; then
            echo -e "${C_RED}ERROR: [regencies.csv] Referential integrity fail: 'province_id' '$province_id' not found in provinces.csv.${C_NC}"
            regency_errors=1
        fi
    done < <(tail -n +2 "$CSV_DIR/regencies.csv")

    if [ $regency_errors -eq 0 ]; then
        awk -F, 'NR > 1 {print $1}' "$CSV_DIR/regencies.csv" > "$tmp_dir/regency_ids.txt"
        echo -e "${C_GREEN}SUCCESS: No issues found in regencies.csv.${C_NC}"
    fi
    total_errors=$((total_errors + regency_errors))
    echo "---"

    # --- 3. Validate districts.csv ---
    echo -e "${C_BLUE}INFO: Validating districts.csv...${C_NC}"
    local district_errors=0
    # Similar checks for districts...
    awk -F, -v file="districts.csv" 'BEGIN {err=0} NR > 1 { 
        if ($1 !~ /^[0-9]+$/) { printf "ERROR: [%s:%d] Column 'id' ('%s') is invalid.\n", file, NR, $1; err=1 }
        if ($2 !~ /^[0-9]+$/) { printf "ERROR: [%s:%d] Column 'regency_id' ('%s') is invalid.\n", file, NR, $2; err=1 }
        if (substr($1, 1, length($2)) != $2) { printf "ERROR: [%s:%d] ID format inconsistency: id '%s' does not start with regency_id '%s'.\n", file, NR, $1, $2; err=1 }
    } END { exit err }' "$CSV_DIR/districts.csv" || district_errors=1

    while IFS=, read -r id regency_id name;
 do
        if ! grep -q -x "$regency_id" "$tmp_dir/regency_ids.txt"; then
            echo -e "${C_RED}ERROR: [districts.csv] Referential integrity fail: 'regency_id' '$regency_id' not found in regencies.csv.${C_NC}"
            district_errors=1
        fi
    done < <(tail -n +2 "$CSV_DIR/districts.csv")

    if [ $district_errors -eq 0 ]; then
        awk -F, 'NR > 1 {print $1}' "$CSV_DIR/districts.csv" > "$tmp_dir/district_ids.txt"
        echo -e "${C_GREEN}SUCCESS: No issues found in districts.csv.${C_NC}"
    fi
    total_errors=$((total_errors + district_errors))
    echo "---"

    # --- 4. Validate villages.csv (This will be VERY slow) ---
    echo -e "${C_BLUE}INFO: Validating villages.csv... (This may take a while)${C_NC}"
    local village_errors=0
    awk -F, -v file="villages.csv" 'BEGIN {err=0} NR > 1 { 
        if ($1 !~ /^[0-9]+$/) { printf "ERROR: [%s:%d] Column 'id' ('%s') is invalid.\n", file, NR, $1; err=1 }
        if ($2 !~ /^[0-9]+$/) { printf "ERROR: [%s:%d] Column 'district_id' ('%s') is invalid.\n", file, NR, $2; err=1 }
        if (substr($1, 1, length($2)) != $2) { printf "ERROR: [%s:%d] ID format inconsistency: id '%s' does not start with district_id '%s'.\n", file, NR, $1, $2; err=1 }
    } END { exit err }' "$CSV_DIR/villages.csv" || village_errors=1

    while IFS=, read -r id district_id name;
 do
        if ! grep -q -x "$district_id" "$tmp_dir/district_ids.txt"; then
            echo -e "${C_RED}ERROR: [villages.csv] Referential integrity fail: 'district_id' '$district_id' not found in districts.csv.${C_NC}"
            village_errors=1
        fi
    done < <(tail -n +2 "$CSV_DIR/villages.csv")

    if [ $village_errors -eq 0 ]; then
        echo -e "${C_GREEN}SUCCESS: No issues found in villages.csv.${C_NC}"
    fi
    total_errors=$((total_errors + village_errors))
    echo "---"

    # Cleanup
    rm -rf "$tmp_dir"

    return $total_errors
}

# --- Main Execution Logic ---
main() {
    check_dependencies
    run_indent_check
    
    if ! run_data_validation; then
        echo -e "\n${C_RED}LINT FAIL: Data validation failed with one or more errors.${C_NC}"
        exit 1
    fi

    echo -e "\n${C_GREEN}LINT SUCCESS: All checks passed!${C_NC}"
}

main
