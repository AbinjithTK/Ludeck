param(
  [Parameter(Mandatory = $true)][string]$Name,
  [int]$MaxDim = 1600
)

# Capture the emulator screen and write a downscaled PNG that the image reader accepts.
# Full-res 1080x2400 shots exceed the reader's max-dimension cap for multi-image requests.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools'
if ($env:Path -notlike "*$sdk*") { $env:Path += ";$sdk" }

$outDir = Join-Path $PSScriptRoot '..\build\shots'
$null = New-Item -ItemType Directory -Force -Path $outDir
$outDir = (Resolve-Path $outDir).Path

$rawPath = Join-Path $outDir "$Name.raw.png"
$smallPath = Join-Path $outDir "$Name.png"

# On-device capture then pull is the byte-safe route; PowerShell redirection corrupts binaries.
& adb shell screencap -p /sdcard/__shot.png | Out-Null
& adb pull /sdcard/__shot.png $rawPath | Out-Null
& adb shell rm /sdcard/__shot.png | Out-Null

$src = [System.Drawing.Image]::FromFile($rawPath)
try {
  $scale = [Math]::Min(1.0, $MaxDim / [Math]::Max($src.Width, $src.Height))
  $w = [int][Math]::Round($src.Width * $scale)
  $h = [int][Math]::Round($src.Height * $scale)
  $dst = New-Object System.Drawing.Bitmap($w, $h)
  try {
    $g = [System.Drawing.Graphics]::FromImage($dst)
    try {
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.DrawImage($src, 0, 0, $w, $h)
    } finally { $g.Dispose() }
    $dst.Save($smallPath, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally { $dst.Dispose() }
  Write-Output "$smallPath ($($src.Width)x$($src.Height) -> ${w}x${h})"
} finally {
  $src.Dispose()
}
Remove-Item $rawPath -Force
