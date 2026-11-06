<#
build_ratings.ps1 - recompute the Team Ratings tab (DATA.ratings) for a season
from the full nflverse play-by-play + final scores, and emit it as a PARTIAL
DATA bundle: data/<Year>/data.js = regData(<Year>,"DATA",{ratings:{...}}).

The year engine (setYear) merges a partial DATA over the baseline season, so only
ratings is overridden for <Year>; every other DATA key (coverage, fieldZones,
leagueEPA, saints, draft, ...) stays the baseline until separately rebuilt.

Phase score (0-100): league percentile of each team across the phase's metrics,
averaged. This is a transparent, reproducible composite over the SAME metric set
and benchmarks the baseline uses (the baseline's original curated 0-100 formula
was never saved as a builder). Ordering matches the baseline closely.

Metrics (value `v` vs fixed benchmark `bm`, `met` = beats bm):
 Offense: Points/G, Yards/G, 3rd-Down %, Turnovers Lost/G, Sack % Allowed,
          Red Zone TD %, Time of Poss, Explosive Play %
 Defense: Points Allowed/G, Yards Allowed/G, 3rd-Down % Allowed,
          Turnovers Forced/G, Sacks/G, Opp Time of Poss, Explosive % Allowed
 ST:      FG %, Punt Avg, Punts Inside 20, Kick Return Avg, Return TDs
#>
param(
  [string]$Gz     = "",            # play_by_play_<Year>.csv or .csv.gz (required)
  [string]$OutDir = "C:/Users/miles/saints-dashboard",
  [int]   $Year   = 2026
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName Microsoft.VisualBasic
if(-not $Gz -or -not (Test-Path $Gz)){ throw "pass -Gz <play_by_play csv/.gz> (got '$Gz')" }

# fixed benchmarks + orientation (hiBetter). bm=$null => shown but not benchmarked.
$OFF_METS = @('Points/G','Yards/G','3rd-Down %','Turnovers Lost/G','Sack % Allowed','Red Zone TD %','Time of Poss','Explosive Play %')
$DEF_METS = @('Points Allowed/G','Yards Allowed/G','3rd-Down % Allowed','Turnovers Forced/G','Sacks/G','Opp Time of Poss','Explosive % Allowed')
$ST_METS  = @('FG %','Punt Avg','Punts Inside 20','Kick Return Avg','Return TDs')
# $BENCH not $BM: a local $bm in the assemble loop would alias $BM (case-insensitive vars).
$BENCH = @{
  'Points/G'=26.0; 'Yards/G'=365.0; '3rd-Down %'=45.0; 'Turnovers Lost/G'=1.1; 'Sack % Allowed'=1.7; 'Red Zone TD %'=64.0; 'Time of Poss'=31.0; 'Explosive Play %'=$null;
  'Points Allowed/G'=20.0; 'Yards Allowed/G'=310.0; '3rd-Down % Allowed'=38.0; 'Turnovers Forced/G'=1.6; 'Sacks/G'=2.8; 'Opp Time of Poss'=28.5; 'Explosive % Allowed'=$null;
  'FG %'=93.8; 'Punt Avg'=50.0; 'Punts Inside 20'=34.0; 'Kick Return Avg'=26.9; 'Return TDs'=1.0
}
# hiBetter = higher value is better
$HI = @{
  'Points/G'=$true;'Yards/G'=$true;'3rd-Down %'=$true;'Turnovers Lost/G'=$false;'Sack % Allowed'=$false;'Red Zone TD %'=$true;'Time of Poss'=$true;'Explosive Play %'=$true;
  'Points Allowed/G'=$false;'Yards Allowed/G'=$false;'3rd-Down % Allowed'=$false;'Turnovers Forced/G'=$true;'Sacks/G'=$true;'Opp Time of Poss'=$false;'Explosive % Allowed'=$false;
  'FG %'=$true;'Punt Avg'=$true;'Punts Inside 20'=$true;'Kick Return Avg'=$true;'Return TDs'=$true
}
# counting stats (season totals, not per-game) - shown as integers
$COUNT = @{'Punts Inside 20'=$true;'Return TDs'=$true}

$FULLNAME = @{
 ARI='Arizona Cardinals';ATL='Atlanta Falcons';BAL='Baltimore Ravens';BUF='Buffalo Bills';CAR='Carolina Panthers';CHI='Chicago Bears';CIN='Cincinnati Bengals';CLE='Cleveland Browns';DAL='Dallas Cowboys';DEN='Denver Broncos';DET='Detroit Lions';GB='Green Bay Packers';HOU='Houston Texans';IND='Indianapolis Colts';JAX='Jacksonville Jaguars';KC='Kansas City Chiefs';LA='Los Angeles Rams';LAC='Los Angeles Chargers';LV='Las Vegas Raiders';MIA='Miami Dolphins';MIN='Minnesota Vikings';NE='New England Patriots';NO='New Orleans Saints';NYG='New York Giants';NYJ='New York Jets';PHI='Philadelphia Eagles';PIT='Pittsburgh Steelers';SEA='Seattle Seahawks';SF='San Francisco 49ers';TB='Tampa Bay Buccaneers';TEN='Tennessee Titans';WAS='Washington Commanders'
}

function Pd($x){ if($null -eq $x){return $null}; $t=([string]$x).Trim(); if($t -eq '' -or $t -eq 'NA'){return $null}; $d=0.0; if([double]::TryParse($t,[ref]$d)){return $d}; return $null }
function Mins($x){ if($null -eq $x){return $null}; $t=([string]$x).Trim(); if($t -eq '' -or $t -eq 'NA'){return $null}; if($t -match '^(\d+):(\d+)$'){ return [int]$matches[1]*60+[int]$matches[2] }; $d=Pd $t; if($null -ne $d){return $d}; return $null }

# ---- decompress if needed ----
$isGz = $Gz.ToLower().EndsWith('.gz')
if($isGz){ $fsI=[System.IO.File]::OpenRead($Gz); $gzs=New-Object System.IO.Compression.GZipStream($fsI,[System.IO.Compression.CompressionMode]::Decompress); $tmp=[System.IO.Path]::GetTempFileName(); $outF=[System.IO.File]::Create($tmp); $gzs.CopyTo($outF); $outF.Close(); $gzs.Close(); $fsI.Close(); $pbpPath=$tmp } else { $pbpPath=$Gz }

$pf=New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($pbpPath)
$pf.SetDelimiters(@(",")); $pf.HasFieldsEnclosedInQuotes=$true
$h=$pf.ReadFields(); $ix=@{}; for($i=0;$i -lt $h.Length;$i++){ $ix[$h[$i]]=$i }
function Col($row,$name){ $j=$ix[$name]; if($null -eq $j){return $null}; return $row[$j] }

# accumulators
$TEAMS = @{}            # abbr -> ordered agg hashtable
function Ensure($ab){ if(-not $TEAMS.ContainsKey($ab)){ $TEAMS[$ab]=@{ oyd=0.0;opl=0;oexp=0;o3c=0;o3a=0;osack=0;odb=0;otol=0; dyd=0.0;d3c=0;d3a=0;dsack=0;dtof=0;dexp=0;dpl=0; fgm=0;fga=0;puntYds=0.0;puntN=0;in20=0;krYds=0.0;krN=0;retTD=0 } } ; return $TEAMS[$ab] }
$GAMESCORE = @{}        # game_id -> @{home;away;hs;as_}
$DRIVE_TOP = @{}        # game_id|drive -> @{team;sec}
$DRIVE_RZ  = @{}        # game_id|drive -> @{team;rz;td}

while(-not $pf.EndOfData){
  $r=$pf.ReadFields()
  if((Col $r 'season_type') -ne 'REG'){ continue }
  $gid=Col $r 'game_id'
  if(-not $GAMESCORE.ContainsKey($gid)){ $GAMESCORE[$gid]=@{home=(Col $r 'home_team');away=(Col $r 'away_team');hs=$null;as_=$null} }
  # scores accumulate during the game; take the max seen (= final) rather than the first row (empty).
  $hsv=Pd (Col $r 'home_score'); if($null -ne $hsv -and ($null -eq $GAMESCORE[$gid].hs -or $hsv -gt $GAMESCORE[$gid].hs)){ $GAMESCORE[$gid].hs=$hsv }
  $asv=Pd (Col $r 'away_score'); if($null -ne $asv -and ($null -eq $GAMESCORE[$gid].as_ -or $asv -gt $GAMESCORE[$gid].as_)){ $GAMESCORE[$gid].as_=$asv }
  $pos=Col $r 'posteam'; $def=Col $r 'defteam'
  $pt=Col $r 'play_type'
  $isPass = ((Pd (Col $r 'pass')) -eq 1)
  $isRush = ((Pd (Col $r 'rush')) -eq 1)
  $yg = Pd (Col $r 'yards_gained'); if($null -eq $yg){$yg=0}
  $dn = Pd (Col $r 'down')

  # --- drive-level: TOP + red zone ---
  $drv = Col $r 'fixed_drive'; if(-not $drv){ $drv = Col $r 'drive' }
  if($pos -and $drv){
    $dk="$gid|$drv"
    $sec = Mins (Col $r 'drive_time_of_possession')
    if(-not $DRIVE_TOP.ContainsKey($dk)){ $DRIVE_TOP[$dk]=@{team=$pos;sec=$null} }
    if($null -ne $sec -and $null -eq $DRIVE_TOP[$dk].sec){ $DRIVE_TOP[$dk].sec=$sec }
    if(-not $DRIVE_RZ.ContainsKey($dk)){ $DRIVE_RZ[$dk]=@{team=$pos;rz=$false;td=$false} }
    $yl = Pd (Col $r 'yardline_100')
    if($null -ne $yl -and $yl -le 20){ $DRIVE_RZ[$dk].rz=$true }
    if(((Pd (Col $r 'pass_touchdown')) -eq 1) -or ((Pd (Col $r 'rush_touchdown')) -eq 1)){ $DRIVE_RZ[$dk].td=$true }
  }

  # --- offense (posteam) ---
  if($pos){
    $o=Ensure $pos
    if($isPass -or $isRush){
      $o.oyd += $yg; $o.opl++
      if(($isPass -and $yg -ge 20) -or ($isRush -and $yg -ge 10)){ $o.oexp++ }
    }
    if($dn -eq 3){ if((Pd (Col $r 'third_down_converted')) -eq 1){$o.o3a++;$o.o3c++} elseif((Pd (Col $r 'third_down_failed')) -eq 1){$o.o3a++} }
    if((Pd (Col $r 'qb_dropback')) -eq 1){ $o.odb++ }
    if((Pd (Col $r 'sack')) -eq 1){ $o.osack++ }
    if((Pd (Col $r 'interception')) -eq 1){ $o.otol++ }
    if((Pd (Col $r 'fumble_lost')) -eq 1){ $o.otol++ }
  }
  # --- defense (defteam) sees opponent's offensive play ---
  if($def){
    $d=Ensure $def
    if($isPass -or $isRush){ $d.dyd += $yg; $d.dpl++; if(($isPass -and $yg -ge 20) -or ($isRush -and $yg -ge 10)){ $d.dexp++ } }
    if($dn -eq 3){ if((Pd (Col $r 'third_down_converted')) -eq 1){$d.d3a++;$d.d3c++} elseif((Pd (Col $r 'third_down_failed')) -eq 1){$d.d3a++} }
    if((Pd (Col $r 'sack')) -eq 1){ $d.dsack++ }
    if((Pd (Col $r 'interception')) -eq 1){ $d.dtof++ }
    if((Pd (Col $r 'fumble_lost')) -eq 1){ $d.dtof++ }
  }
  # --- special teams ---
  if((Pd (Col $r 'field_goal_attempt')) -eq 1 -and $pos){ $o2=Ensure $pos; $o2.fga++; if((Col $r 'field_goal_result') -eq 'made'){$o2.fgm++} }
  if((Pd (Col $r 'punt_attempt')) -eq 1 -and $pos){ $o3=Ensure $pos; $kd=Pd (Col $r 'kick_distance'); if($null -ne $kd){$o3.puntYds+=$kd;$o3.puntN++}; if((Pd (Col $r 'punt_inside_twenty')) -eq 1){$o3.in20++} }
  if($pt -eq 'kickoff' -and $def){ $rt=Ensure $def; $ry=Pd (Col $r 'return_yards'); if($null -ne $ry -and $ry -gt 0){$rt.krYds+=$ry;$rt.krN++} }
  if((Pd (Col $r 'return_touchdown')) -eq 1 -and $def){ $rt2=Ensure $def; $rt2.retTD++ }
}
$pf.Close(); if($isGz){ Remove-Item $pbpPath -ErrorAction SilentlyContinue }

# ---- games played + points for/against from final scores ----
# NOTE: PowerShell variable names are case-insensitive, so these hashtables must NOT share a
# name with any local scalar ($GP vs $gp, $PF vs the $pf parser) - hence $GMS/$PTSF/$PTSA.
$GMS=@{}; $PTSF=@{}; $PTSA=@{}
foreach($gid in $GAMESCORE.Keys){
  $g=$GAMESCORE[$gid]; if($null -eq $g.hs -or $null -eq $g.as_){ continue }
  # handle home + away explicitly (nested @() arrays flatten in PowerShell, so no pair-loop)
  if($g.home){ $GMS[$g.home]=([int]$GMS[$g.home])+1; $PTSF[$g.home]=([double]$PTSF[$g.home])+$g.hs;  $PTSA[$g.home]=([double]$PTSA[$g.home])+$g.as_ }
  if($g.away){ $GMS[$g.away]=([int]$GMS[$g.away])+1; $PTSF[$g.away]=([double]$PTSF[$g.away])+$g.as_; $PTSA[$g.away]=([double]$PTSA[$g.away])+$g.hs  }
}
# ---- TOP seconds per team (own) and per game, to derive opp TOP ----
$TOPown=@{}; $TOPbyGame=@{}   # TOPbyGame[gid][team]=sec
foreach($dk in $DRIVE_TOP.Keys){
  $e=$DRIVE_TOP[$dk]; if($null -eq $e.sec){continue}
  $gid=$dk.Split('|')[0]; $tm=$e.team
  $TOPown[$tm]=([double]$TOPown[$tm])+$e.sec
  if(-not $TOPbyGame.ContainsKey($gid)){$TOPbyGame[$gid]=@{}}
  $TOPbyGame[$gid][$tm]=([double]$TOPbyGame[$gid][$tm])+$e.sec
}
$TOPopp=@{}
foreach($gid in $TOPbyGame.Keys){
  $g=$GAMESCORE[$gid]; if($null -eq $g){continue}
  $hm=$g.home; $aw=$g.away
  if($hm){ $TOPopp[$hm]=([double]$TOPopp[$hm])+([double]$TOPbyGame[$gid][$aw]) }
  if($aw){ $TOPopp[$aw]=([double]$TOPopp[$aw])+([double]$TOPbyGame[$gid][$hm]) }
}
# ---- red zone trips/TD per team ----
$RZtrip=@{}; $RZtd=@{}
foreach($dk in $DRIVE_RZ.Keys){ $e=$DRIVE_RZ[$dk]; if(-not $e.rz){continue}; $tm=$e.team; $RZtrip[$tm]=([int]$RZtrip[$tm])+1; if($e.td){$RZtd[$tm]=([int]$RZtd[$tm])+1} }

# ---- build metric values per team ----
function Rnd($v,$n){ if($null -eq $v){return $null}; return [math]::Round([double]$v,$n) }
$VAL=@{}  # team -> metric -> value
# iterate a snapshot of teams-that-played ($ng = this team's games; NOT $GMS)
$PLAYED = @($GMS.Keys | Sort-Object)
foreach($ab in $PLAYED){
  $o=$TEAMS[$ab]; if($null -eq $o){ continue }
  $ng=[int]$GMS[$ab]; if($ng -lt 1){ continue }
  $v=@{}
  $v['Points/G']            = Rnd ($PTSF[$ab]/$ng) 1
  $v['Yards/G']             = Rnd ($o.oyd/$ng) 1
  $v['3rd-Down %']          = if($o.o3a){ Rnd (100.0*$o.o3c/$o.o3a) 1 } else { $null }
  $v['Turnovers Lost/G']    = Rnd ($o.otol/$ng) 1
  $v['Sack % Allowed']      = if($o.odb){ Rnd (100.0*$o.osack/$o.odb) 1 } else { $null }
  $v['Red Zone TD %']       = if([int]$RZtrip[$ab]){ Rnd (100.0*([int]$RZtd[$ab])/([int]$RZtrip[$ab])) 1 } else { $null }
  $v['Time of Poss']        = if($TOPown.ContainsKey($ab)){ Rnd (($TOPown[$ab]/$ng)/60.0) 1 } else { $null }
  $v['Explosive Play %']    = if($o.opl){ Rnd (100.0*$o.oexp/$o.opl) 1 } else { $null }
  $v['Points Allowed/G']    = Rnd ($PTSA[$ab]/$ng) 1
  $v['Yards Allowed/G']     = Rnd ($o.dyd/$ng) 1
  $v['3rd-Down % Allowed']  = if($o.d3a){ Rnd (100.0*$o.d3c/$o.d3a) 1 } else { $null }
  $v['Turnovers Forced/G']  = Rnd ($o.dtof/$ng) 1
  $v['Sacks/G']             = Rnd ($o.dsack/$ng) 1
  $v['Opp Time of Poss']    = if($TOPopp.ContainsKey($ab)){ Rnd (($TOPopp[$ab]/$ng)/60.0) 1 } else { $null }
  $v['Explosive % Allowed'] = if($o.dpl){ Rnd (100.0*$o.dexp/$o.dpl) 1 } else { $null }
  $v['FG %']                = if($o.fga){ Rnd (100.0*$o.fgm/$o.fga) 1 } else { $null }
  $v['Punt Avg']            = if($o.puntN){ Rnd ($o.puntYds/$o.puntN) 1 } else { $null }
  $v['Punts Inside 20']     = [int]$o.in20
  $v['Kick Return Avg']     = if($o.krN){ Rnd ($o.krYds/$o.krN) 1 } else { $null }
  $v['Return TDs']          = [int]$o.retTD
  $VAL[$ab]=$v
}
$ABS = @($VAL.Keys | Sort-Object)
Write-Host ("teams with games: {0}" -f $ABS.Count)

# ---- percentile 0-100 per metric, then phase score = mean of metric percentiles ----
function Percentile($arr,$mv,$hi){
  $nums=@($arr | Where-Object { $null -ne $_ })
  if($nums.Count -le 1){ return 50.0 }
  $worse=0; foreach($x in $nums){ if($hi){ if($x -lt $mv){$worse++} } else { if($x -gt $mv){$worse++} } }
  return 100.0*$worse/($nums.Count-1)
}
function PhaseScore($ab,$mets){
  $sum=0.0;$n=0
  foreach($m in $mets){ $mv=$VAL[$ab][$m]; if($null -eq $mv){continue}
    $col=@($ABS | ForEach-Object { $VAL[$_][$m] })
    $sum += Percentile $col $mv $HI[$m]; $n++ }
  if($n -eq 0){ return 0.0 }
  return [math]::Round($sum/$n,1)
}

# ---- assemble ratings object ----
$teamObjs=@()
foreach($ab in $ABS){
  $offM=[ordered]@{}; foreach($m in $OFF_METS){ $mv=$VAL[$ab][$m]; $bm=$BENCH[$m]; $met=$null; if($null -ne $mv -and $null -ne $bm){ $met = if($HI[$m]){ $mv -ge $bm } else { $mv -le $bm } }; $offM[$m]=[ordered]@{v=$mv;bm=$bm;met=$met} }
  $defM=[ordered]@{}; foreach($m in $DEF_METS){ $mv=$VAL[$ab][$m]; $bm=$BENCH[$m]; $met=$null; if($null -ne $mv -and $null -ne $bm){ $met = if($HI[$m]){ $mv -ge $bm } else { $mv -le $bm } }; $defM[$m]=[ordered]@{v=$mv;bm=$bm;met=$met} }
  $stM =[ordered]@{}; foreach($m in $ST_METS){  $mv=$VAL[$ab][$m]; $bm=$BENCH[$m]; $met=$null; if($null -ne $mv -and $null -ne $bm){ $met = if($HI[$m]){ $mv -ge $bm } else { $mv -le $bm } }; $stM[$m]=[ordered]@{v=$mv;bm=$bm;met=$met} }
  $teamObjs += [ordered]@{
    abbr=$ab; team=$FULLNAME[$ab];
    off=(PhaseScore $ab $OFF_METS); def=(PhaseScore $ab $DEF_METS); st=(PhaseScore $ab $ST_METS);
    offM=$offM; defM=$defM; stM=$stM
  }
}
$ratings=[ordered]@{ teams=$teamObjs; metricsOff=$OFF_METS; metricsDef=$DEF_METS; metricsST=$ST_METS }
$dataObj=[ordered]@{ ratings=$ratings }

$json = $dataObj | ConvertTo-Json -Depth 12 -Compress
$outFile = Join-Path $OutDir ("data/{0}/data.js" -f $Year)
$body = "regData($Year,`"DATA`",$json);`n"
[System.IO.File]::WriteAllText($outFile,$body,[System.Text.UTF8Encoding]::new($false))
Write-Host ("WROTE {0} ({1:N0} bytes, {2} teams)" -f $outFile,$body.Length,$teamObjs.Count)
# quick sanity: top-5 offense
$teamObjs | Sort-Object { -$_.off } | Select-Object -First 5 | ForEach-Object { Write-Host ("  OFF {0} {1}  (pts/g {2}, yds/g {3})" -f $_.abbr,$_.off,$_.offM['Points/G'].v,$_.offM['Yards/G'].v) }
