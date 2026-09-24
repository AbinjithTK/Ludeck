# check.ps1 - mechanical guard for the Flutter app. Run before claiming done.
#
# The Kotlin fallback has its own checker at fallback-kotlin\scripts\check.ps1.
# That one is rooted inside fallback-kotlin and its rules name Kotlin files, so
# this is a sibling rather than an extension of it. Until this file existed, the
# Dart code that actually ships had NO mechanical enforcement at all, and the
# colour and vocabulary rules in docs\DECISIONS.md were honoured by memory only.
#
# Rules 1, 2, 6 and 7 are COMMENT-AWARE. A guard that fires on the comment
# explaining the rule gets ignored, and an ignored guard is worse than none.

$ErrorActionPreference = 'Stop'
$fail = 0
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'app'

function Violation($rule, $detail) {
    Write-Host "FAIL  $rule" -ForegroundColor Red
    Write-Host "      $detail"
    $script:fail = 1
}

function Pass($rule) { Write-Host "ok    $rule" -ForegroundColor Green }

# Returns only the CODE portion of a Dart file: comment-only lines dropped
# (including /// doc comments), block comments skipped, and the trailing //
# comment stripped from mixed lines. String literals are kept, because a banned
# value usually appears AS a string.
#
# A line carrying `// check:ignore <reason>` is skipped entirely. The reason is
# REQUIRED: a bare marker is itself reported, so an exemption always says why it
# exists and can be argued with later. This exists because some rules have
# legitimate exceptions, above all a test that deliberately writes a banned value
# in order to prove the app survives reading one.
function Get-DartCode($path) {
    $out = @()
    $inBlock = $false
    $n = 0
    foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
        $n++
        $t = $line.Trim()
        if ($inBlock) {
            if ($t -match '\*/') { $inBlock = $false }
            continue
        }
        if ($t -match '^/\*') { if ($t -notmatch '\*/') { $inBlock = $true }; continue }
        if ($t -match '^(///|//|\*)') { continue }
        if ($line -match '//\s*check:ignore\s*(.*)$') {
            if (-not $Matches[1].Trim()) {
                $script:bareIgnores += "$(Split-Path $path -Leaf):$n"
            }
            continue
        }
        $code = ($line -split '//')[0]
        if ($code.Trim()) { $out += [pscustomobject]@{ Line = $n; Text = $code } }
    }
    return $out
}

$bareIgnores = @()

if (-not (Test-Path $app)) {
    Write-Host "no app directory at $app" -ForegroundColor Red
    exit 1
}

$dartFiles = Get-ChildItem -Path (Join-Path $app 'lib') -Recurse -File -Filter *.dart `
    -ErrorAction SilentlyContinue
$testFiles = Get-ChildItem -Path (Join-Path $app 'test') -Recurse -File -Filter *.dart `
    -ErrorAction SilentlyContinue

# --- 1. No colour literal outside the token file -----------------------------
# The palette is exactly six colours. A literal anywhere else is how a seventh
# arrives without anyone deciding to add one.
$colourHits = @()
foreach ($f in ($dartFiles | Where-Object { $_.Name -ne 'tokens.dart' })) {
    foreach ($l in (Get-DartCode $f.FullName)) {
        if ($l.Text -match 'Color\(0x|Colors\.[a-zA-Z]|#[0-9a-fA-F]{6}\b') {
            $colourHits += "$($f.Name):$($l.Line)  $($l.Text.Trim())"
        }
    }
}
if ($colourHits) {
    Violation 'colour literal outside lib/ui/tokens.dart' ($colourHits -join ' | ')
} else { Pass 'no colour literal outside tokens.dart' }

# --- 2. No status vocabulary outside the declared enums ----------------------
$banned = 'want_to_play', 'wantToPlay', 'backlog', 'completed', 'beaten', 'dropped', 'on_hold'
$enumHits = @()
foreach ($f in ($dartFiles + $testFiles)) {
    foreach ($l in (Get-DartCode $f.FullName)) {
        foreach ($b in $banned) {
            if ($l.Text -match ("[`"']$b[`"']|\b$b\s*[:=]|\.\s*$b\b")) {
                $enumHits += "$($f.Name):$($l.Line)  $($l.Text.Trim())"
                break
            }
        }
    }
}
if ($enumHits) {
    Violation 'status value outside the declared enums' ($enumHits -join ' | ')
} else { Pass 'status vocabulary matches DECISIONS.md' }

# --- 3. IGDB is reachable from exactly one place -----------------------------
# IGDB has no CORS and the token must never reach a client, so every call goes
# through the Supabase Edge Function. A direct hostname in lib/ means someone
# bypassed it.
$igdb = $dartFiles | Select-String -Pattern 'api\.igdb\.com' -List
if ($igdb) {
    Violation 'IGDB called directly instead of via the proxy' (($igdb | ForEach-Object { $_.Path }) -join '; ')
} else { Pass 'IGDB only reached via the proxy' }

# --- 4. time-to-beat is seconds; 3600 is the only legal divisor --------------
$ttb = ($dartFiles + $testFiles) |
    Select-String -Pattern '(timeToBeat|time_to_beat)[A-Za-z_]*\s*(/|~/)\s*(?!3600)\d+' -List
if ($ttb) {
    Violation 'time-to-beat divided by something other than 3600' (($ttb | ForEach-Object { "$($_.Path):$($_.LineNumber)" }) -join '; ')
} else { Pass 'time-to-beat converted correctly' }

# --- 5. No server secret in the shipped app ---------------------------------
$secretNames = 'SUPABASE_SERVICE_ROLE', 'service_role', 'TWITCH_CLIENT_SECRET',
'REVENUECAT_SECRET', 'sk_live_'
$secrets = Get-ChildItem -Path $app -Recurse -File -Include *.dart, *.yaml, *.xml, *.properties `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\build\\|\\\.dart_tool\\' } |
    Select-String -Pattern ($secretNames -join '|') -List
if ($secrets) {
    Violation 'server secret referenced in app source' (($secrets | ForEach-Object { $_.Path }) -join '; ')
} else { Pass 'no server secret in app source' }

# --- 6. Ripeness stays gone -------------------------------------------------
# Removed on 2026-09-24 and replaced by completion. It came back once already as
# a duplicated condition that a scripted rename produced, which the analyzer
# could not see because it was valid Dart.
#
# The quoted-string alternative is here because the identifier patterns alone
# missed a real survivor: enums.dart shipped untouched('Not started', 'Ripe')
# for a full day after the removal, because 'Ripe' as a DISPLAY STRING matches
# no identifier shape. A metaphor word the user can read is exactly the case
# this rule exists to catch, so it must cover the string form too.
$ripeHits = @()
foreach ($f in ($dartFiles + $testFiles)) {
    foreach ($l in (Get-DartCode $f.FullName)) {
        if ($l.Text -match "\bisRipe\b|\bripeness\b|\bripe\s*[:=]|\.\s*ripe\b|['`"]Ripe['`"]") {
            $ripeHits += "$($f.Name):$($l.Line)  $($l.Text.Trim())"
        }
    }
}
if ($ripeHits) {
    Violation 'ripeness is back' (($ripeHits -join ' | ') +
        ' - completion is the only tree status; see docs/DECISIONS.md')
} else { Pass 'ripeness stays removed' }

# --- 7. No replacing conflict on a table other rows CASCADE FROM ------------
# THE most expensive bug found in this codebase. INSERT OR REPLACE deletes the
# row rather than updating it, and entries, copies and placements all declare
# REFERENCES games(igdb_id) ON DELETE CASCADE with foreign keys ON, so a
# re-import destroyed the user's status, rating, note, owned platforms and branch
# placement. Nine tests cover it; this catches the shape before they run.
#
# Scoped to the tables something else cascades FROM. `games` is the dangerous
# one, and `branches` because placements cascades from it. A replace on a LEAF
# table is safe and often correct: `place()` uses one so re-placing a game on the
# same branch updates its position, and nothing references placements, so the
# delete-and-reinsert reaches nothing. An unscoped rule flagged that and would
# have taught everyone to ignore this check.
$cascadeParents = 'games', 'branches'
$replaceHits = @()
foreach ($f in $dartFiles) {
    $lines = Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue
    $inBlock = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        # Comment-aware, like the other rules. Without this the rule flagged the
        # doc comment in repository.dart that explains why replace is forbidden,
        # which is the exact "guard fires on its own documentation" failure this
        # file's header warns about.
        if ($inBlock) {
            if ($trimmed -match '\*/') { $inBlock = $false }
            continue
        }
        if ($trimmed -match '^/\*') { if ($trimmed -notmatch '\*/') { $inBlock = $true }; continue }
        if ($trimmed -match '^(///|//|\*)') { continue }

        if ($lines[$i] -notmatch 'ConflictAlgorithm\.replace') { continue }
        if ($lines[$i] -match '//\s*check:ignore\s*\S') { continue }
        # Walk back for the table this insert targets. sqflite puts it as the
        # first positional argument, so it is within a few lines above.
        $table = $null
        for ($j = $i; $j -ge [Math]::Max(0, $i - 8); $j--) {
            if ($lines[$j] -match "insert\(\s*['`"]([a-z_]+)['`"]") { $table = $Matches[1]; break }
            if ($lines[$j] -match "^\s*['`"]([a-z_]+)['`"]\s*,") { $table = $Matches[1]; break }
        }
        if ($table -and ($cascadeParents -contains $table)) {
            $replaceHits += "$($f.Name):$($i + 1)  table '$table'"
        } elseif (-not $table) {
            $replaceHits += "$($f.Name):$($i + 1)  table could not be determined, check by hand"
        }
    }
}
if ($replaceHits) {
    Violation 'replacing conflict on a cascade-parent table' (($replaceHits -join ' | ') +
        ' - it DELETES the conflicting row and cascades. Use ON CONFLICT DO UPDATE.')
} else { Pass 'no replacing conflict on a cascade-parent table' }

# --- 9. Every ignore marker states a reason ---------------------------------
if ($bareIgnores) {
    Violation 'check:ignore with no reason given' ($bareIgnores -join '; ')
} else { Pass 'every exemption states a reason' }

# --- 10. The share layer never carries a third party's name -----------------
# docs\DECISIONS.md invariant 10: the share payload is title, cover, status and
# rating ONLY. Two columns hold a real person's name and neither may leave the
# device: entries.recommended_by (who suggested the game) and sources.channel
# (whose video it came from).
#
# This is a static rule and not a test on purpose. The share layer does not
# exist yet, so there is nothing to assert against; the rule has to fire the
# moment that code is written rather than whenever someone remembers to add a
# test. Comment-aware, so the paragraph you are reading does not trip it.
$privacyHits = @()
$shareFiles = Get-ChildItem -Path (Join-Path $app 'lib') -Recurse -Filter *.dart |
    Where-Object { $_.Name -match 'share|export' }
foreach ($f in $shareFiles) {
    foreach ($l in (Get-DartCode $f.FullName)) {
        if ($l.Text -match 'recommended_by|recommendedBy|\.channel\b|sourcesFor\s*\(') {
            $privacyHits += "$($f.Name):$($l.Line)  $($l.Text.Trim())"
        }
    }
}
if ($privacyHits) {
    Violation 'share layer reaches a third party name' (($privacyHits -join ' | ') +
        ' - the share payload is title, cover, status and rating only. See' +
        ' docs\DECISIONS.md invariant 10.')
} else { Pass 'share layer carries no third party name' }

# --- 8. The analyzer and the tests actually pass ----------------------------
# A rule check that passes while the build is red is worthless.
Push-Location $app
try {
    $analyze = & flutter analyze 2>&1
    if ($analyze -match 'No issues found') { Pass 'flutter analyze clean' }
    else { Violation 'flutter analyze reported issues' (($analyze | Select-Object -Last 5) -join ' | ') }

    $tests = & flutter test 2>&1
    if ($tests -match 'All tests passed') { Pass 'flutter test green' }
    else { Violation 'flutter test failed' (($tests | Select-Object -Last 5) -join ' | ') }
} finally {
    Pop-Location
}

if ($fail -ne 0) {
    Write-Host ''
    Write-Host 'check.ps1 FAILED. Fix the above before continuing.' -ForegroundColor Red
    exit 1
}
Write-Host ''
Write-Host 'check.ps1 passed.' -ForegroundColor Green
exit 0
