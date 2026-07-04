<#
build_plays.ps1 — play-level field-chart dataset for the Saints dashboard.

Streams nflverse play-by-play (gzipped CSV) and emits compact, per-team play-level
JSON for the interactive field views (pass throw charts + rush charts), all 32 teams.

This is the local/prototype version of the weekly pipeline transform: the same
projection will run in CI (R nflreadr / Python nfl_data_py) against fresh nflverse
data during the season. Pure PowerShell — no Python/Node required.

Outputs (under <Out>/data/):
  plays/<TEAM>.json   { "pass":[ [..] ], "rush":[ [..] ] }
  plays_index.json    season, generated, field order, per-team counts + passer/rusher lists

Pass row : [wk, def, qb, rec, ay, loc, yl, dn, yg, yac, epa, succ, out, td]
Rush row : [wk, def, run, gap, dir, yl, dn, yg, epa, succ, td, fum]
  loc/dir: 0=left 1=middle 2=right ; gap: 0=guard 1=tackle 2=end ; out: C/I/N (complete/incomplete/intercepted)
#>
param(
  [string]$Gz  = "C:/Users/miles/AppData/Local/Temp/claude/C--Users-miles--claude/43c60d0d-1058-41de-8b01-6569684d112c/scratchpad/pbp2025.csv.gz",
  [string]$Part = "C:/Users/miles/AppData/Local/Temp/claude/C--Users-miles--claude/43c60d0d-1058-41de-8b01-6569684d112c/scratchpad/part2025.csv",
  [string]$Ftn = "C:/Users/miles/AppData/Local/Temp/claude/C--Users-miles--claude/43c60d0d-1058-41de-8b01-6569684d112c/scratchpad/ftn2025.csv",
  [string]$Roster = "C:/Users/miles/AppData/Local/Temp/claude/C--Users-miles--claude/43c60d0d-1058-41de-8b01-6569684d112c/scratchpad/roster2025.csv",
  [string]$OutDir = "C:/Users/miles/AppData/Local/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/local-agent-mode-sessions/eb2236da-4f45-4faf-848a-e61ff1c5f82e/1e19824b-7456-46d5-a988-785586ae0cbb/local_97362316-1558-446f-8479-3a400f8303cf/outputs",
  [int]$Year = 2025,      # season written into plays_index.json
  [int]$Limit = 0,        # 0 = all rows; >0 = stop early (validation)
  [switch]$DryRun         # parse + summarize but do not write files
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName Microsoft.VisualBasic

$fs  = [System.IO.File]::OpenRead($Gz)
$gzs = New-Object System.IO.Compression.GZipStream($fs,[System.IO.Compression.CompressionMode]::Decompress)
$tp  = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($gzs)
$tp.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
$tp.SetDelimiters(@(","))
$tp.HasFieldsEnclosedInQuotes = $true

# header -> index
$hdr = $tp.ReadFields()
$ix = @{}
for($i=0;$i -lt $hdr.Length;$i++){ $ix[$hdr[$i]] = $i }
function C([string]$n){ $ix[$n] }
$I_gid=C 'game_id'; $I_pid=C 'play_id'; $I_sd=C 'score_differential'; $I_ytg=C 'ydstogo'
$I_week=C 'week'; $I_st=C 'season_type'; $I_pos=C 'posteam'; $I_def=C 'defteam'
$I_down=C 'down'; $I_yl=C 'yardline_100'; $I_epa=C 'epa'; $I_succ=C 'success'; $I_yg=C 'yards_gained'
$I_pass=C 'pass'; $I_rush=C 'rush'; $I_2pt=C 'two_point_attempt'
$I_qb=C 'passer_player_name'; $I_rec=C 'receiver_player_name'; $I_ay=C 'air_yards'
$I_ploc=C 'pass_location'; $I_yac=C 'yards_after_catch'
$I_cmp=C 'complete_pass'; $I_int=C 'interception'; $I_ptd=C 'pass_touchdown'; $I_cpoe=C 'cpoe'; $I_rid=C 'receiver_player_id'
$I_run=C 'rusher_player_name'; $I_rloc=C 'run_location'; $I_rgap=C 'run_gap'
$I_rtd=C 'rush_touchdown'; $I_fum=C 'fumble_lost'

function NumOrNull($v,[int]$dec=0){
  if($null -eq $v -or $v -eq '' -or $v -eq 'NA'){ return 'null' }
  $d=[double]$v; if($dec -gt 0){ return ([math]::Round($d,$dec)).ToString([Globalization.CultureInfo]::InvariantCulture) }
  return ([int][math]::Round($d)).ToString()
}
function IsOne($v){ $v -eq '1' -or $v -eq '1.0' }
function Jstr($s){
  if($null -eq $s -or $s -eq '' -or $s -eq 'NA'){ return 'null' }
  return '"' + ($s -replace '\\','\\' -replace '"','\"') + '"'
}
$LMAP=@{'left'='0';'middle'='1';'right'='2'}
$GMAP=@{'guard'='0';'tackle'='1';'end'='2'}
function MapLoc($v){ $k=[string]$v; if($LMAP.ContainsKey($k)){ $LMAP[$k] } else { 'null' } }
function MapGap($v){ $k=[string]$v; if($GMAP.ContainsKey($k)){ $GMAP[$k] } else { 'null' } }

# ---- participation join: personnel grouping, man/zone, coverage family, box ----
$COVM=@{'2_MAN'='2M';'COVER_0'='C0';'COVER_1'='C1';'COVER_2'='C2';'COVER_3'='C3';'COVER_4'='C4';'COVER_6'='C6';'COVER_9'='C9';'COMBO'='CMB'}
function PersGroup($s){
  if([string]::IsNullOrEmpty($s)){ return $null }
  $rb=0;$fb=0;$te=0
  foreach($m in [regex]::Matches($s,'(\d+)\s*(RB|FB|TE)\b')){ $c=[int]$m.Groups[1].Value; $p=$m.Groups[2].Value; if($p -eq 'RB'){$rb=$c}elseif($p -eq 'FB'){$fb=$c}else{$te=$c} }
  $backs=$rb+$fb; if($backs -gt 4 -or $te -gt 4){ return $null }
  return "$backs$te"
}
$ROUTES=@{'QUICK OUT'=0;'HITCH/CURL'=1;'GO'=2;'SCREEN'=3;'IN/DIG'=4;'DEEP OUT'=5;'SHALLOW CROSS/DRAG'=6;'SLANT'=7;'POST'=8;'SWING'=9;'CORNER'=10;'WHEEL'=11;'TEXAS/ANGLE'=12}
$FORMM=@{'SHOTGUN'='"S"';'UNDER CENTER'='"U"';'PISTOL'='"P"'}
$PJOIN=@{}
$SNAPCT=@{}   # gsis_id -> offensive snaps (counted from participation offense_players)
if(Test-Path $Part){
  $pfs=New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Part)
  $pfs.SetDelimiters(@(",")); $pfs.HasFieldsEnclosedInQuotes=$true
  $ph=$pfs.ReadFields(); $pix=@{}; for($i=0;$i -lt $ph.Length;$i++){ $pix[$ph[$i]]=$i }
  $P_gid=$pix['nflverse_game_id']; $P_pid=$pix['play_id']; $P_pers=$pix['offense_personnel']
  $P_mz=$pix['defense_man_zone_type']; $P_cov=$pix['defense_coverage_type']; $P_box=$pix['defenders_in_box']
  $P_route=$pix['route']; $P_form=$pix['offense_formation']; $P_off=$pix['offense_players']
  $pc=0
  while(-not $pfs.EndOfData){
    $g=$pfs.ReadFields(); $pc++
    $grp=PersGroup $g[$P_pers]
    $mzv=$g[$P_mz]; $mzc= if($mzv -eq 'MAN_COVERAGE'){'"M"'}elseif($mzv -eq 'ZONE_COVERAGE'){'"Z"'}else{'null'}
    $cvv=[string]$g[$P_cov]; $cvc= if($COVM.ContainsKey($cvv)){'"'+$COVM[$cvv]+'"'}else{'null'}
    $rtv=[string]$g[$P_route]; $rtc= if($ROUTES.ContainsKey($rtv)){$ROUTES[$rtv]}else{'null'}
    $fmv=[string]$g[$P_form]; $fmc= if($FORMM.ContainsKey($fmv)){$FORMM[$fmv]}else{'null'}
    $PJOIN[$g[$P_gid]+'|'+$g[$P_pid]]=','+(Jstr $grp)+','+$mzc+','+$cvc+','+(NumOrNull $g[$P_box])+','+$rtc+','+$fmc
    if($null -ne $P_off){ $op=[string]$g[$P_off]; if($op){ foreach($id in $op.Split(';')){ if($id){ if($SNAPCT.ContainsKey($id)){$SNAPCT[$id]++}else{$SNAPCT[$id]=1} } } } }
  }
  $pfs.Close()
  Write-Host "participation rows: $pc | joined keys: $($PJOIN.Count) | snap ids: $($SNAPCT.Count)"
}
# FTN charting -> drops, keyed game_id|play_id (is_drop = TRUE/FALSE)
$DROPS=@{}
if(Test-Path $Ftn){
  $ffs=New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Ftn)
  $ffs.SetDelimiters(@(",")); $ffs.HasFieldsEnclosedInQuotes=$true
  $fh=$ffs.ReadFields(); $fix=@{}; for($i=0;$i -lt $fh.Length;$i++){ $fix[$fh[$i]]=$i }
  $F_gid=$fix['nflverse_game_id']; $F_pid=$fix['nflverse_play_id']; $F_drop=$fix['is_drop']
  $fc=0; $dc=0
  while(-not $ffs.EndOfData){
    $g=$ffs.ReadFields(); $fc++
    if($g[$F_drop] -eq 'TRUE' -or $g[$F_drop] -eq 'true' -or $g[$F_drop] -eq '1'){ $DROPS[$g[$F_gid]+'|'+$g[$F_pid]]=1; $dc++ }
  }
  $ffs.Close()
  Write-Host "FTN rows: $fc | drops: $dc"
}
# Weekly rosters -> gsis_id => position (for WR/TE tagging of targeted receivers)
# NOTE: hashtable is $RPOS (not $POS) — $pos is the posteam string in the main loop and PS vars are case-insensitive.
$RPOS=@{}
if(Test-Path $Roster){
  $rfs=New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Roster)
  $rfs.SetDelimiters(@(",")); $rfs.HasFieldsEnclosedInQuotes=$true
  $rh=$rfs.ReadFields(); $rix=@{}; for($i=0;$i -lt $rh.Length;$i++){ $rix[$rh[$i]]=$i }
  $R_id=$rix['gsis_id']; $R_pos=$rix['position']
  while(-not $rfs.EndOfData){ $g=$rfs.ReadFields(); $id=$g[$R_id]; if($id){ $RPOS[$id]=$g[$R_pos] } }
  $rfs.Close()
  Write-Host "roster positions: $($RPOS.Count)"
}
$RECPOS=@{}; $RECSNP=@{}; $SEENREC=@{}

$teams=@{}    # team -> @{pass=List;rush=List;qbs=@{};rbs=@{}}
function Team($t){
  if(-not $teams.ContainsKey($t)){
    $teams[$t]=@{ pass=[System.Collections.Generic.List[string]]::new(); rush=[System.Collections.Generic.List[string]]::new(); qbs=@{}; rbs=@{} }
  }
  $teams[$t]
}

$n=0; $np=0; $nr=0
while(-not $tp.EndOfData){
  $f=$tp.ReadFields(); $n++
  if($Limit -gt 0 -and $n -gt $Limit){ break }
  $st=$f[$I_st]; if($st -ne 'REG' -and $st -ne 'POST'){ continue }
  if(IsOne $f[$I_2pt]){ continue }
  $pos=$f[$I_pos]; if($pos -eq '' -or $pos -eq 'NA'){ continue }
  $dn=$f[$I_down]; if($dn -eq '' -or $dn -eq 'NA'){ continue }
  $jk=$f[$I_gid]+'|'+$f[$I_pid]; $pj= if($PJOIN.ContainsKey($jk)){ $PJOIN[$jk] } else { ',null,null,null,null,null,null' }
  $sd=NumOrNull $f[$I_sd]; $ytg=NumOrNull $f[$I_ytg]
  $wk=NumOrNull $f[$I_week]; $def=$f[$I_def]; $yl=NumOrNull $f[$I_yl]
  $epa=NumOrNull $f[$I_epa] 3; $succ= if(IsOne $f[$I_succ]){'1'}else{'0'}; $yg=NumOrNull $f[$I_yg]; $dnv=NumOrNull $dn
  if(IsOne $f[$I_pass]){
    $ay=$f[$I_ay]
    if($ay -eq '' -or $ay -eq 'NA'){ continue }   # thrown ball only (skip sacks/scrambles/no-air)
    $qb=$f[$I_qb]; if($qb -eq '' -or $qb -eq 'NA'){ continue }
    $rec=$f[$I_rec]
    if($rec -and $rec -ne 'NA' -and -not $SEENREC.ContainsKey($rec)){ $SEENREC[$rec]=1; $rid=$f[$I_rid]; if($RPOS.ContainsKey($rid)){ $RECPOS[$rec]=$RPOS[$rid] }; if($SNAPCT.ContainsKey($rid)){ $RECSNP[$rec]=$SNAPCT[$rid] } }
    $loc=MapLoc $f[$I_ploc]
    $td= if(IsOne $f[$I_ptd]){'1'}else{'0'}
    $out= if(IsOne $f[$I_int]){'"N"'}elseif(IsOne $f[$I_cmp]){'"C"'}else{'"I"'}
    $yac=NumOrNull $f[$I_yac]
    $cpoe=NumOrNull $f[$I_cpoe] 1
    $drop= if($DROPS.ContainsKey($jk)){'1'}else{'0'}
    $row='['+$wk+','+(Jstr $def)+','+(Jstr $qb)+','+(Jstr $rec)+','+(NumOrNull $ay)+','+$loc+','+$yl+','+$dnv+','+$yg+','+$yac+','+$epa+','+$succ+','+$out+','+$td+$pj+','+$sd+','+$ytg+','+$cpoe+','+$drop+']'
    $tm=Team $pos; $tm.pass.Add($row); $np++
    if($tm.qbs.ContainsKey($qb)){ $tm.qbs[$qb]++ } else { $tm.qbs[$qb]=1 }
  } elseif(IsOne $f[$I_rush]){
    $run=$f[$I_run]; if($run -eq '' -or $run -eq 'NA'){ continue }
    $gap=MapGap $f[$I_rgap]; $dir=MapLoc $f[$I_rloc]
    $td= if(IsOne $f[$I_rtd]){'1'}else{'0'}; $fum= if(IsOne $f[$I_fum]){'1'}else{'0'}
    $row='['+$wk+','+(Jstr $def)+','+(Jstr $run)+','+$gap+','+$dir+','+$yl+','+$dnv+','+$yg+','+$epa+','+$succ+','+$td+','+$fum+$pj+','+$sd+','+$ytg+']'
    $tm=Team $pos; $tm.rush.Add($row); $nr++
    if($tm.rbs.ContainsKey($run)){ $tm.rbs[$run]++ } else { $tm.rbs[$run]=1 }
  }
}
$tp.Close()
Write-Host ("rows scanned: {0} | pass throws: {1} | rushes: {2} | teams: {3}" -f $n,$np,$nr,$teams.Count)

if($DryRun){
  $sample = ($teams.Keys | Sort-Object | Select-Object -First 1)
  if($sample){ Write-Host "sample team $sample pass[0]: $($teams[$sample].pass[0])"; Write-Host "sample team $sample rush[0]: $($teams[$sample].rush[0])" }
  return
}

$dataDir = Join-Path $OutDir 'data'
$playDir = Join-Path $dataDir 'plays'
New-Item -ItemType Directory -Force -Path $playDir | Out-Null
$allp = [System.Text.StringBuilder]::new(); [void]$allp.Append('window.PLAYS={'); $pfirst=$true
$idx = [System.Text.StringBuilder]::new()
[void]$idx.Append('{"season":'+$Year+',"generated":"'+(Get-Date -Format 'yyyy-MM-dd')+'",')
[void]$idx.Append('"fields":{"pass":["wk","def","qb","rec","ay","loc","yl","dn","yg","yac","epa","succ","out","td","pers","mz","cov","box","route","form","sd","ytg","cpoe","drop"],"rush":["wk","def","run","gap","dir","yl","dn","yg","epa","succ","td","fum","pers","mz","cov","box","route","form","sd","ytg"]},')
[void]$idx.Append('"teams":{')
$first=$true
foreach($t in ($teams.Keys | Sort-Object)){
  $tm=$teams[$t]
  $body='{"pass":['+($tm.pass -join ',')+'],"rush":['+($tm.rush -join ',')+']}'
  [System.IO.File]::WriteAllText((Join-Path $playDir "$t.json"),$body)
  if(-not $pfirst){ [void]$allp.Append(',') }; $pfirst=$false
  [void]$allp.Append('"'+$t+'":'+$body)
  $qbList=($tm.qbs.GetEnumerator()|Sort-Object Value -Descending|ForEach-Object{ (Jstr $_.Key)+':'+$_.Value }) -join ','
  $rbList=($tm.rbs.GetEnumerator()|Sort-Object Value -Descending|ForEach-Object{ (Jstr $_.Key)+':'+$_.Value }) -join ','
  if(-not $first){ [void]$idx.Append(',') }; $first=$false
  [void]$idx.Append('"'+$t+'":{"pass":'+$tm.pass.Count+',"rush":'+$tm.rush.Count+',"qbs":{'+$qbList+'},"rbs":{'+$rbList+'}}')
}
[void]$idx.Append('}}')
[System.IO.File]::WriteAllText((Join-Path $dataDir 'plays_index.json'),$idx.ToString())
[void]$allp.Append('};')
[System.IO.File]::WriteAllText((Join-Path $dataDir 'plays.js'),$allp.ToString())
# positions.js -> window.RECPOS = { "<receiver name>": "<POS>", ... } for WR/TE tagging
$posbuf = [System.Text.StringBuilder]::new(); [void]$posbuf.Append('window.RECPOS={'); $rfirst=$true
foreach($k in ($SEENREC.Keys | Sort-Object)){
  $pv= if($RECPOS.ContainsKey($k)){$RECPOS[$k]}else{'?'}
  $sv= if($RECSNP.ContainsKey($k)){$RECSNP[$k]}else{0}
  if(-not $rfirst){ [void]$posbuf.Append(',') }; $rfirst=$false
  [void]$posbuf.Append((Jstr $k)+':{"p":"'+$pv+'","s":'+$sv+'}')
}
[void]$posbuf.Append('};')
[System.IO.File]::WriteAllText((Join-Path $dataDir 'positions.js'),$posbuf.ToString())
Write-Host ("WROTE {0} team files + plays_index.json + plays.js + positions.js ({1} receivers) to {2}" -f $teams.Count,$SEENREC.Count,$dataDir)
