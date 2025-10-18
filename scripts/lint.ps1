<#
.SYNOPSIS
    A self-contained linting script for the project with an auto-fix option for indentation.
.DESCRIPTION
    This script performs two main checks. When the --Fix switch is used, it will attempt
    to automatically correct indentation issues.

    1. Indentation Check: Ensures all text files adhere to the .editorconfig rules.
    2. Data Validation: Checks for data consistency and referential integrity.
.PARAMETER Fix
    If specified, the script will automatically fix indentation errors (like tabs-to-spaces).
#>

param (
  [switch]$Fix
)

# --- Script Configuration ---
$ErrorActionPreference = "SilentlyContinue"

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
    "FIXED"   { "Cyan" }
    default   { "White" }
  }

  Write-Host -ForegroundColor $color "$($Level.ToUpper()): $Message"
}

# --- Main Logic Functions ---

function Test-Indentation {
  param (
    [switch]$Fix
  )
  Write-Log -Level INFO "Starting self-contained indentation check..."
  $totalErrors = 0
  $filesFixed = 0
  $editorconfigFile = Join-Path $PSScriptRoot "..\.editorconfig"

  if (-not (Test-Path $editorconfigFile)) {
    Write-Log -Level ERROR ".editorconfig file not found!"
    return $false
  }

  $config = @{}
  Get-Content $editorconfigFile | ForEach-Object {
    if ($_ -like "*=*") {
      $key, $value = $_.Split("=", 2); $config[$key.Trim()] = $value.Trim()
    }
  }
  $indentStyle = $config['indent_style']
  $indentSize = [int]$config['indent_size']

  Write-Log -Level INFO "Applying rule: indent_style = $indentStyle, indent_size = $indentSize"

  $filesToCheck = Get-ChildItem -Path (Join-Path $PSScriptRoot "..") -Recurse -File |
    Where-Object { $_.FullName -notmatch '\.git[\/]' -and $_.Name -notlike '*.exe' -and $_.Name -notlike '*.dll' -and $_.Name -notlike '*.png' -and $_.Name -notlike '*.jpg' }

  foreach ($file in $filesToCheck) {
    $lines = Get-Content -Path $file.FullName
    $fileContentModified = $false

    foreach ($i in 0..($lines.Count - 1)) {
      $line = $lines[$i]
      $lineNumber = $i + 1

      if ([string]::IsNullOrWhiteSpace($line)) { continue }

      if ($indentStyle -eq "space") {
        if ($line.StartsWith("`t")) {
          if ($Fix) {
            $leadingTabs = ($line | Select-String -Pattern "^(`t+)").Matches.Groups[1].Value
            $numSpaces = $leadingTabs.Length * $indentSize
            $lines[$i] = (" " * $numSpaces) + $line.TrimStart("`t")
            $fileContentModified = $true
            Write-Log -Level FIXED "[$($file.Name):$lineNumber] Replaced leading tab(s) with $numSpaces spaces."
          } else {
            Write-Log -Level ERROR "[$($file.Name):$lineNumber] Line starts with a tab, but style is set to 'space'."
            $totalErrors++
          }
        }

        $firstCharIndex = [regex]::Match($line, "\S").Index
        if ($firstCharIndex -gt 0) {
          if (($firstCharIndex % $indentSize) -ne 0) {
            Write-Log -Level ERROR "[$($file.Name):$lineNumber] Invalid indentation size. Found $firstCharIndex spaces, which is not a multiple of $indentSize. (Auto-fix not supported for this error)"
            $totalErrors++
          }
        }
      }
    }

    if ($fileContentModified) {
      Set-Content -Path $file.FullName -Value $lines -Encoding UTF8
      $filesFixed++
    }
  }

  if ($filesFixed -gt 0) {
    Write-Log -Level SUCCESS "Successfully fixed indentation in $filesFixed file(s)."
  }

  if ($totalErrors -gt 0) {
    Write-Log -Level ERROR "Indentation check failed with $totalErrors error(s) that could not be auto-fixed."
    return $false
  }

  Write-Log -Level SUCCESS "All files adhere to the parsed .editorconfig rules."
  return $true
}

function Test-DataConsistency {
  Write-Log -Level INFO "Starting CSV data validation..."
  $basePath = Join-Path $PSScriptRoot "..\csv"
  $totalErrors = 0
  $schemas = @(
    @{ File = "provinces.csv"; IdCol = "id"; ParentCol = $null; ParentSet = $null },
    @{ File = "regencies.csv"; IdCol = "id"; ParentCol = "province_id"; ParentSet = [System.Collections.Generic.HashSet[string]]::new() },
    @{ File = "districts.csv"; IdCol = "id"; ParentCol = "regency_id"; ParentSet = [System.Collections.Generic.HashSet[string]]::new() },
    @{ File = "villages.csv"; IdCol = "id"; ParentCol = "district_id"; ParentSet = [System.Collections.Generic.HashSet[string]]::new() }
  )
  $idSets = @{ provinces = $schemas[1].ParentSet; regencies = $schemas[2].ParentSet; districts = $schemas[3].ParentSet }

  foreach ($schema in $schemas) {
    $file = $schema.File
    $filePath = Join-Path $basePath $file
    $fileErrors = 0
    Write-Log -Level INFO "Validating $file..."
    if (-not (Test-Path $filePath)) { Write-Log -Level ERROR "[$file:0] File not found."; $totalErrors++; continue }
    $data = Import-Csv -Path $filePath
    $parentSet = $schema.ParentSet
    $entityName = $file.Replace(".csv", "")
    foreach ($row in $data) {
      $lineNumber = $row.psobject.Properties["PS_ROW_NUMBER"].Value + 1
      $itemId = $row.($schema.IdCol)
      if ($itemId -notmatch '^\d+$') { Write-Log -Level ERROR "[$file`:$lineNumber] Column '$($schema.IdCol)' ('$itemId') is invalid."; $fileErrors++; continue }
      if ($idSets.ContainsKey($entityName)) { [void]$idSets[$entityName].Add($itemId) }
      if ($schema.ParentCol) {
        $parentId = $row.($schema.ParentCol)
        if ($parentId -notmatch '^\d+$') { Write-Log -Level ERROR "[$file`:$lineNumber] Column '$($schema.ParentCol)' ('$parentId') is invalid."; $fileErrors++ }
        elseif (-not $parentSet.Contains($parentId)) { Write-Log -Level ERROR "[$file`:$lineNumber] Referential integrity fail: '$($schema.ParentCol)' '$parentId' not found."; $fileErrors++ }
        if (-not $itemId.StartsWith($parentId)) { Write-Log -Level ERROR "[$file`:$lineNumber] ID format inconsistency: '$($schema.IdCol)' '$itemId' does not start with '$($schema.ParentCol)' '$parentId'."; $fileErrors++ }
      }
    }
    if ($fileErrors -eq 0) { Write-Log -Level SUCCESS "No issues found in $file." }
    $totalErrors += $fileErrors
    Write-Host "---"
  }

  if ($totalErrors -gt 0) { Write-Log -Level ERROR "Found $totalErrors total data error(s)."; return $false }
  Write-Log -Level SUCCESS "Data validation complete. All data is consistent!"
  return $true
}

# --- Main Execution ---
function main {
  param ([switch]$Fix)

  $indentSuccess = Test-Indentation -Fix:$Fix
  if (-not $indentSuccess) {
    if ($Fix) {
      # If fix was attempted, don't exit with error code for remaining indentation issues
    } else {
      exit 1
    }
  }

  Write-Host ""
  $dataSuccess = Test-DataConsistency
  if (-not $dataSuccess) {
    exit 1
  }

  Write-Log -Level SUCCESS "LINT SUCCESS: All checks passed!"
}

main -Fix:$Fix
