<#
build_fantasy.ps1 - Efficiency Ratings (PFF-derived) + FF Ratings (Fantasy Footballers-derived).

Reads the licensed exports in pff_raw/ (gitignored) and emits derived composites only:
  data/pff.js  -> window.PFFX  { players, ol, def }   "Efficiency Rating" per player + team OL/DEF
  data/ff.js   -> window.FFX   { players }            "FF Rating" from the dynasty consensus

Efficiency Rating = weighted z-blend of PFF charting inputs, rescaled 50+15z (clamped 1-99).
It is NOT a PFF grade and is not interchangeable with one - it is a composite of several of
their charted inputs. Source is attributed in the UI.

Player keys use the nflverse short form (first-initial + '.' + last) + team, so these join to
window.PLAYS / the rest of the dashboard.
#>
param(
  [string]$Raw = "C:/Users/miles/saints-dashboard/pff_raw",
  [string]$OutDir = "C:/Users/miles/saints-dashboard",
  [int]$Year = 2025
)
$ErrorActionPreference = "Stop"

# PFF / FF team codes -> nflverse
$TEAM=@{ARZ='ARI';BLT='BAL';CLV='CLE';HST='HOU';LAR='LA';SD='LAC';OAK='LV'}
function NTeam($t){ if($null -eq $t -or $t -eq ''){return ''} ; if($TEAM.ContainsKey($t)){return $TEAM[$t]} ; return $t }
$SUFFIX=@('Jr.','Sr.','II','III','IV','V','Jr','Sr')
function ShortName($full){
  if([string]::IsNullOrWhiteSpace($full)){ return '' }
  $t=@($full.Trim() -split '\s+')
  while($t.Count -gt 2 -and $SUFFIX -contains $t[-1]){ $t=$t[0..($t.Count-2)] }
  if($t.Count -eq 1){ return $t[0] }
  return ($t[0].Substring(0,1) + '.' + ($t[1..($t.Count-1)] -join ' '))
}
function D($v){ if($null -eq $v -or $v -eq '' -or $v -eq 'NA'){ return $null } ; try{ [double]$v }catch{ $null } }
function Js($s){ if($null -eq $s){return 'null'} ; '"' + ($s -replace '\\','\\' -replace '"','\"') + '"' }
function Nn($v,[int]$dec){ if($null -eq $v){ return 'null' } ; ([math]::Round([double]$v,$dec)).ToString([Globalization.CultureInfo]::InvariantCulture) }

# z-score helper: rows = list of hashtables, key = field, returns {mean,sd}
function Stats($rows,$key){
  $v=@($rows | ForEach-Object { $_[$key] } | Where-Object { $null -ne $_ })
  if($v.Count -lt 3){ return $null }
  $m=($v | Measure-Object -Average).Average
  $sd=[math]::Sqrt((($v | ForEach-Object { ($_-$m)*($_-$m) } | Measure-Object -Sum).Sum)/$v.Count)
  if($sd -eq 0){ $sd=1 }
  return @{m=$m;sd=$sd}
}
# specs: @( @{k='grades_pass';w=1.0;inv=$false}, ... ) -> sets $_['eff']
function Composite($rows,$specs){
  $st=@{}
  foreach($s in $specs){ $st[$s.k]=Stats $rows $s.k }
  $wsum=($specs | ForEach-Object { [math]::Abs($_.w) } | Measure-Object -Sum).Sum
  foreach($r in $rows){
    $acc=0.0; $used=0.0
    foreach($s in $specs){
      $stat=$st[$s.k]; if($null -eq $stat){ continue }   # NB: $S would alias $s - PowerShell vars are case-insensitive
      $val=$r[$s.k]; if($null -eq $val){ continue }
      $z=($val-$stat.m)/$stat.sd
      if($s.inv){ $z=-$z }
      $acc += $s.w*$z; $used += [math]::Abs($s.w)
    }
    if($used -le 0){ $r['eff']=$null; continue }
    $z=$acc/$used
    $r['eff']=[math]::Max(1,[math]::Min(99,50+15*$z))
  }
}

# ---------------- QB ----------------
$qbRaw = Import-Csv (Join-Path $Raw 'passing_summary.csv') | Where-Object { $_.position -eq 'QB' -and [int]$_.dropbacks -ge 150 }
$qb=@(); foreach($r in $qbRaw){
  $qb += @{ name=$r.player; team=(NTeam $r.team_name); pos='QB'; g=[int]$r.player_game_count; db=[int]$r.dropbacks
    'grades_pass'=(D $r.grades_pass); 'btt_rate'=(D $r.btt_rate); 'twp_rate'=(D $r.twp_rate)
    'accuracy_percent'=(D $r.accuracy_percent); 'pressure_to_sack_rate'=(D $r.pressure_to_sack_rate)
    'epa'=(D $r.epa); 'qb_rating'=(D $r.qb_rating); 'ypa'=(D $r.ypa); 'avg_time_to_throw'=(D $r.avg_time_to_throw) }
}
Composite $qb @(
  @{k='grades_pass';w=1.5;inv=$false}, @{k='epa';w=1.0;inv=$false}, @{k='btt_rate';w=0.7;inv=$false},
  @{k='twp_rate';w=0.7;inv=$true},     @{k='accuracy_percent';w=0.6;inv=$false},
  @{k='pressure_to_sack_rate';w=0.5;inv=$true}, @{k='ypa';w=0.5;inv=$false}
)

# ---------------- RB ----------------
$rbRaw = Import-Csv (Join-Path $Raw 'rushing_summary.csv') | Where-Object { ($_.position -eq 'HB' -or $_.position -eq 'FB') -and [int]$_.attempts -ge 40 }
$rb=@(); foreach($r in $rbRaw){
  $att=[int]$r.attempts
  $rb += @{ name=$r.player; team=(NTeam $r.team_name); pos='RB'; g=[int]$r.player_game_count; att=$att
    'grades_run'=(D $r.grades_run); 'elusive_rating'=(D $r.elusive_rating); 'yco_attempt'=(D $r.yco_attempt)
    'breakaway_percent'=(D $r.breakaway_percent); 'ypa'=(D $r.ypa); 'grades_pass_route'=(D $r.grades_pass_route)
    'mtf_att'=$(if($att -gt 0 -and $null -ne (D $r.avoided_tackles)){ (D $r.avoided_tackles)/$att } else { $null })
    'yprr'=(D $r.yprr); 'receptions'=[int]$r.receptions; 'touchdowns'=[int]$r.touchdowns }
}
Composite $rb @(
  @{k='grades_run';w=1.5;inv=$false}, @{k='elusive_rating';w=1.0;inv=$false}, @{k='yco_attempt';w=0.9;inv=$false},
  @{k='mtf_att';w=0.8;inv=$false},    @{k='breakaway_percent';w=0.6;inv=$false}, @{k='ypa';w=0.6;inv=$false},
  @{k='grades_pass_route';w=0.5;inv=$false}
)

# ---------------- WR / TE ----------------
$recRaw = Import-Csv (Join-Path $Raw 'receiving_summary.csv') | Where-Object { ($_.position -eq 'WR' -or $_.position -eq 'TE') -and [int]$_.routes -ge 100 }
$scheme=@{}
foreach($s in (Import-Csv (Join-Path $Raw 'receiving_scheme.csv'))){ $scheme[$s.player_id]=$s }
$rec=@(); foreach($r in $recRaw){
  $sc=$scheme[$r.player_id]
  $rec += @{ name=$r.player; team=(NTeam $r.team_name); pos=$r.position; g=[int]$r.player_game_count; routes=[int]$r.routes
    'grades_pass_route'=(D $r.grades_pass_route); 'yprr'=(D $r.yprr); 'contested_catch_rate'=(D $r.contested_catch_rate)
    'drop_rate'=(D $r.drop_rate); 'caught_percent'=(D $r.caught_percent); 'targeted_qb_rating'=(D $r.targeted_qb_rating)
    'avg_depth_of_target'=(D $r.avg_depth_of_target); 'yards_after_catch_per_reception'=(D $r.yards_after_catch_per_reception)
    'targets'=[int]$r.targets; 'receptions'=[int]$r.receptions; 'yards'=[int]$r.yards; 'touchdowns'=[int]$r.touchdowns
    'slot_rate'=(D $r.slot_rate); 'wide_rate'=(D $r.wide_rate); 'inline_rate'=(D $r.inline_rate)
    'man_yprr'=$(if($sc){ D $sc.man_yprr } else { $null }); 'zone_yprr'=$(if($sc){ D $sc.zone_yprr } else { $null })
    'man_grade'=$(if($sc){ D $sc.man_grades_pass_route } else { $null }); 'zone_grade'=$(if($sc){ D $sc.zone_grades_pass_route } else { $null }) }
}
Composite $rec @(
  @{k='grades_pass_route';w=1.5;inv=$false}, @{k='yprr';w=1.2;inv=$false}, @{k='targeted_qb_rating';w=0.7;inv=$false},
  @{k='contested_catch_rate';w=0.6;inv=$false}, @{k='caught_percent';w=0.5;inv=$false}, @{k='drop_rate';w=0.5;inv=$true},
  @{k='yards_after_catch_per_reception';w=0.5;inv=$false}
)

# ---------------- team OL (blocking) ----------------
$olRows = Import-Csv (Join-Path $Raw 'offense_blocking.csv') | Where-Object { [int]$_.snap_counts_offense -ge 100 }
$olT=@{}
foreach($r in $olRows){
  $t=NTeam $r.team_name; if($t -eq ''){ continue }
  if(-not $olT.ContainsKey($t)){ $olT[$t]=@{snaps=0;pbeW=0.0;pbeN=0.0;rbW=0.0;rbN=0.0;press=0;sacks=0} }
  $o=$olT[$t]; $sn=[int]$r.snap_counts_offense
  $o.snaps+=$sn
  $pbe=D $r.pbe; if($null -ne $pbe){ $o.pbeW += $pbe*$sn; $o.pbeN += $sn }
  $rbg=D $r.grades_run_block; if($null -ne $rbg){ $o.rbW += $rbg*$sn; $o.rbN += $sn }
  $o.press += [int]$r.pressures_allowed; $o.sacks += [int]$r.sacks_allowed
}
$olRowsOut=@()
foreach($t in ($olT.Keys | Sort-Object)){ $o=$olT[$t]
  $olRowsOut += @{ team=$t; pbe=$(if($o.pbeN -gt 0){$o.pbeW/$o.pbeN}else{$null}); rblk=$(if($o.rbN -gt 0){$o.rbW/$o.rbN}else{$null}); press=$o.press; sacks=$o.sacks }
}
Composite $olRowsOut @(@{k='pbe';w=1.2;inv=$false}, @{k='rblk';w=1.0;inv=$false}, @{k='press';w=0.8;inv=$true})

# ---------------- team defense (from PFF player rows) ----------------
$dRows = Import-Csv (Join-Path $Raw 'defense_summary.csv') | Where-Object { [int]$_.snap_counts_defense -ge 100 }
$dT=@{}
foreach($r in $dRows){
  $t=NTeam $r.team_name; if($t -eq ''){ continue }
  if(-not $dT.ContainsKey($t)){ $dT[$t]=@{sn=0;covW=0.0;covN=0.0;prW=0.0;prN=0.0;runW=0.0;runN=0.0;press=0;stops=0} }
  $o=$dT[$t]; $sn=[int]$r.snap_counts_defense; $o.sn+=$sn
  $c=D $r.grades_coverage_defense; if($null -ne $c){ $o.covW += $c*[int]$r.snap_counts_coverage; $o.covN += [int]$r.snap_counts_coverage }
  $pr=D $r.grades_pass_rush_defense; if($null -ne $pr){ $o.prW += $pr*[int]$r.snap_counts_pass_rush; $o.prN += [int]$r.snap_counts_pass_rush }
  $rd=D $r.grades_run_defense; if($null -ne $rd){ $o.runW += $rd*[int]$r.snap_counts_run_defense; $o.runN += [int]$r.snap_counts_run_defense }
  $o.press += [int]$r.total_pressures; $o.stops += [int]$r.stops
}
$dRowsOut=@()
foreach($t in ($dT.Keys | Sort-Object)){ $o=$dT[$t]
  $dRowsOut += @{ team=$t; cov=$(if($o.covN -gt 0){$o.covW/$o.covN}else{$null}); rush=$(if($o.prN -gt 0){$o.prW/$o.prN}else{$null}); run=$(if($o.runN -gt 0){$o.runW/$o.runN}else{$null}); press=$o.press; stops=$o.stops }
}
Composite $dRowsOut @(@{k='cov';w=1.2;inv=$false}, @{k='rush';w=1.0;inv=$false}, @{k='run';w=0.8;inv=$false})

# ---------------- emit data/pff.js ----------------
function PlayerJson($r,$extra){
  $k=(ShortName $r.name)+'|'+$r.team
  $base="`"k`":$(Js $k),`"name`":$(Js $r.name),`"team`":$(Js $r.team),`"pos`":$(Js $r.pos),`"g`":$($r.g),`"eff`":$(Nn $r.eff 1)"
  return "{$base$extra}"
}
$qbJs = ($qb | Sort-Object { -$_.eff } | ForEach-Object { PlayerJson $_ ",`"db`":$($_.db),`"btt`":$(Nn $_.btt_rate 1),`"twp`":$(Nn $_.twp_rate 1),`"acc`":$(Nn $_.accuracy_percent 1),`"p2s`":$(Nn $_.pressure_to_sack_rate 1),`"ypa`":$(Nn $_.ypa 1),`"ttt`":$(Nn $_.avg_time_to_throw 2)" }) -join ",`n"
$rbJs = ($rb | Sort-Object { -$_.eff } | ForEach-Object { PlayerJson $_ ",`"att`":$($_.att),`"elu`":$(Nn $_.elusive_rating 1),`"yco`":$(Nn $_.yco_attempt 2),`"brk`":$(Nn $_.breakaway_percent 1),`"mtf`":$(Nn $_.mtf_att 3),`"ypa`":$(Nn $_.ypa 1),`"rec`":$($_.receptions),`"td`":$($_.touchdowns)" }) -join ",`n"
$recJs = ($rec | Sort-Object { -$_.eff } | ForEach-Object { PlayerJson $_ ",`"routes`":$($_.routes),`"yprr`":$(Nn $_.yprr 2),`"cc`":$(Nn $_.contested_catch_rate 1),`"drop`":$(Nn $_.drop_rate 1),`"adot`":$(Nn $_.avg_depth_of_target 1),`"tgt`":$($_.targets),`"yds`":$($_.yards),`"td`":$($_.touchdowns),`"slot`":$(Nn $_.slot_rate 1),`"wide`":$(Nn $_.wide_rate 1),`"manY`":$(Nn $_.man_yprr 2),`"zoneY`":$(Nn $_.zone_yprr 2),`"manG`":$(Nn $_.man_grade 1),`"zoneG`":$(Nn $_.zone_grade 1)" }) -join ",`n"
$olJs = ($olRowsOut | ForEach-Object { "`"$($_.team)`":{`"eff`":$(Nn $_.eff 1),`"pbe`":$(Nn $_.pbe 1),`"rblk`":$(Nn $_.rblk 1),`"press`":$($_.press),`"sacks`":$($_.sacks)}" }) -join ",`n"
$defJs = ($dRowsOut | ForEach-Object { "`"$($_.team)`":{`"eff`":$(Nn $_.eff 1),`"cov`":$(Nn $_.cov 1),`"rush`":$(Nn $_.rush 1),`"run`":$(Nn $_.run 1),`"press`":$($_.press),`"stops`":$($_.stops)}" }) -join ",`n"

$gen=(Get-Date).ToString('yyyy-MM-dd')
$pffJs = "window.PFFX={`"season`":$Year,`"gen`":`"$gen`",`"src`":`"Efficiency Rating - a weighted composite derived from PFF charting data (subscriber export). Not a PFF grade.`",`n" +
 "`"qb`":[`n$qbJs`n],`n`"rb`":[`n$rbJs`n],`n`"rec`":[`n$recJs`n],`n`"ol`":{`n$olJs`n},`n`"def`":{`n$defJs`n}};`n"
[System.IO.File]::WriteAllText((Join-Path $OutDir 'data/pff.js'),$pffJs,[System.Text.UTF8Encoding]::new($false))

# ---------------- FF dynasty -> data/ff.js ----------------
$ffRows = Import-Csv (Join-Path $Raw 'ff_dynasty.csv') | Where-Object { $_.Rank -ne '' -and $_.Name -ne '' }
$maxR = ($ffRows | ForEach-Object { [int]$_.Rank } | Measure-Object -Maximum).Maximum
$ffOut=@()
foreach($r in $ffRows){
  $rank=[int]$r.Rank
  $a=D $r.Andy; $j=D $r.Jason; $m=D $r.Mike
  $vals=@($a,$j,$m) | Where-Object { $null -ne $_ }
  $spread = if($vals.Count -ge 2){ ([int](($vals | Measure-Object -Maximum).Maximum)) - ([int](($vals | Measure-Object -Minimum).Minimum)) } else { $null }
  # FF Rating: rank -> 0-100, top rank = 100
  $ffr = 100.0*(1.0 - (($rank-1)/[double]$maxR))
  $ffOut += "{`"k`":$(Js ((ShortName $r.Name)+'|'+(NTeam $r.Team))),`"name`":$(Js $r.Name),`"team`":$(Js (NTeam $r.Team)),`"pos`":$(Js $r.Pos),`"age`":$(Nn (D $r.Age) 1),`"rank`":$rank,`"ffr`":$(Nn $ffr 1),`"andy`":$(Nn $a 0),`"jason`":$(Nn $j 0),`"mike`":$(Nn $m 0),`"spread`":$(Nn $spread 0)}"
}
$ffJs = "window.FFX={`"gen`":`"$gen`",`"n`":$($ffOut.Count),`"src`":`"FF Rating - derived from the Fantasy Footballers Podcast dynasty startup rankings (consensus + Andy/Jason/Mike).`",`n`"players`":[`n" + ($ffOut -join ",`n") + "`n]};`n"
[System.IO.File]::WriteAllText((Join-Path $OutDir 'data/ff.js'),$ffJs,[System.Text.UTF8Encoding]::new($false))

Write-Output "pff.js  -> QB $($qb.Count) | RB $($rb.Count) | REC $($rec.Count) | OL $($olRowsOut.Count) | DEF $($dRowsOut.Count)"
Write-Output "ff.js   -> $($ffOut.Count) players (max rank $maxR)"
