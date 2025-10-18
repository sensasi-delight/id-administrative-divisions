<#
----------------------------------------------------------------------
Synchronization Script for Open Data
Detects which file (CSV or JSON) was modified most recently
and updates the older one automatically.
----------------------------------------------------------------------
#>

$Datasets = @("provinces", "regencies", "districts", "villages")
New-Item -ItemType Directory -Force -Path "csv", "json" | Out-Null

foreach ($dataset in $Datasets) {
  $csv = "csv\$dataset.csv"
  $json = "json\$dataset.json"

  if (!(Test-Path $csv) -and !(Test-Path $json)) {
    Write-Host "⚠️ Skipping $dataset (no data files found)"
    continue
  }

  $csvTime = if (Test-Path $csv) { (Get-Item $csv).LastWriteTimeUtc } else { Get-Date 0 }
  $jsonTime = if (Test-Path $json) { (Get-Item $json).LastWriteTimeUtc } else { Get-Date 0 }

  if ($csvTime -gt $jsonTime) {
    Remove-Item $json -Force -ErrorAction SilentlyContinue
    $data = Import-Csv $csv | ForEach-Object {
      $row = $_
      foreach ($prop in $row.PSObject.Properties) {
        $name = $prop.Name
        $value = $prop.Value
        if ($value -match '^\d+$' -and $value -notlike '0*') {
          $row.$name = [int64]$value
        }
      }
      $row
    }
    $data | ConvertTo-Json -Depth 10 | Set-Content $json -Encoding UTF8
    Write-Host "✅ Updated JSON for $dataset"
  }
  elseif ($jsonTime -gt $csvTime) {
    $data = Get-Content $json | ConvertFrom-Json

    if ($data) {
      $headers = $data[0].PSObject.Properties.Name
      $csvLines = @(
        ($headers | ForEach-Object {
          if ($_ -match '[,\"]' -or $_ -like "*`n*") { '"' + ($_ -replace '"', '""') + '"' } else { $_ }
        }) -join ','
      )

      $csvLines += $data | ForEach-Object {
        $row = $_ 
        ($headers | ForEach-Object {
          $value = $row.$_
          if ($value -is [string] -and ($value -match '[,\"]' -or $value -like "*`n*")) {
            '"' + ($value -replace '"', '""') + '"'
          }
          else {
            $value
          }
        }) -join ','
      }
      $csvLines | Set-Content -Path $csv -Encoding UTF8
    }
  }
  else {
    Write-Host "✅ $dataset already synchronized"
  }
}
