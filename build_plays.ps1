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
  [string]$Pfr = "C:/Users/miles/AppData/Local/Temp/claude/C--Users-miles--claude/43c60d0d-1058-41de-8b01-6569684d112c/scratchpad/pfrrush.csv",
  [string]$Pdef = "C:/Users/miles/AppData/Local/Temp/claude/C--Users-miles--claude/43c60d0d-1058-41de-8b01-6569684d112c/scratchpad/pfrdef.csv",
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
$I_run=C 'rusher_player_name'; $I_rloc=C 'run_location'; $I_rgap=C 'run_gap'; $I_rrid=C 'rusher_player_id'
$I_rtd=C 'rush_touchdown'; $I_fum=C 'fumble_lost'
# defensive fields (team + player HAVOC family) and final scores for points allowed
$I_ht=C 'home_team'; $I_at=C 'away_team'; $I_hs=C 'home_score'; $I_as=C 'away_score'
$I_sack=C 'sack'; $I_tfl=C 'tackled_for_loss'; $I_ff=C 'fumble_forced'; $I_qbh=C 'qb_hit'
$I_pd1=C 'pass_defense_1_player_id'; $I_pd2=C 'pass_defense_2_player_id'
$I_ff1=C 'forced_fumble_player_1_player_id'; $I_ff2=C 'forced_fumble_player_2_player_id'
$I_tfl1=C 'tackle_for_loss_1_player_id'; $I_tfl2=C 'tackle_for_loss_2_player_id'

function NumOrNull($v,[int]$dec=0){
  if($null -eq $v -or $v -eq '' -or $v -eq 'NA'){ return 'null' }
  $d=[double]$v; if($dec -gt 0){ return ([math]::Round($d,$dec)).ToString([Globalization.CultureInfo]::InvariantCulture) }
  return ([int][math]::Round($d)).ToString()
}
function IsOne($v){ $v -eq '1' -or $v -eq '1.0' }
function Num0($v){ if($null -eq $v -or $v -eq '' -or $v -eq 'NA'){ 0.0 } else { [double]$v } }
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
$DSNAP=@{}    # gsis_id -> defensive snaps (counted from participation defense_players)
if(Test-Path $Part){
  $pfs=New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Part)
  $pfs.SetDelimiters(@(",")); $pfs.HasFieldsEnclosedInQuotes=$true
  $ph=$pfs.ReadFields(); $pix=@{}; for($i=0;$i -lt $ph.Length;$i++){ $pix[$ph[$i]]=$i }
  $P_gid=$pix['nflverse_game_id']; $P_pid=$pix['play_id']; $P_pers=$pix['offense_personnel']
  $P_mz=$pix['defense_man_zone_type']; $P_cov=$pix['defense_coverage_type']; $P_box=$pix['defenders_in_box']
  $P_route=$pix['route']; $P_form=$pix['offense_formation']; $P_off=$pix['offense_players']; $P_defp=$pix['defense_players']
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
    if($null -ne $P_defp){ $dp=[string]$g[$P_defp]; if($dp){ foreach($id in $dp.Split(';')){ if($id){ if($DSNAP.ContainsKey($id)){$DSNAP[$id]++}else{$DSNAP[$id]=1} } } } }
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
# Weekly rosters -> gsis_id => position + gsis_id => pfr_id crosswalk
# NOTE: hashtable is $RPOS (not $POS) — $pos is the posteam string in the main loop and PS vars are case-insensitive.
$RPOS=@{}; $G2PFR=@{}
if(Test-Path $Roster){
  $rfs=New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Roster)
  $rfs.SetDelimiters(@(",")); $rfs.HasFieldsEnclosedInQuotes=$true
  $rh=$rfs.ReadFields(); $rix=@{}; for($i=0;$i -lt $rh.Length;$i++){ $rix[$rh[$i]]=$i }
  $R_id=$rix['gsis_id']; $R_pos=$rix['position']; $R_pfr=$rix['pfr_id']
  while(-not $rfs.EndOfData){ $g=$rfs.ReadFields(); $id=$g[$R_id]; if($id){ $RPOS[$id]=$g[$R_pos]; if($null -ne $R_pfr){ $pf=$g[$R_pfr]; if($pf){ $G2PFR[$id]=$pf } } } }
  $rfs.Close()
  Write-Host "roster positions: $($RPOS.Count) | gsis->pfr: $($G2PFR.Count)"
}
# PFR advanced rushing (weekly) -> pfr_id => season totals {carries, yds before/after contact, broken tackles}
$PFRADV=@{}
if(Test-Path $Pfr){
  $afs=New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Pfr)
  $afs.SetDelimiters(@(",")); $afs.HasFieldsEnclosedInQuotes=$true
  $ah=$afs.ReadFields(); $aix=@{}; for($i=0;$i -lt $ah.Length;$i++){ $aix[$ah[$i]]=$i }
  $A_id=$aix['pfr_player_id']; $A_car=$aix['carries']; $A_ybc=$aix['rushing_yards_before_contact']; $A_yac=$aix['rushing_yards_after_contact']; $A_brk=$aix['rushing_broken_tackles']
  while(-not $afs.EndOfData){ $g=$afs.ReadFields(); $apid=$g[$A_id]; if(-not $apid){ continue }
    if(-not $PFRADV.ContainsKey($apid)){ $PFRADV[$apid]=@{car=0.0;ybc=0.0;yac=0.0;mtf=0.0} }
    $a=$PFRADV[$apid]; $a.car+=(Num0 $g[$A_car]); $a.ybc+=(Num0 $g[$A_ybc]); $a.yac+=(Num0 $g[$A_yac]); $a.mtf+=(Num0 $g[$A_brk]) }
  $afs.Close(); Write-Host "PFR rush players: $($PFRADV.Count)"
}
# PFR advanced defense (weekly) -> pfr_id => season totals (coverage + pass rush + tackling)
# NOTE: hashtable must be $DPLAY, NOT $PDEF — $Pdef is the input-path param and PS vars are case-insensitive.
$DPLAY=@{}
if(Test-Path $Pdef){
  $dfs=New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Pdef)
  $dfs.SetDelimiters(@(",")); $dfs.HasFieldsEnclosedInQuotes=$true
  $dh=$dfs.ReadFields(); $dix=@{}; for($i=0;$i -lt $dh.Length;$i++){ $dix[$dh[$i]]=$i }
  $D_tm=$dix['team']; $D_nm=$dix['pfr_player_name']; $D_id=$dix['pfr_player_id']
  $D_int=$dix['def_ints']; $D_tgt=$dix['def_targets']; $D_cmp=$dix['def_completions_allowed']; $D_yds=$dix['def_yards_allowed']
  $D_td=$dix['def_receiving_td_allowed']; $D_hur=$dix['def_times_hurried']; $D_qbh=$dix['def_times_hitqb']
  $D_sk=$dix['def_sacks']; $D_prs=$dix['def_pressures']; $D_tkl=$dix['def_tackles_combined']; $D_miss=$dix['def_missed_tackles']
  while(-not $dfs.EndOfData){ $g=$dfs.ReadFields(); $dpid=$g[$D_id]; if(-not $dpid){ continue }
    if(-not $DPLAY.ContainsKey($dpid)){ $DPLAY[$dpid]=@{name=$g[$D_nm];team=$g[$D_tm];g=0;intc=0.0;tgt=0.0;cmp=0.0;yds=0.0;td=0.0;hur=0.0;qbh=0.0;sk=0.0;prs=0.0;tkl=0.0;miss=0.0} }
    $p=$DPLAY[$dpid]; $p.g++; $p.team=$g[$D_tm]
    $p.intc+=(Num0 $g[$D_int]); $p.tgt+=(Num0 $g[$D_tgt]); $p.cmp+=(Num0 $g[$D_cmp]); $p.yds+=(Num0 $g[$D_yds]); $p.td+=(Num0 $g[$D_td])
    $p.hur+=(Num0 $g[$D_hur]); $p.qbh+=(Num0 $g[$D_qbh]); $p.sk+=(Num0 $g[$D_sk]); $p.prs+=(Num0 $g[$D_prs]); $p.tkl+=(Num0 $g[$D_tkl]); $p.miss+=(Num0 $g[$D_miss]) }
  $dfs.Close(); Write-Host "PFR def players: $($DPLAY.Count)"
}
# reverse crosswalk pfr_id -> gsis_id (to attach pbp PD/FF/TFL + defensive snaps + position to PFR-keyed players)
$P2GSIS=@{}; foreach($k in $G2PFR.Keys){ $P2GSIS[$G2PFR[$k]]=$k }
# NFL passer rating allowed from season aggregates (coverage proxy; lower is better)
function PasserRating($att,$cmp,$yds,$td,$intc){
  if($att -le 0){ return $null }
  $a=[math]::Max(0.0,[math]::Min(2.375, (($cmp/$att)-0.3)*5))
  $b=[math]::Max(0.0,[math]::Min(2.375, (($yds/$att)-3)*0.25))
  $c=[math]::Max(0.0,[math]::Min(2.375, ($td/$att)*20))
  $e=[math]::Max(0.0,[math]::Min(2.375, 2.375-(($intc/$att)*25)))
  return [math]::Round((($a+$b+$c+$e)/6)*100,1)
}
function DGroup($p){ switch -Regex ($p){ '^(DE|DT|NT|DL)$' {return 'DL'} '^(LB|ILB|OLB|MLB|EDGE)$' {return 'LB'} '^(CB|S|FS|SS|DB)$' {return 'DB'} default {return '?'} } }
# team defense + per-player pbp havoc accumulators (filled during the main pbp scan)
$DEFT=@{}   # defteam -> @{plays;epa;succ;expl;sack;tfl;intc;pd;ff;qbh}
$PBPD=@{}   # gsis_id -> @{pd;ff;tfl}  (passes defended, forced fumbles, run stuffs — not in PFR)
$GAMES=@{}  # game_id -> @{ht;at;h;a}  final scores, for points allowed
function AddPBPD($id,$k){ if($id -and $id -ne 'NA'){ if(-not $PBPD.ContainsKey($id)){ $PBPD[$id]=@{pd=0;ff=0;tfl=0} }; $PBPD[$id][$k]++ } }
$RECPOS=@{}; $RECSNP=@{}; $SEENREC=@{}; $RBDAT=@{}

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
  # ---- defense accumulation (team HAVOC family + player pbp events), on every scrimmage snap incl. sacks ----
  $isP=IsOne $f[$I_pass]; $isR=IsOne $f[$I_rush]
  if(($isP -or $isR) -and $def -and $def -ne 'NA'){
    if(-not $DEFT.ContainsKey($def)){ $DEFT[$def]=@{plays=0;epa=0.0;succ=0;expl=0;sack=0;tfl=0;intc=0;pd=0;ff=0;qbh=0} }
    $dt=$DEFT[$def]; $dt.plays++; $dt.epa+=(Num0 $f[$I_epa]); if(IsOne $f[$I_succ]){ $dt.succ++ }
    $ygn=(Num0 $f[$I_yg]); if(($isP -and $ygn -ge 20) -or ($isR -and $ygn -ge 10)){ $dt.expl++ }
    $sk=IsOne $f[$I_sack]; if($sk){ $dt.sack++ }
    $tf=(IsOne $f[$I_tfl]) -and (-not $sk); if($tf){ $dt.tfl++ }
    if(IsOne $f[$I_int]){ $dt.intc++ }
    if(IsOne $f[$I_ff]){ $dt.ff++ }
    if(IsOne $f[$I_qbh]){ $dt.qbh++ }
    if($f[$I_pd1] -and $f[$I_pd1] -ne 'NA'){ $dt.pd++; AddPBPD $f[$I_pd1] 'pd' }
    if($f[$I_pd2] -and $f[$I_pd2] -ne 'NA'){ $dt.pd++; AddPBPD $f[$I_pd2] 'pd' }
    if($f[$I_ff1] -and $f[$I_ff1] -ne 'NA'){ AddPBPD $f[$I_ff1] 'ff' }
    if($f[$I_ff2] -and $f[$I_ff2] -ne 'NA'){ AddPBPD $f[$I_ff2] 'ff' }
    if($tf){ if($f[$I_tfl1] -and $f[$I_tfl1] -ne 'NA'){ AddPBPD $f[$I_tfl1] 'tfl' }; if($f[$I_tfl2] -and $f[$I_tfl2] -ne 'NA'){ AddPBPD $f[$I_tfl2] 'tfl' } }
    $gid=$f[$I_gid]; if(-not $GAMES.ContainsKey($gid)){ $GAMES[$gid]=@{ht=$f[$I_ht];at=$f[$I_at];h=(Num0 $f[$I_hs]);a=(Num0 $f[$I_as])} }
  }
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
    if(-not $RBDAT.ContainsKey($run)){
      $rrid=$f[$I_rrid]
      $rp= if($RPOS.ContainsKey($rrid)){$RPOS[$rrid]}else{'?'}
      $rs= if($SNAPCT.ContainsKey($rrid)){$SNAPCT[$rrid]}else{0}
      $pf= if($G2PFR.ContainsKey($rrid)){$G2PFR[$rrid]}else{''}
      $rcar=0.0;$rybc=0.0;$ryac=0.0;$rmtf=0.0
      if($pf -and $PFRADV.ContainsKey($pf)){ $adv=$PFRADV[$pf]; $rcar=$adv.car; $rybc=$adv.ybc; $ryac=$adv.yac; $rmtf=$adv.mtf }
      $RBDAT[$run]=@{pos=$rp;s=$rs;car=$rcar;ybc=$rybc;yac=$ryac;mtf=$rmtf}
    }
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
# rbadv.js -> window.RBADV = { "<rusher name>": {"pos":"RB","s":<snaps>,"car":<pfr carries>,"ybc":<yds before contact>,"yac":<yds after contact>,"mtf":<broken tackles>}, ... }
$rbbuf = [System.Text.StringBuilder]::new(); [void]$rbbuf.Append('window.RBADV={'); $rbfirst=$true
foreach($k in ($RBDAT.Keys | Sort-Object)){
  $d=$RBDAT[$k]
  if(-not $rbfirst){ [void]$rbbuf.Append(',') }; $rbfirst=$false
  [void]$rbbuf.Append((Jstr $k)+':{"pos":"'+$d.pos+'","s":'+$d.s+',"car":'+([int]$d.car)+',"ybc":'+([math]::Round($d.ybc,1))+',"yac":'+([math]::Round($d.yac,1))+',"mtf":'+([int]$d.mtf)+'}')
}
[void]$rbbuf.Append('};')
[System.IO.File]::WriteAllText((Join-Path $dataDir 'rbadv.js'),$rbbuf.ToString())
# points allowed per team (home team allows away final score, and vice-versa)
$PA=@{}
foreach($gid in $GAMES.Keys){ $gm=$GAMES[$gid]
  if($gm.ht){ if($PA.ContainsKey($gm.ht)){$PA[$gm.ht]+=$gm.a}else{$PA[$gm.ht]=$gm.a} }
  if($gm.at){ if($PA.ContainsKey($gm.at)){$PA[$gm.at]+=$gm.h}else{$PA[$gm.at]=$gm.h} } }
# defense.js -> window.DEFTEAM = { "<TEAM>": {plays,epa,succ,expl,sack,tfl,intc,pd,ff,qbh,havoc,havocR,pa}, ... }
$dbuf=[System.Text.StringBuilder]::new(); [void]$dbuf.Append('window.DEFTEAM={'); $dfirst=$true
foreach($t in ($DEFT.Keys | Sort-Object)){
  $dv=$DEFT[$t]; $pl=$dv.plays; if($pl -le 0){ continue }
  $hav=$dv.tfl+$dv.sack+$dv.intc+$dv.pd+$dv.ff
  $paT= if($PA.ContainsKey($t)){[int]$PA[$t]}else{0}
  if(-not $dfirst){ [void]$dbuf.Append(',') }; $dfirst=$false
  [void]$dbuf.Append('"'+$t+'":{"plays":'+$pl+',"epa":'+([math]::Round($dv.epa/$pl,3))+',"succ":'+([math]::Round(100*$dv.succ/$pl,1))+',"expl":'+([math]::Round(100*$dv.expl/$pl,1))+',"sack":'+$dv.sack+',"tfl":'+$dv.tfl+',"intc":'+$dv.intc+',"pd":'+$dv.pd+',"ff":'+$dv.ff+',"qbh":'+$dv.qbh+',"havoc":'+$hav+',"havocR":'+([math]::Round(100*$hav/$pl,1))+',"pa":'+$paT+'}')
}
[void]$dbuf.Append('};')
[System.IO.File]::WriteAllText((Join-Path $dataDir 'defense.js'),$dbuf.ToString())
# defplayers.js -> window.DEFPLAYERS = [ {name,tm,pos,grp,g,snaps,sack,prs,hur,qbh,intc,pd,ff,tfl,tkl,miss,missPct,tgt,cmp,cmpPct,yds,ypt,tdA,rtg,havoc,havocR}, ... ]
$pbuf=[System.Text.StringBuilder]::new(); [void]$pbuf.Append('window.DEFPLAYERS=['); $pfirst2=$true; $pcnt=0
foreach($pfrid in $DPLAY.Keys){
  $pv=$DPLAY[$pfrid]
  $gs= if($P2GSIS.ContainsKey($pfrid)){$P2GSIS[$pfrid]}else{''}
  $pos= if($gs -and $RPOS.ContainsKey($gs)){$RPOS[$gs]}else{'?'}
  $grp=DGroup $pos
  $snaps= if($gs -and $DSNAP.ContainsKey($gs)){$DSNAP[$gs]}else{0}
  $ppd=0;$pff=0;$ptfl=0; if($gs -and $PBPD.ContainsKey($gs)){ $pb=$PBPD[$gs]; $ppd=$pb.pd; $pff=$pb.ff; $ptfl=$pb.tfl }
  $tgt=$pv.tgt; $cmp=$pv.cmp; $yds=$pv.yds
  $cmpPctS= if($tgt -gt 0){[math]::Round(100*$cmp/$tgt,1)}else{'null'}
  $yptS= if($tgt -gt 0){[math]::Round($yds/$tgt,1)}else{'null'}
  $rtg=PasserRating $tgt $cmp $yds $pv.td $pv.intc; $rtgS= if($null -eq $rtg){'null'}else{$rtg}
  $tot=$pv.tkl+$pv.miss; $missPctS= if($tot -gt 0){[math]::Round(100*$pv.miss/$tot,1)}else{'null'}
  $phav=[math]::Round($pv.sk+$ptfl+$ppd+$pff+$pv.intc,1)
  $havRS= if($snaps -gt 0){[math]::Round(100*$phav/$snaps,2)}else{'null'}
  if(-not $pfirst2){ [void]$pbuf.Append(',') }; $pfirst2=$false; $pcnt++
  [void]$pbuf.Append('{"name":'+(Jstr $pv.name)+',"tm":'+(Jstr $pv.team)+',"pos":'+(Jstr $pos)+',"grp":"'+$grp+'","g":'+$pv.g+',"snaps":'+$snaps+',"sack":'+([math]::Round($pv.sk,1))+',"prs":'+([int]$pv.prs)+',"hur":'+([int]$pv.hur)+',"qbh":'+([int]$pv.qbh)+',"intc":'+([int]$pv.intc)+',"pd":'+$ppd+',"ff":'+$pff+',"tfl":'+$ptfl+',"tkl":'+([int]$pv.tkl)+',"miss":'+([int]$pv.miss)+',"missPct":'+$missPctS+',"tgt":'+([int]$tgt)+',"cmp":'+([int]$cmp)+',"cmpPct":'+$cmpPctS+',"yds":'+([int]$yds)+',"ypt":'+$yptS+',"tdA":'+([int]$pv.td)+',"rtg":'+$rtgS+',"havoc":'+$phav+',"havocR":'+$havRS+'}')
}
[void]$pbuf.Append('];')
[System.IO.File]::WriteAllText((Join-Path $dataDir 'defplayers.js'),$pbuf.ToString())
Write-Host ("WROTE {0} team files + plays_index.json + plays.js + positions.js ({1} rec) + rbadv.js ({2} rushers) + defense.js ({3} tms) + defplayers.js ({4}) to {5}" -f $teams.Count,$SEENREC.Count,$RBDAT.Count,$DEFT.Count,$pcnt,$dataDir)
