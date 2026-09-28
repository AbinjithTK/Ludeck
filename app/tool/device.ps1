# Drive the Ludeck app on the emulator by accessible text, and capture screens.
# Usage:
#   .\tool\device.ps1 check               is an emulator attached? (never hangs)
#   .\tool\device.ps1 tap "Skip"          tap the first node whose text/desc matches
#   .\tool\device.ps1 type "hollow"       type text into the focused field
#   .\tool\device.ps1 shot name           capture, downscale below 2000px -> build\device\name.png
#   .\tool\device.ps1 dump                list tappable text on screen
#
# Every adb call goes through Invoke-Adb, which has a hard timeout. A bare
# `adb devices` with no running server starts a daemon that inherits the
# caller's pipes, so the agent's shell call never returns and the whole
# Kiro Crew turn wedges (2026-09-28). With the timeout, a stuck call kills
# its own adb child and reports instead of blocking.
param([string]$cmd, [string]$arg)
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$out = "F:\Abin\Ludeck\app\build\device"
New-Item -ItemType Directory -Force $out | Out-Null

function Invoke-Adb([string[]]$argv, [int]$timeoutSec = 20) {
    $log = Join-Path $out 'adb.out'
    $err = Join-Path $out 'adb.err'
    $p = Start-Process $adb -ArgumentList $argv -NoNewWindow -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError $err
    if (-not $p.WaitForExit($timeoutSec * 1000)) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        throw "adb $($argv -join ' ') STILL HANGING after ${timeoutSec}s (killed)"
    }
    Get-Content $log -Raw
}

function Assert-Device {
    # Start the server detached first, so no later call is the one that spawns it.
    Invoke-Adb @('start-server') 15 | Out-Null
    $list = Invoke-Adb @('devices') 10
    $lines = ($list -split "`n") | Where-Object { $_ -match '\tdevice\s*$' }
    if (-not $lines) { "NO DEVICE attached. Boot the emulator first."; exit 2 }
    $lines
}

function Get-Nodes {
    Invoke-Adb @('shell', 'uiautomator', 'dump', '/sdcard/ui.xml') 30 | Out-Null
    Invoke-Adb @('pull', '/sdcard/ui.xml', "$out\ui.xml") | Out-Null
    [xml]$x = Get-Content "$out\ui.xml" -Raw
    $x.SelectNodes('//node')
}

if ($cmd -ne 'check') { Assert-Device | Out-Null }

switch ($cmd) {
    'check' { Assert-Device }
    'tap' {
        $n = Get-Nodes | Where-Object { $_.text -like "*$arg*" -or $_.'content-desc' -like "*$arg*" } | Select-Object -First 1
        if (-not $n) { "NOT FOUND: $arg"; exit 1 }
        $b = [regex]::Matches($n.bounds, '\d+') | ForEach-Object { [int]$_.Value }
        $x = [int](($b[0] + $b[2]) / 2); $y = [int](($b[1] + $b[3]) / 2)
        Invoke-Adb @('shell', 'input', 'tap', "$x", "$y") | Out-Null
        "tapped '$arg' at $x,$y"
    }
    'tapxy' { $p = $arg -split ','; Invoke-Adb @('shell', 'input', 'tap', $p[0], $p[1]) | Out-Null; "tapped $arg" }
    'type' { Invoke-Adb @('shell', 'input', 'text', ($arg -replace ' ', '%s')) | Out-Null; "typed $arg" }
    'dump' {
        Get-Nodes | Where-Object { $_.text -or $_.'content-desc' } |
            ForEach-Object { "{0} | {1} | {2}" -f $_.text, $_.'content-desc', $_.bounds }
    }
    'shot' {
        Invoke-Adb @('shell', 'screencap', '-p', '/sdcard/s.png') | Out-Null
        Invoke-Adb @('pull', '/sdcard/s.png', "$out\raw.png") | Out-Null
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
