# Captures the orchard at rest, mid-swipe, and after the swipe, for the meadow check.
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$out = 'F:\Abin\Ludeck\docs\shots'
function Shot([string]$name) {
    & $adb shell screencap -p "/sdcard/$name.png"
    & $adb pull "/sdcard/$name.png" "$out\$name`_raw.png" 2>&1 | Out-Null
    & $adb shell rm "/sdcard/$name.png"
    python -c "from PIL import Image; Image.open(r'$out\$name`_raw.png').resize((540,1200)).save(r'$out\$name.png')"
}
& $adb shell am force-stop com.ludeck.android
& $adb shell monkey -p com.ludeck.android -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
Start-Sleep 7
Shot 'meadow_rest'
# A slow 3 s drag right-to-left; the capture lands partway through it.
$drag = Start-Job -ScriptBlock { param($a) & $a shell input swipe 900 1400 250 1400 3000 } -ArgumentList $adb
Start-Sleep -Milliseconds 1500
Shot 'meadow_midswipe'
Wait-Job $drag | Out-Null
Start-Sleep 2
Shot 'meadow_page2'
# The customise sheet on this tree, then pick Frost + Birch + Lantern + Fence.
function TapText([string]$t) {
    & $adb shell uiautomator dump /sdcard/ui.xml 2>&1 | Out-Null
    & $adb shell uiautomator dump /sdcard/ui.xml 2>&1 | Out-Null
    $x = [xml](& $adb shell cat /sdcard/ui.xml)
    $n = $x.SelectNodes('//node') | Where-Object { $_.'content-desc' -like "*$t*" -or $_.text -like "*$t*" } | Select-Object -First 1
    if (-not $n) { Write-Output "not found: $t"; return }
    $b = [regex]::Matches($n.bounds, '\d+') | ForEach-Object { [int]$_.Value }
    & $adb shell input tap ([int](($b[0] + $b[2]) / 2)) ([int](($b[1] + $b[3]) / 2))
    Start-Sleep -Milliseconds 700
}
TapText 'Customise'
Start-Sleep 1
Shot 'customise_open'
TapText 'Frost blossom'
TapText 'Birch wood'
TapText 'Lantern'
TapText 'Fence'
Start-Sleep 2
Shot 'customise_picked'
TapText 'Done'
Start-Sleep 2
Shot 'meadow_styled'
