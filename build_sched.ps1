<#
build_sched.ps1 - real NFL schedule -> data/sched.js

Reads the nflverse schedules release (games.csv - same data family as the play-by-play)
and emits the season's slate plus each team's rest days, computed from the game dates.

Output: data/sched.js -> window.SCHED = { season, gen, weeks, games, byTeam }
  byTeam[TEAM][WEEK] = { opp, home, date, rest }   rest = days since that team's previous game
#>
param(
  [string]$Games = "C:/Users/miles/AppData/Local/Temp/claude/C--Users-miles--claude/43c60d0d-1058-41de-8b01-6569684d112c/scratchpad/games.csv",
  [string]$OutDir = "C:/Users/miles/saints-dashboard",
  [int]$Year = 2026
)
$ErrorActionPreference = "Stop"

$rows = Import-Csv $Games | Where-Object { [int]$_.season -eq $Year -and $_.game_type -eq 'REG' }
if(-not $rows){ throw "No REG games found for $Year in $Games" }

# NB: do NOT call this $games - it would alias the [string]$Games param (vars are case-insensitive) and
# the type constraint would silently coerce the array to a string, turning += into concatenation.
$gl=@(); $byTeam=@{}
foreach($r in $rows){
  $wk=[int]$r.week; $a=$r.away_team; $h=$r.home_team; $d=$r.gameday
  $gl += [ordered]@{wk=$wk;away=$a;home=$h;date=$d}
  foreach($pair in @(@($a,$h,0),@($h,$a,1))){
    # NB: $home would clash with the read-only built-in $HOME (PowerShell vars are case-insensitive)
    $t=$pair[0]; $o=$pair[1]; $isHome=$pair[2]
    if(-not $byTeam.ContainsKey($t)){ $byTeam[$t]=@{} }
    $byTeam[$t][$wk]=[ordered]@{opp=$o;home=$isHome;date=$d;rest=$null}
  }
}
# rest = days since that team's previous game (null in their opener)
foreach($t in $byTeam.Keys){
  $wks = $byTeam[$t].Keys | Sort-Object
  $prev=$null
  foreach($w in $wks){
    $d=[datetime]::ParseExact($byTeam[$t][$w].date,'yyyy-MM-dd',$null)
    if($null -ne $prev){ $byTeam[$t][$w].rest=[int]($d-$prev).TotalDays }
    $prev=$d
  }
}
$weeks = ($gl | ForEach-Object { $_.wk } | Sort-Object -Unique)

function Js($s){ if($null -eq $s){return 'null'} ; '"' + ($s -replace '\\','\\' -replace '"','\"') + '"' }
$gJs = ($gl | Sort-Object {$_.wk},{$_.away} | ForEach-Object { "{`"wk`":$($_.wk),`"away`":$(Js $_.away),`"home`":$(Js $_.home),`"date`":$(Js $_.date)}" }) -join ",`n"
$tJs = ($byTeam.Keys | Sort-Object | ForEach-Object {
  $t=$_
  $inner = ($byTeam[$t].Keys | Sort-Object | ForEach-Object {
    $w=$_; $o=$byTeam[$t][$w]
    "`"$w`":{`"opp`":$(Js $o.opp),`"home`":$($o.home),`"date`":$(Js $o.date),`"rest`":$(if($null -eq $o.rest){'null'}else{$o.rest})}"
  }) -join ","
  "`"$t`":{$inner}"
}) -join ",`n"

$gen=(Get-Date).ToString('yyyy-MM-dd')
$js = "window.SCHED={`"season`":$Year,`"gen`":`"$gen`",`"src`":`"nflverse schedules release (games.csv)`",`n" +
  "`"weeks`":[$($weeks -join ',')],`n" +
  "`"games`":[`n$gJs`n],`n" +
  "`"byTeam`":{`n$tJs`n}};`n"
[System.IO.File]::WriteAllText((Join-Path $OutDir 'data/sched.js'),$js,[System.Text.UTF8Encoding]::new($false))
Write-Output "sched.js -> $Year : $($gl.Count) games, weeks $($weeks[0])-$($weeks[-1]), $($byTeam.Count) teams"
