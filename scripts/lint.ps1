<#
.SYNOPSIS
    A linting script for the project.
.DESCRIPTION
    This script performs two main checks:
    1. Indentation Check: Ensures all files adhere to the .editorconfig rules using 'editorconfig-checker'.
    2. Data Validation: Checks for data consistency and referential integrity in the CSV datasets.
#>

# --- Script Configuration ---
$ErrorActionPreference = "Stop"

# --- Helper Functions ---
function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Level = "INFO"
    )

    $color = switch ($Level) {
        "INFO"    { "Blue" }
        "SUCCESS" { "Green" }
        "ERROR"   { "Red" }
        default   { "White" }
    }

    Write-Host -ForegroundColor $color "$($Level.ToUpper()): $Message"
}

# --- Main Logic Functions ---

function Test-Indentation {
    Write-Log -Level INFO "Starting indentation check..."

    $checker = Get-Command -Name "editorconfig-checker" -ErrorAction SilentlyContinue
    if (-not $checker) {
        $checker = Get-Command -Name "ec" -ErrorAction SilentlyContinue
    }

    if (-not $checker) {
        Write-Log -Level ERROR "'editorconfig-checker' (or 'ec') not found."
        Write-Host "Please install it by following the instructions at: https://github.com/editorconfig-checker/editorconfig-checker" -ForegroundColor Yellow
        return $false
    }

    $process = Start-Process -FilePath $checker.Source -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Log -Level ERROR "Indentation check failed. Please fix the files listed above."
        return $false
    }

    Write-Log -Level SUCCESS "All files adhere to .editorconfig rules."
    return $true
}

function Test-DataConsistency {
    Write-Log -Level INFO "Starting CSV data validation..."

    $basePath = Join-Path $PSScriptRoot "..\csv"
    $totalErrors = 0

    # Define schema: File, ID Column, Parent ID Column, Parent ID Set
    $schemas = @(
        @{ File = "provinces.csv"; IdCol = "id"; ParentCol = $null; ParentSet = $null },
        @{ File = "regencies.csv"; IdCol = "id"; ParentCol = "province_id"; ParentSet = [System.Collections.Generic.HashSet[string]]::new() },
        @{ File = "districts.csv"; IdCol = "id"; ParentCol = "regency_id"; ParentSet = [System.Collections.Generic.HashSet[string]]::new() },
        @{ File = "villages.csv"; IdCol = "id"; ParentCol = "district_id"; ParentSet = [System.Collections.Generic.HashSet[string]]::new() }
    )

    $idSets = @{ 
        provinces = $schemas[1].ParentSet;
        regencies = $schemas[2].ParentSet;
        districts = $schemas[3].ParentSet;
    }

    foreach ($schema in $schemas) {
        $file = $schema.File
        $filePath = Join-Path $basePath $file
        $fileErrors = 0
        Write-Log -Level INFO "Validating $file..."

        if (-not (Test-Path $filePath)) {
            Write-Log -Level ERROR "[$file:0] File not found."
            $totalErrors++
            continue
        }

        $data = Import-Csv -Path $filePath
        $parentSet = $schema.ParentSet
        $entityName = $file.Replace(".csv", "")

        foreach ($row in $data) {
            $lineNumber = $row.psobject.Properties["PS_ROW_NUMBER"].Value + 1
            $itemId = $row.($schema.IdCol)
            
            # 1. Validate ID format
            if ($itemId -notmatch '^\d+$') {
                Write-Log -Level ERROR "[$file:$lineNumber] Column '($schema.IdCol)' ('$itemId') is invalid. Must be a numeric string."
                $fileErrors++
                continue
            }

            # Store valid ID for child checks
            if ($idSets.ContainsKey($entityName)) {
                [void]$idSets[$entityName].Add($itemId)
            }

            # 2. Validate parent reference (if applicable)
            if ($schema.ParentCol) {
                $parentId = $row.($schema.ParentCol)

                if ($parentId -notmatch '^\d+$') {
                    Write-Log -Level ERROR "[$file:$lineNumber] Column '($schema.ParentCol)' ('$parentId') is invalid. Must be a numeric string."
                    $fileErrors++
                }
                elseif (-not $parentSet.Contains($parentId)) {
                    Write-Log -Level ERROR "[$file:$lineNumber] Referential integrity fail: '($schema.ParentCol)' '$parentId' not found in parent dataset."
                    $fileErrors++
                }

                # 3. Check for prefix consistency
                if (-not $itemId.StartsWith($parentId)) {
                    Write-Log -Level ERROR "[$file:$lineNumber] ID format inconsistency: '($schema.IdCol)' '$itemId' does not start with '($schema.ParentCol)' '$parentId'."
                    $fileErrors++
                }
            }
        }

        if ($fileErrors -eq 0) {
            Write-Log -Level SUCCESS "No issues found in $file."
        }
        $totalErrors += $fileErrors
        Write-Host "---"
    }

    if ($totalErrors -gt 0) {
        Write-Log -Level ERROR "Found $totalErrors total error(s)."
        return $false
    }
    
    Write-Log -Level SUCCESS "Data validation complete. All data is consistent!"
    return $true
}

# --- Main Execution ---
function main {
    $indentSuccess = Test-Indentation
    if (-not $indentSuccess) {
        exit 1
    }

    Write-Host ""
    $dataSuccess = Test-DataConsistency
    if (-not $dataSuccess) {
        exit 1
    }

    Write-Log -Level SUCCESS "LINT SUCCESS: All checks passed!"
}

main
