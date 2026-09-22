<#
build_snaps.ps1 - per-player PASS vs RUN on-field snap split -> data/snaps.js

Uses participation (offense_players = who's actually on the field per snap) joined to
the play-by-play (play_type = pass/run) and the roster (gsis_id -> name/position).
For every RB / WR / TE, counts how many pass snaps and run snaps he was ON THE FIELD
for, overall and broken out by offensive personnel grouping (backs+TE, e.g. "11").

Output: data/snaps.js -> window.SNAPX = {
  season, gen,
  teams: { "<TM>": [ {n:"A.Kamara",pos:"RB",p:<passSnaps>,r:<runSnaps>,g:{"11":[p,r],...}}, ... ] }
}
Pass share = p / (p + r). Sorting/filtering is done in the UI.
#>
param(
  [string]$Pbp    = "C:/Users/miles/Downloads/play_by_play_2025.csv",                # .csv or .csv.gz
  [string]$Part   = "C:/Users/miles/Downloads/pbp_participation_2025.csv",
  [string]$Roster = "C:/Users/miles/AppData/Local/Temp/claude/C--Users-miles--claude/43c60d0d-1058-41de-8b01-6569684d112c/scratchpad/roster2025.csv",
  [string]$OutDir = "C:/Users/miles/saints-dashboard",
  [int]   $Year   = 2025,
  [int]   $MinSnaps = 25
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName Microsoft.VisualBasic

# No participation (e.g. nflverse hasn't published it for this season) -> emit an empty SNAPX
# sentinel so the dashboard shows "no data" for snap roles/tells instead of falling back to a
# prior season. Snap counts alone can't reconstruct the per-play on/off-field split.
if(-not (Test-Path $Part)){
  $gen=(Get-Date).ToString('yyyy-MM-dd')
  [System.IO.File]::WriteAllText((Join-Path $OutDir 'data/snaps.js'),'window.SNAPX={"season":'+$Year+',"gen":"'+$gen+'","teams":{},"tot":{}};'+"`n",[System.Text.UTF8Encoding]::new($false))
  Write-Host "build_snaps: no participation at '$Part' -> wrote empty SNAPX sentinel for $Year"
  return
}

function PersGroup($s){
  if([string]::IsNullOrEmpty($s)){ return $null }
  $rb=0;$fb=0;$te=0
  foreach($m in [regex]::Matches($s,'(\d+)\s*(RB|FB|TE)\b')){ $c=[int]$m.Groups[1].Value; $p=$m.Groups[2].Value; if($p -eq 'RB'){$rb=$c}elseif($p -eq 'FB'){$fb=$c}else{$te=$c} }
  $backs=$rb+$fb; if($backs -gt 4 -or $te -gt 4){ return $null }
  return "$backs$te"
}
function ShortName($full){
  $t=@(([string]$full).Trim() -split '\s+'); $suf=@('Jr.','Sr.','II','III','IV','V')
  while($t.Count -gt 2 -and $suf -contains $t[-1]){ $t=$t[0..($t.Count-2)] }
  if($t.Count -lt 2){ return $t[0] }
  return $t[0].Substring(0,1)+'.'+($t[1..($t.Count-1)] -join ' ')
}
function Jstr($s){ if($null -eq $s){return 'null'} ; '"'+(([string]$s) -replace '\\','\\' -replace '"','\"')+'"' }

# ---- 1. roster: gsis_id -> {name, pos}  (RB/FB/WR/TE only; FB folded into RB) ----
$ROST=@{}
$rf=New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Roster)
$rf.SetDelimiters(@(",")); $rf.HasFieldsEnclosedInQuotes=$true
$rh=$rf.ReadFields(); $rix=@{}; for($i=0;$i -lt $rh.Length;$i++){ $rix[$rh[$i]]=$i }
$R_g=$rix['gsis_id']; $R_pos=$rix['position']
$R_nm = if($rix.ContainsKey('full_name')){$rix['full_name']}elseif($rix.ContainsKey('player_name')){$rix['player_name']}elseif($rix.ContainsKey('football_name')){$rix['football_name']}else{-1}
while(-not $rf.EndOfData){
  $g=$rf.ReadFields(); $gid=[string]$g[$R_g]; if(-not $gid){continue}
  $pos=[string]$g[$R_pos]; if($pos -eq 'FB'){$pos='RB'}
  if($pos -ne 'RB' -and $pos -ne 'WR' -and $pos -ne 'TE'){continue}
  $nm= if($R_nm -ge 0){ShortName $g[$R_nm]}else{$gid}
  if(-not $ROST.ContainsKey($gid)){ $ROST[$gid]=@{name=$nm;pos=$pos} }
}
$rf.Close()
Write-Host "roster RB/WR/TE: $($ROST.Count)"

# ---- 2. participation: key(game|play) -> {team, pers, off[]} ----
$PMAP=@{}
$pf=New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Part)
$pf.SetDelimiters(@(",")); $pf.HasFieldsEnclosedInQuotes=$true
$ph=$pf.ReadFields(); $pix=@{}; for($i=0;$i -lt $ph.Length;$i++){ $pix[$ph[$i]]=$i }
$P_g=$pix['nflverse_game_id']; $P_p=$pix['play_id']; $P_tm=$pix['possession_team']; $P_pers=$pix['offense_personnel']; $P_off=$pix['offense_players']
while(-not $pf.EndOfData){
  $g=$pf.ReadFields()
  $off=[string]$g[$P_off]; if(-not $off){continue}
  $PMAP[[string]$g[$P_g]+'|'+[string]$g[$P_p]]=@{team=[string]$g[$P_tm];pers=(PersGroup $g[$P_pers]);off=$off.Split(';')}
}
$pf.Close()
Write-Host "participation plays: $($PMAP.Count)"

# ---- 3. pbp: for each pass/run play, credit every on-field RB/WR/TE ----
# ACC: team -> gsis -> @{p;r;g=@{code->[p,r]}}
$ACC=@{}
$TTOT=@{}  # team -> pers -> [pass,run]  (team totals per personnel, one credit per PLAY)
function Bump($team,$gid,$isPass,$pers){
  if(-not $ACC.ContainsKey($team)){ $ACC[$team]=@{} }
  $t=$ACC[$team]; if(-not $t.ContainsKey($gid)){ $t[$gid]=@{p=0;r=0;g=@{}} }
  $o=$t[$gid]; if($isPass){$o.p++}else{$o.r++}
  if($pers){ if(-not $o.g.ContainsKey($pers)){ $o.g[$pers]=@(0,0) } ; if($isPass){$o.g[$pers][0]++}else{$o.g[$pers][1]++} }
}
$isGz = $Pbp.ToLower().EndsWith('.gz')
if($isGz){ $fs=[System.IO.File]::OpenRead($Pbp); $gz=New-Object System.IO.Compression.GZipStream($fs,[System.IO.Compression.CompressionMode]::Decompress); $tmp=[System.IO.Path]::GetTempFileName(); $out=[System.IO.File]::Create($tmp); $gz.CopyTo($out); $out.Close(); $gz.Close(); $fs.Close(); $pbpPath=$tmp }
else { $pbpPath=$Pbp }
$bf=New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($pbpPath)
$bf.SetDelimiters(@(",")); $bf.HasFieldsEnclosedInQuotes=$true
$bh=$bf.ReadFields(); $bix=@{}; for($i=0;$i -lt $bh.Length;$i++){ $bix[$bh[$i]]=$i }
$B_g=$bix['game_id']; $B_p=$bix['play_id']; $B_ty=$bix['play_type']
$np=0
while(-not $bf.EndOfData){
  $g=$bf.ReadFields(); $ty=[string]$g[$B_ty]
  if($ty -ne 'pass' -and $ty -ne 'run'){continue}
  $pe=$PMAP[[string]$g[$B_g]+'|'+[string]$g[$B_p]]; if(-not $pe){continue}
  $isPass = ($ty -eq 'pass'); $team=$pe.team; $pers=$pe.pers
  if($pers -and $team){ if(-not $TTOT.ContainsKey($team)){$TTOT[$team]=@{}}; if(-not $TTOT[$team].ContainsKey($pers)){$TTOT[$team][$pers]=@(0,0)}; if($isPass){$TTOT[$team][$pers][0]++}else{$TTOT[$team][$pers][1]++} }
  foreach($id in $pe.off){ if($id -and $ROST.ContainsKey($id)){ Bump $team $id $isPass $pers } }
  $np++
}
$bf.Close(); if($isGz){ Remove-Item $pbpPath -ErrorAction SilentlyContinue }
Write-Host "scrimmage pass/run plays credited: $np ; teams: $($ACC.Count)"

# ---- 4. emit data/snaps.js ----
$gen=(Get-Date).ToString('yyyy-MM-dd')
$sb=[System.Text.StringBuilder]::new()
[void]$sb.Append('window.SNAPX={"season":'+$Year+',"gen":"'+$gen+'","teams":{'+"`n")
$tfirst=$true
foreach($team in ($ACC.Keys | Sort-Object)){
  $players=@()
  foreach($gid in $ACC[$team].Keys){
    $o=$ACC[$team][$gid]; $tot=$o.p+$o.r; if($tot -lt $MinSnaps){continue}
    $meta=$ROST[$gid]
    $gj=@(); foreach($code in ($o.g.Keys | Sort-Object)){ $gj += '"'+$code+'":['+$o.g[$code][0]+','+$o.g[$code][1]+']' }
    $players += [pscustomobject]@{ tot=$tot; js=('{"n":'+(Jstr $meta.name)+',"pos":"'+$meta.pos+'","p":'+$o.p+',"r":'+$o.r+',"g":{'+([string]::Join(',',$gj))+'}}') }
  }
  if($players.Count -eq 0){continue}
  $players = $players | Sort-Object -Property tot -Descending
  if(-not $tfirst){ [void]$sb.Append(",`n") }; $tfirst=$false
  [void]$sb.Append('"'+$team+'":['+([string]::Join(',',($players | ForEach-Object { $_.js })))+']')
}
[void]$sb.Append("`n},`n")
# team totals per personnel (denominator for on/off-field "tell" calc)
[void]$sb.Append('"tot":{'+"`n")
$tfirst=$true
foreach($team in ($TTOT.Keys | Sort-Object)){
  $cj=@(); foreach($code in ($TTOT[$team].Keys | Sort-Object)){ $cj += '"'+$code+'":['+$TTOT[$team][$code][0]+','+$TTOT[$team][$code][1]+']' }
  if(-not $tfirst){ [void]$sb.Append(",`n") }; $tfirst=$false
  [void]$sb.Append('"'+$team+'":{'+([string]::Join(',',$cj))+'}')
}
[void]$sb.Append("`n}};`n")
[System.IO.File]::WriteAllText((Join-Path $OutDir 'data/snaps.js'),$sb.ToString(),[System.Text.UTF8Encoding]::new($false))
Write-Host ("WROTE data/snaps.js - {0} teams" -f $ACC.Count)
