# check.ps1 — mechanical guard. Run before claiming any task done.
# Exits non-zero on any violation. These six rules encode the mistakes that are
# expensive and invisible; see BUILD.md section 9.
#
# Rules 2 and 3 are COMMENT-AWARE on purpose. The first version flagged the
# manifest comment explaining why QUERY_ALL_PACKAGES is absent, and a doc comment
# listing the banned status words. A guard that fires on its own documentation
# gets ignored, and an ignored guard is worse than no guard.

$ErrorActionPreference = 'Stop'
$fail = 0
$root = Split-Path -Parent $PSScriptRoot

function Violation($rule, $detail) {
    Write-Host "FAIL  $rule" -ForegroundColor Red
    Write-Host "      $detail"
    $script:fail = 1
}

function Pass($rule) { Write-Host "ok    $rule" -ForegroundColor Green }

# Returns only the CODE portion of a file: comment-only lines dropped, and the
# trailing // comment stripped from mixed lines.
function Get-CodeLines($path) {
    $out = @()
    $inBlock = $false
    foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
        $t = $line.Trim()
        if ($inBlock) {
            if ($t -match '\*/') { $inBlock = $false }
            continue
        }
        if ($t -match '^/\*') { if ($t -notmatch '\*/') { $inBlock = $true }; continue }
        if ($t -match '^(//|\*|#|<!--)') { continue }
        $code = ($line -split '//')[0]
        if ($code.Trim()) { $out += $code }
    }
    return $out
}

$srcFiles = Get-ChildItem -Path $root -Recurse -File -Include *.kt, *.ts, *.tsx, *.sql `
    -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\build\\' }

# --- 1. No colour literal outside the token file -----------------------------
$colourHits = @()
foreach ($f in ($srcFiles | Where-Object { $_.Extension -eq '.kt' -and $_.Name -ne 'Tokens.kt' })) {
    foreach ($l in (Get-CodeLines $f.FullName)) {
        if ($l -match 'Color\(0x|#[0-9a-fA-F]{6}\b') { $colourHits += $f.FullName; break }
    }
}
if ($colourHits) {
    Violation 'colour literal outside Tokens.kt' ($colourHits -join '; ')
} else { Pass 'no colour literal outside Tokens.kt' }

# --- 2. QUERY_ALL_PACKAGES actually declared, not merely mentioned -----------
# Matches only inside a uses-permission element, so the comment saying we do NOT
# use it does not trip the rule.
$qapFiles = @()
foreach ($m in (Get-ChildItem -Path $root -Recurse -Filter AndroidManifest.xml -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\build\\' })) {
    $raw = Get-Content -LiteralPath $m.FullName -Raw
    $stripped = [regex]::Replace($raw, '(?s)<!--.*?-->', '')
    if ($stripped -match '(?s)<uses-permission[^>]*QUERY_ALL_PACKAGES') { $qapFiles += $m.FullName }
}
if ($qapFiles) {
    Violation 'QUERY_ALL_PACKAGES declared' (($qapFiles -join '; ') +
        ' — Play restricts it to device search / antivirus / file managers / browsers. A collection tracker does not qualify.')
} else { Pass 'no QUERY_ALL_PACKAGES declared' }

# --- 3. No status string outside the declared enums --------------------------
# Code lines only, and each token must look like a VALUE (quoted) or an
# identifier, not a word in an English sentence.
$banned = 'want_to_play', 'wantToPlay', 'backlog', 'completed', 'beaten', 'dropped', 'on_hold'
$enumHits = @()
foreach ($f in $srcFiles) {
    $n = 0
    foreach ($l in (Get-CodeLines $f.FullName)) {
        $n++
        foreach ($b in $banned) {
            if ($l -match ("[`"']$b[`"']|\b$b\s*=|\.\s*$b\b")) {
                $enumHits += "$($f.FullName) :: $($l.Trim())"
                break
            }
        }
    }
}
if ($enumHits) {
    Violation 'status value outside the declared enums' ($enumHits -join ' | ')
} else { Pass 'status values match BUILD.md section 4' }

# --- 4. IGDB is reachable from exactly one place -----------------------------
$igdb = $srcFiles | Where-Object { $_.FullName -notmatch 'supabase[\\/]functions' } |
    Select-String -Pattern 'api\.igdb\.com' -List
if ($igdb) {
    Violation 'IGDB called outside the Edge Function proxy' (($igdb | ForEach-Object { $_.Path }) -join '; ')
} else { Pass 'IGDB only reached via the proxy' }

# --- 5. time-to-beat is seconds; 3600 is the only legal divisor --------------
$ttb = $srcFiles | Select-String -Pattern '(timeToBeat|time_to_beat)[A-Za-z_]*\s*/\s*(?!3600)\d+' -List
if ($ttb) {
    Violation 'time-to-beat divided by something other than 3600' (($ttb | ForEach-Object { "$($_.Path):$($_.LineNumber)" }) -join '; ')
} else { Pass 'time-to-beat converted correctly' }

# --- 6. No server secret in the shipped app ---------------------------------
$secretNames = 'SUPABASE_SERVICE_ROLE', 'service_role', 'REVENUECAT_SECRET', 'sk_live_'
$appSrc = Join-Path $root 'app'
if (Test-Path $appSrc) {
    $secrets = Get-ChildItem -Path $appSrc -Recurse -File -Include *.kt, *.xml, *.properties -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\build\\' } |
        Select-String -Pattern ($secretNames -join '|') -List
    if ($secrets) {
        Violation 'server secret referenced in app source' (($secrets | ForEach-Object { $_.Path }) -join '; ')
    } else { Pass 'no server secret in app source' }
} else { Pass 'no server secret in app source (app/ not scaffolded yet)' }

if ($fail -ne 0) {
    Write-Host ''
    Write-Host 'check.ps1 FAILED. Fix the above before continuing.' -ForegroundColor Red
    exit 1
}
Write-Host ''
Write-Host 'check.ps1 passed.' -ForegroundColor Green
exit 0
