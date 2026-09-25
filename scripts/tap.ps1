param(
  [string]$Label,
  [switch]$ListOnly
)

# Tap an element by its accessibility label, resolved from a real uiautomator dump.
# Guessing pixel coordinates cost several wasted cycles; the dump carries exact bounds.

$ErrorActionPreference = 'Stop'
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools'
if ($env:Path -notlike "*$sdk*") { $env:Path += ";$sdk" }

$scratch = if ($env:KIROCREW_SCRATCH) { $env:KIROCREW_SCRATCH } else { $env:TEMP }
$local = Join-Path $scratch 'ui.xml'

& adb shell uiautomator dump /sdcard/__ui.xml | Out-Null
& adb pull /sdcard/__ui.xml $local | Out-Null
& adb shell rm /sdcard/__ui.xml | Out-Null

$xml = Get-Content $local -Raw

if ($ListOnly) {
  [regex]::Matches($xml, 'content-desc="([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value } |
    Where-Object { $_ -ne '' } |
    Select-Object -Unique
  return
}

# Match the node whose content-desc contains the label, then read its bounds attribute.
$pattern = 'content-desc="([^"]*' + [regex]::Escape($Label) + '[^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
$m = [regex]::Match($xml, $pattern)

if (-not $m.Success) {
  Write-Output "NOT FOUND: $Label"
  exit 1
}

$x1 = [int]$m.Groups[2].Value; $y1 = [int]$m.Groups[3].Value
$x2 = [int]$m.Groups[4].Value; $y2 = [int]$m.Groups[5].Value
$cx = [int](($x1 + $x2) / 2); $cy = [int](($y1 + $y2) / 2)

& adb shell input tap $cx $cy | Out-Null
Write-Output "tapped '$($m.Groups[1].Value)' at ($cx,$cy) bounds [$x1,$y1][$x2,$y2]"
