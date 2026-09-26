# Drive the Ludeck app on the emulator by accessible text, and capture screens.
# Usage:
#   .\tool\device.ps1 tap "Skip"          tap the first node whose text/desc matches
#   .\tool\device.ps1 type "hollow"       type text into the focused field
#   .\tool\device.ps1 shot name           capture, downscale below 2000px -> build\device\name.png
#   .\tool\device.ps1 dump                list tappable text on screen
param([string]$cmd, [string]$arg)
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$out = "F:\Abin\Ludeck\app\build\device"
New-Item -ItemType Directory -Force $out | Out-Null

function Get-Nodes {
    & $adb shell uiautomator dump /sdcard/ui.xml | Out-Null
    & $adb pull /sdcard/ui.xml "$out\ui.xml" 2>$null | Out-Null
    [xml]$x = Get-Content "$out\ui.xml" -Raw
    $x.SelectNodes('//node')
}

switch ($cmd) {
    'tap' {
        $n = Get-Nodes | Where-Object { $_.text -like "*$arg*" -or $_.'content-desc' -like "*$arg*" } | Select-Object -First 1
        if (-not $n) { "NOT FOUND: $arg"; exit 1 }
        $b = [regex]::Matches($n.bounds, '\d+') | ForEach-Object { [int]$_.Value }
        $x = [int](($b[0] + $b[2]) / 2); $y = [int](($b[1] + $b[3]) / 2)
        & $adb shell input tap $x $y
        "tapped '$arg' at $x,$y"
    }
    'tapxy' { $p = $arg -split ','; & $adb shell input tap $p[0] $p[1]; "tapped $arg" }
    'type' { & $adb shell input text ($arg -replace ' ', '%s'); "typed $arg" }
    'dump' {
        Get-Nodes | Where-Object { $_.text -or $_.'content-desc' } |
            ForEach-Object { "{0} | {1} | {2}" -f $_.text, $_.'content-desc', $_.bounds }
    }
    'shot' {
        & $adb shell screencap -p /sdcard/s.png
        & $adb pull /sdcard/s.png "$out\raw.png" 2>$null | Out-Null
        Add-Type -AssemblyName System.Drawing
        $src = [System.Drawing.Image]::FromFile("$out\raw.png")
        $s = 0.45
        $dst = New-Object System.Drawing.Bitmap ([int]($src.Width * $s)), ([int]($src.Height * $s))
        $g = [System.Drawing.Graphics]::FromImage($dst)
        $g.InterpolationMode = 'HighQualityBicubic'
        $g.DrawImage($src, 0, 0, $dst.Width, $dst.Height)
        $dst.Save("$out\$arg.png", [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $dst.Dispose(); $src.Dispose()
        "$out\$arg.png"
    }
}
