param([Parameter(Mandatory = $true)][string]$Path)

# Find hard horizontal discontinuities in a screenshot by comparing the mean
# brightness of adjacent rows. Turns an "I think I see a seam" hunch into a
# measurement, which is what the critique is allowed to report as fact.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$bmp = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Path).Path)
try {
  $w = $bmp.Width; $h = $bmp.Height
  $means = New-Object 'double[]' $h
  # Sample every 4th column; enough for a row mean, ~4x faster.
  for ($y = 0; $y -lt $h; $y++) {
    $sum = 0.0; $n = 0
    for ($x = 0; $x -lt $w; $x += 4) {
      $c = $bmp.GetPixel($x, $y)
      $sum += (0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B)
      $n++
    }
    $means[$y] = $sum / $n
  }

  $jumps = @()
  for ($y = 1; $y -lt $h; $y++) {
    $d = $means[$y] - $means[$y - 1]
    if ([Math]::Abs($d) -ge 2.0) {
      $jumps += [pscustomobject]@{
        Row   = $y
        Delta = [Math]::Round($d, 2)
        Above = [Math]::Round($means[$y - 1], 2)
        Below = [Math]::Round($means[$y], 2)
      }
    }
  }

  Write-Output "image: $w x $h"
  if ($jumps.Count -eq 0) {
    Write-Output "no row-to-row brightness jump >= 2.0 found (no hard seam)"
  } else {
    Write-Output "hard row transitions (|delta| >= 2.0 of 255):"
    $jumps | Sort-Object { - [Math]::Abs($_.Delta) } | Select-Object -First 8 | Format-Table -AutoSize | Out-String | Write-Output
  }
} finally {
  $bmp.Dispose()
}
