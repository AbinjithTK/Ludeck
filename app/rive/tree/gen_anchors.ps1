# Generates lib/ui/tree/tree_anchors.dart from rive/tree/scene.rml.
#
# WHY THIS EXISTS
# The anchors were first written by hand, by reading vertex coordinates out of
# the RML and estimating where the middle of each branch was. They were wrong,
# and fruit hung off the branches in the running app. They were also a silent
# coupling: move a branch in the RML and nothing fails, the fruit just float.
#
# A branch in the RML is a CLOSED path: it runs out along one edge to the tip and
# back along the other. So the branch centreline is the midpoint of each
# corresponding pair of vertices, first with last, second with second-last, and
# so on. That is what this computes.
#
# Run after changing any branch:
#   powershell -File rive/tree/gen_anchors.ps1

$ErrorActionPreference = 'Stop'
$root   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # app/
$rml    = Join-Path $root 'rive\tree\scene.rml'
$outDart= Join-Path $root 'lib\ui\tree\tree_anchors.dart'

$text = Get-Content $rml -Raw

# Which artboard layer each branch belongs to, and how much of its length is
# usable. Fruit near the trunk look wrong (they read as growths on the trunk),
# and fruit exactly on the tip look like they are about to fall off, so each
# branch is sampled between these fractions of its centreline.
$branchConfig = @{
  'BranchFrontLeft'  = @{ depth = 1.00; from = 0.34; to = 0.94; count = 3 }
  'BranchFrontRight' = @{ depth = 1.00; from = 0.34; to = 0.94; count = 3 }
  'BranchMidLeft'    = @{ depth = 0.60; from = 0.36; to = 0.92; count = 3 }
  'BranchMidRight'   = @{ depth = 0.60; from = 0.36; to = 0.92; count = 3 }
  'BranchBackLeft'   = @{ depth = 0.25; from = 0.40; to = 0.92; count = 2 }
  'BranchBackRight'  = @{ depth = 0.25; from = 0.40; to = 0.92; count = 2 }
  'BranchLeader'     = @{ depth = 0.80; from = 0.55; to = 0.90; count = 1 }
}

# Shapes carry an x offset (the trunk and branches all sit at x=200), and the
# vertices are relative to it. Anchors must be in artboard space.
$shapePattern = '(?s)<Shape\s+x="(?<sx>-?[\d.]+)"\s+y="(?<sy>-?[\d.]+)"\s+name="(?<name>[A-Za-z]+)"[^>]*>(?<body>.*?)</Shape>'
$vertexPattern = '<StraightVertex\s+x="(?<x>-?[\d.]+)"\s+y="(?<y>-?[\d.]+)"'

$anchors = New-Object System.Collections.Generic.List[object]

foreach ($m in [regex]::Matches($text, $shapePattern)) {
  $name = $m.Groups['name'].Value
  if (-not $branchConfig.ContainsKey($name)) { continue }

  $cfg = $branchConfig[$name]
  $sx  = [double]$m.Groups['sx'].Value
  $sy  = [double]$m.Groups['sy'].Value

  $vs = New-Object 'System.Collections.Generic.List[double[]]'
  foreach ($v in [regex]::Matches($m.Groups['body'].Value, $vertexPattern)) {
    $vs.Add([double[]]@([double]$v.Groups['x'].Value, [double]$v.Groups['y'].Value))
  }
  if ($vs.Count -lt 4) { continue }

  # Centreline: pair first with last, second with second-last, and so on. For an
  # even vertex count that is exactly count/2 points, running base to tip.
  $n = $vs.Count
  $centre = New-Object 'System.Collections.Generic.List[double[]]'
  for ($i = 0; $i -lt [int]($n / 2); $i++) {
    $a = $vs[$i]
    $b = $vs[$n - 1 - $i]
    $cx = (($a[0] + $b[0]) / 2.0) + $sx
    $cy = (($a[1] + $b[1]) / 2.0) + $sy
    $centre.Add([double[]]@($cx, $cy))
  }

  # Cumulative arc length, so samples are evenly spaced along the branch rather
  # than evenly spaced by vertex index. Vertices bunch near the tip.
  $seg = New-Object 'System.Collections.Generic.List[double]'
  $seg.Add(0.0)
  $total = 0.0
  for ($i = 1; $i -lt $centre.Count; $i++) {
    $dx = $centre[$i][0] - $centre[$i-1][0]
    $dy = $centre[$i][1] - $centre[$i-1][1]
    $total += [math]::Sqrt(($dx * $dx) + ($dy * $dy))
    $seg.Add($total)
  }
  if ($total -le 0) { continue }

  $count = [int]$cfg.count
  for ($k = 0; $k -lt $count; $k++) {
    $f = if ($count -eq 1) { ($cfg.from + $cfg.to) / 2 }
         else { $cfg.from + (($cfg.to - $cfg.from) * $k / ($count - 1)) }
    $target = $f * $total

    # Walk the segments to find the point at this arc length.
    $j = 1
    while ($j -lt $seg.Count -and $seg[$j] -lt $target) { $j++ }
    if ($j -ge $seg.Count) { $j = $seg.Count - 1 }
    $span = $seg[$j] - $seg[$j-1]
    $t = if ($span -gt 0) { ($target - $seg[$j-1]) / $span } else { 0 }
    $px = $centre[$j-1][0] + (($centre[$j][0] - $centre[$j-1][0]) * $t)
    $py = $centre[$j-1][1] + (($centre[$j][1] - $centre[$j-1][1]) * $t)

    $anchors.Add([pscustomobject]@{
      Branch = $name
      Depth  = [double]$cfg.depth
      X      = [math]::Round($px, 1)
      Y      = [math]::Round($py, 1)
    })
  }
}

# Front layers first, so early games take the branches where they read best.
$order = @{ 'TreeFront' = 0; 'TreeMid' = 1; 'TreeBack' = 2 }
function LayerOf($n) {
  if ($n -like '*Front*') { return 'TreeFront' }
  if ($n -like '*Back*')  { return 'TreeBack' }
  return 'TreeMid'
}
$anchors = $anchors | Sort-Object @{e={$order[(LayerOf $_.Branch)]}}, @{e={$_.Branch}}, @{e={$_.Y}}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('// GENERATED FILE. Do not edit by hand.')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('// Produced by rive/tree/gen_anchors.ps1 from rive/tree/scene.rml.')
[void]$sb.AppendLine('// Re-run it after moving any branch:')
[void]$sb.AppendLine('//   powershell -File rive/tree/gen_anchors.ps1')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('// A branch in the RML is a closed path: out along one edge to the tip and back')
[void]$sb.AppendLine('// along the other. So its centreline is the midpoint of each corresponding pair')
[void]$sb.AppendLine('// of vertices, and these anchors are sampled at even arc lengths along it.')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('// Anchors stop short of both ends on purpose. A fruit near the trunk reads as a')
[void]$sb.AppendLine('// growth on the trunk, and a fruit exactly on the tip looks about to fall off.')
[void]$sb.AppendLine('library;')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("import 'dart:ui';")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('/// The artboard size every coordinate below is expressed in.')
[void]$sb.AppendLine('const Size kTreeArtboardSize = Size(400, 560);')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('/// One place a fruit can hang.')
[void]$sb.AppendLine('class BranchAnchor {')
[void]$sb.AppendLine('  const BranchAnchor({')
[void]$sb.AppendLine('    required this.position,')
[void]$sb.AppendLine('    required this.depth,')
[void]$sb.AppendLine('    required this.branch,')
[void]$sb.AppendLine('  });')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('  /// In artboard space.')
[void]$sb.AppendLine('  final Offset position;')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('  /// 0 is the back layer, 1 the front. Fruit inherit their branch depth, so a')
[void]$sb.AppendLine('  /// fruit on a back branch is drawn smaller and dimmer. Without this, fruit')
[void]$sb.AppendLine('  /// would flatten the depth the artboard just built.')
[void]$sb.AppendLine('  final double depth;')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('  /// The RML shape this belongs to, so a diff against the artwork is readable.')
[void]$sb.AppendLine('  final String branch;')
[void]$sb.AppendLine('}')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('/// Front layer first.')
[void]$sb.AppendLine('const List<BranchAnchor> kBranchAnchors = [')
foreach ($a in $anchors) {
  [void]$sb.AppendLine(("  BranchAnchor(position: Offset({0}, {1}), depth: {2}, branch: '{3}')," -f $a.X, $a.Y, $a.Depth.ToString('0.00'), $a.Branch))
}
[void]$sb.AppendLine('];')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('/// Where a seed sits. Seeds are spotted, not owned, so they are not on a branch')
[void]$sb.AppendLine('/// at all; they rest in the soil and may rest there forever without reproach.')
[void]$sb.AppendLine('const List<Offset> kSoilAnchors = [')
[void]$sb.AppendLine('  Offset(150, 498),')
[void]$sb.AppendLine('  Offset(182, 506),')
[void]$sb.AppendLine('  Offset(224, 504),')
[void]$sb.AppendLine('  Offset(256, 497),')
[void]$sb.AppendLine('];')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('/// Fruit radius in artboard space, by depth. A fruit on a back branch is')
[void]$sb.AppendLine('/// genuinely smaller, not just dimmer, because size is the stronger cue.')
[void]$sb.AppendLine('double fruitRadiusForDepth(double depth) => 8 + (depth * 5);')

Set-Content -Path $outDart -Value $sb.ToString() -NoNewline -Encoding UTF8

Write-Output ("wrote " + $outDart)
Write-Output ("anchors: " + $anchors.Count)
$anchors | ForEach-Object { Write-Output ("  {0,-18} depth {1}  ({2}, {3})" -f $_.Branch, $_.Depth, $_.X, $_.Y) }
