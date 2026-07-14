<#
build_st.ps1 — special-teams dataset for the Saints dashboard.

Streams nflverse play-by-play (gzipped CSV) and emits team-level special-teams
ratings + player-level specialist leaderboards (kickoff kickers, place kickers,
punters, kick returners, punt returners), all EPA-based. Pure PowerShell.

posteam/epa conventions (verified against 2025 pbp):
  kickoff : posteam = RECEIVING team, defteam = KICKING team, epa from receiver view
  punt    : posteam = PUNTING team,   defteam = RECEIVING team, epa from punter view
  FG / XP : posteam = KICKING team, epa from kicker view (special_teams_play flag is 0 on FGs)

Output: data/specialteams.js  ->  window.SPECIALTEAMS = { season, gen, teams:[...], players:{...} }
#>
param(
  [string]$Gz  = "C:/Users/miles/AppData/Local/Temp/claude/C--Users-miles--claude/43c60d0d-1058-41de-8b01-6569684d112c/scratchpad/pbp2025.csv.gz",
  [string]$OutDir = "C:/Users/miles/saints-dashboard",
  [int]$Year = 2025
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName Microsoft.VisualBasic

$fs  = [System.IO.File]::OpenRead($Gz)
$gzs = New-Object System.IO.Compression.GZipStream($fs,[System.IO.Compression.CompressionMode]::Decompress)
$tp  = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($gzs)
$tp.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
$tp.SetDelimiters(@(","))
$tp.HasFieldsEnclosedInQuotes = $true
$hdr = $tp.ReadFields(); $ix=@{}; for($i=0;$i -lt $hdr.Length;$i++){ $ix[$hdr[$i]]=$i }
function C([string]$n){ $ix[$n] }
$I_gid=C 'game_id'; $I_st=C 'season_type'; $I_pt=C 'play_type'; $I_pos=C 'posteam'; $I_def=C 'defteam'
$I_epa=C 'epa'; $I_yl=C 'yardline_100'; $I_down=C 'down'; $I_fdr=C 'fixed_drive'
$I_fgr=C 'field_goal_result'; $I_xpr=C 'extra_point_result'; $I_kd=C 'kick_distance'
$I_kick=C 'kicker_player_name'; $I_punt=C 'punter_player_name'
$I_kret=C 'kickoff_returner_player_name'; $I_pret=C 'punt_returner_player_name'
$I_ry=C 'return_yards'; $I_in20=C 'punt_inside_twenty'

function Dbl($v){ if($null -eq $v -or $v -eq '' -or $v -eq 'NA'){ return $null } [double]$v }
function IsOne($v){ $v -eq '1' -or $v -eq '1.0' }

# team aggregates
$T=@{}
function Tm($ab){
  if(-not $T.ContainsKey($ab)){
    $T[$ab]=[ordered]@{ stE=0.0; stN=0; fgM=0; fgA=0; fgE=0.0; fgN=0; koE=0.0; koN=0;
      krE=0.0; krN=0; puE=0.0; puN=0; prE=0.0; prN=0; dsSum=0.0; dsN=0; daSum=0.0; daN=0 }
  }
  $T[$ab]
}
# player aggregates: 5 buckets, each keyed "name|team"
$KO=@{}; $PK=@{}; $PU=@{}; $KR=@{}; $PR=@{}
function Pl($h,$name,$team,$init){
  $k="$name|$team"
  if(-not $h.ContainsKey($k)){ $o=$init.Clone(); $o['name']=$name; $o['team']=$team; $h[$k]=$o }
  $h[$k]
}
$seenDrive=@{}

while(-not $tp.EndOfData){
  $f=$tp.ReadFields()
  if($f[$I_st] -ne 'REG'){ continue }
  $pt=$f[$I_pt]; $pos=$f[$I_pos]; $def=$f[$I_def]; $epa=Dbl $f[$I_epa]

  # ---- drive start field position (own yard line = 100 - yardline_100) ----
  $dn=$f[$I_down]; $yl=Dbl $f[$I_yl]; $fd=$f[$I_fdr]
  if($dn -ne '' -and $dn -ne 'NA' -and $null -ne $yl -and $fd -ne '' -and $pos -ne ''){
    $dk="$($f[$I_gid])|$fd|$pos"
    if(-not $seenDrive.ContainsKey($dk)){
      $seenDrive[$dk]=1
      $own = 100 - $yl
      $o=Tm $pos; $o.dsSum += $own; $o.dsN++
      if($def -ne ''){ $d=Tm $def; $d.daSum += $own; $d.daN++ }
    }
  }

  if($pt -eq 'field_goal'){
    if($pos -ne '' -and $null -ne $epa){ $o=Tm $pos; $o.stE+=$epa; $o.stN++; $o.fgE+=$epa; $o.fgN++
      $o.fgA++; if($f[$I_fgr] -eq 'made'){ $o.fgM++ } }
    if($f[$I_kick] -ne '' -and $pos -ne ''){
      $p=Pl $PK $f[$I_kick] $pos @{fgm=0;fga=0;xpm=0;xpa=0;lng=0;e=0.0;n=0}
      $p.fga++; $p.n++; if($null -ne $epa){ $p.e+=$epa }
      $kd=Dbl $f[$I_kd]
      if($f[$I_fgr] -eq 'made'){ $p.fgm++; if($null -ne $kd -and $kd -gt $p.lng){ $p.lng=[int]$kd } } }
  }
  elseif($pt -eq 'extra_point'){
    if($pos -ne '' -and $null -ne $epa){ $o=Tm $pos; $o.stE+=$epa; $o.stN++ }
    if($f[$I_kick] -ne '' -and $pos -ne ''){
      $p=Pl $PK $f[$I_kick] $pos @{fgm=0;fga=0;xpm=0;xpa=0;lng=0;e=0.0;n=0}
      $p.xpa++; $p.n++; if($null -ne $epa){ $p.e+=$epa }
      if($f[$I_xpr] -eq 'good'){ $p.xpm++ } }
  }
  elseif($pt -eq 'kickoff'){
    # posteam = receiving (return); defteam = kicking (coverage)
    if($pos -ne '' -and $null -ne $epa){ $o=Tm $pos; $o.stE+=$epa; $o.stN++; $o.krE+=$epa; $o.krN++ }
    if($def -ne '' -and $null -ne $epa){ $d=Tm $def; $d.stE+=(-$epa); $d.stN++; $d.koE+=(-$epa); $d.koN++ }
    if($f[$I_kick] -ne '' -and $def -ne ''){          # kicker is on the kicking team (defteam)
      $p=Pl $KO $f[$I_kick] $def @{e=0.0;n=0;dist=0.0;dn=0}
      $p.n++; if($null -ne $epa){ $p.e+=(-$epa) }
      $kd=Dbl $f[$I_kd]; if($null -ne $kd){ $p.dist+=$kd; $p.dn++ } }
    if($f[$I_kret] -ne '' -and $pos -ne ''){           # returner on receiving team (posteam)
      $p=Pl $KR $f[$I_kret] $pos @{e=0.0;n=0;yds=0.0}
      $p.n++; if($null -ne $epa){ $p.e+=$epa }; $ry=Dbl $f[$I_ry]; if($null -ne $ry){ $p.yds+=$ry } }
  }
  elseif($pt -eq 'punt'){
    # posteam = punting; defteam = receiving (return)
    if($pos -ne '' -and $null -ne $epa){ $o=Tm $pos; $o.stE+=$epa; $o.stN++; $o.puE+=$epa; $o.puN++ }
    if($def -ne '' -and $null -ne $epa){ $d=Tm $def; $d.stE+=(-$epa); $d.stN++; $d.prE+=(-$epa); $d.prN++ }
    if($f[$I_punt] -ne '' -and $pos -ne ''){
      $p=Pl $PU $f[$I_punt] $pos @{e=0.0;n=0;gross=0.0;gn=0;in20=0}
      $p.n++; if($null -ne $epa){ $p.e+=$epa }
      $kd=Dbl $f[$I_kd]; if($null -ne $kd){ $p.gross+=$kd; $p.gn++ }
      if(IsOne $f[$I_in20]){ $p.in20++ } }
    if($f[$I_pret] -ne '' -and $def -ne ''){           # returner on receiving team (defteam)
      $p=Pl $PR $f[$I_pret] $def @{e=0.0;n=0;yds=0.0}
      $p.n++; if($null -ne $epa){ $p.e+=(-$epa) }; $ry=Dbl $f[$I_ry]; if($null -ne $ry){ $p.yds+=$ry } }
  }
}
$tp.Close()

# ---- JSON helpers ----
function Nn($v,[int]$dec){ if($null -eq $v){ return 'null' } ([math]::Round([double]$v,$dec)).ToString([Globalization.CultureInfo]::InvariantCulture) }
function Per($sum,$n,[int]$dec){ if($n -le 0){ return 'null' } Nn ($sum/$n) $dec }
function Js($s){ '"' + ($s -replace '\\','\\' -replace '"','\"') + '"' }

$teamRows = foreach($ab in ($T.Keys | Sort-Object)){
  $o=$T[$ab]
  $fgPct = if($o.fgA -gt 0){ Nn (100.0*$o.fgM/$o.fgA) 1 } else { 'null' }
  "{`"abbr`":$(Js $ab),`"stEpa`":$(Per $o.stE $o.stN 3),`"stPlays`":$($o.stN),`"fgM`":$($o.fgM),`"fgA`":$($o.fgA),`"fgPct`":$fgPct,`"fgEpa`":$(Per $o.fgE $o.fgN 3),`"koEpa`":$(Per $o.koE $o.koN 3),`"krEpa`":$(Per $o.krE $o.krN 3),`"prEpa`":$(Per $o.prE $o.prN 3),`"puntEpa`":$(Per $o.puE $o.puN 3),`"driveStart`":$(Per $o.dsSum $o.dsN 1),`"driveStartAllowed`":$(Per $o.daSum $o.daN 1)}"
}

function PlayerRows($h,$fields){
  $out=foreach($k in $h.Keys){ $o=$h[$k]; $parts=foreach($fk in $fields.Keys){ $spec=$fields[$fk]; & $spec $o }; '{'+($parts -join ',')+'}' }
  $out
}

# kickoff kickers
$koRows = foreach($k in $KO.Keys){ $o=$KO[$k]
  "{`"name`":$(Js $o.name),`"team`":$(Js $o.team),`"n`":$($o.n),`"epa`":$(Per $o.e $o.n 3),`"dist`":$(Per $o.dist $o.dn 1)}" }
# place kickers
$pkRows = foreach($k in $PK.Keys){ $o=$PK[$k]
  $fgp = if($o.fga -gt 0){ Nn (100.0*$o.fgm/$o.fga) 1 } else { 'null' }
  $lng = if($o.lng -gt 0){ $o.lng } else { 'null' }
  "{`"name`":$(Js $o.name),`"team`":$(Js $o.team),`"fgm`":$($o.fgm),`"fga`":$($o.fga),`"fgPct`":$fgp,`"long`":$lng,`"xpm`":$($o.xpm),`"xpa`":$($o.xpa),`"n`":$($o.n),`"epa`":$(Per $o.e $o.n 3)}" }
# punters
$puRows = foreach($k in $PU.Keys){ $o=$PU[$k]
  "{`"name`":$(Js $o.name),`"team`":$(Js $o.team),`"n`":$($o.n),`"epa`":$(Per $o.e $o.n 3),`"gross`":$(Per $o.gross $o.gn 1),`"in20`":$($o.in20)}" }
# kick returners
$krRows = foreach($k in $KR.Keys){ $o=$KR[$k]
  "{`"name`":$(Js $o.name),`"team`":$(Js $o.team),`"n`":$($o.n),`"epa`":$(Per $o.e $o.n 3),`"avg`":$(Per $o.yds $o.n 1)}" }
# punt returners
$prRows = foreach($k in $PR.Keys){ $o=$PR[$k]
  "{`"name`":$(Js $o.name),`"team`":$(Js $o.team),`"n`":$($o.n),`"epa`":$(Per $o.e $o.n 3),`"avg`":$(Per $o.yds $o.n 1)}" }

$gen=(Get-Date).ToString('yyyy-MM-dd')
$js = "window.SPECIALTEAMS={`"season`":$Year,`"gen`":`"$gen`",`n" +
  "`"teams`":[`n" + ($teamRows -join ",`n") + "`n],`n" +
  "`"players`":{`n" +
  "`"kickoff`":[" + ($koRows -join ",") + "],`n" +
  "`"place`":["   + ($pkRows -join ",") + "],`n" +
  "`"punt`":["    + ($puRows -join ",") + "],`n" +
  "`"kret`":["    + ($krRows -join ",") + "],`n" +
  "`"pret`":["    + ($prRows -join ",") + "]`n" +
  "}};`n"

$outPath = Join-Path $OutDir "data/specialteams.js"
[System.IO.File]::WriteAllText($outPath,$js,[System.Text.UTF8Encoding]::new($false))
Write-Output "Wrote $outPath"
Write-Output "Teams: $($teamRows.Count) | kickoffK: $($KO.Count) placeK: $($PK.Count) punters: $($PU.Count) kret: $($KR.Count) pret: $($PR.Count)"
