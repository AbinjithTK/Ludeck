$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$manifest = Get-Content (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json

$ok = 0
$fail = 0

foreach ($s in $manifest.screens) {
    $dest = Join-Path $root $s.file
    $dir = Split-Path $dest -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    try {
        Invoke-WebRequest -Uri $s.url -OutFile $dest -UseBasicParsing -TimeoutSec 60
        $size = (Get-Item $dest).Length
        if ($size -lt 1000) { throw "suspiciously small ($size bytes)" }
        Write-Host ("OK   {0}  ({1:N0} bytes)" -f $s.file, $size)
        $ok++
    }
    catch {
        Write-Host ("FAIL {0}  -> {1}" -f $s.file, $_.Exception.Message)
        $fail++
    }
}

Write-Host ""
Write-Host "Downloaded: $ok   Failed: $fail   Total: $($manifest.screens.Count)"
