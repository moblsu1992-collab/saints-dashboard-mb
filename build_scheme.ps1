<#
build_scheme.ps1 — per-team scheme-fingerprint aggregates from FTN charting + nflverse pbp.

Joins FTN's play-level concept flags (play-action, screens, RPO, motion, no-huddle,
out-of-pocket, sneaks, blitzers/pass rushers) onto the pbp by nflverse game|play id and
rolls them up per team: offense counts over dropbacks/rushes, defense pressure identity
over dropbacks faced. Rates + family classification happen client-side so weights stay
adjustable without a data rebuild.

Output: <OutDir>/data/scheme.js  ->  window.SCHEME={season,teams:{ABBR:{...counts}}}
#>
param(
  [string]$Gz  = "C:/Users/miles/AppData/Local/Temp/claude/C--Users-miles--claude/43c60d0d-1058-41de-8b01-6569684d112c/scratchpad/pbp2025.csv.gz",
  [string]$Ftn = "C:/Users/miles/AppData/Local/Temp/claude/C--Users-miles--claude/43c60d0d-1058-41de-8b01-6569684d112c/scratchpad/ftn2025.csv",
  [string]$OutDir = "C:/Users/miles/saints-dashboard",
  [int]$Year = 2025
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName Microsoft.VisualBasic

# ---- pass 1: FTN charting -> packed flags per game|play ----
$FTNJ=@{}   # key -> int bitmask (1 pa, 2 screen, 4 rpo, 8 motion, 16 nohuddle, 32 oop, 64 sneak, 128 blitz) + rushers*256
$ffs=New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Ftn)
$ffs.SetDelimiters(@(",")); $ffs.HasFieldsEnclosedInQuotes=$true
$fh=$ffs.ReadFields(); $fix=@{}; for($i=0;$i -lt $fh.Length;$i++){ $fix[$fh[$i]]=$i }
$F_gid=$fix['nflverse_game_id']; $F_pid=$fix['nflverse_play_id']
$F_pa=$fix['is_play_action']; $F_scr=$fix['is_screen_pass']; $F_rpo=$fix['is_rpo']
$F_mot=$fix['is_motion']; $F_nh=$fix['is_no_huddle']; $F_oop=$fix['is_qb_out_of_pocket']
$F_snk=$fix['is_qb_sneak']; $F_blz=$fix['n_blitzers']; $F_prr=$fix['n_pass_rushers']
function T($v){ $v -eq 'TRUE' -or $v -eq 'true' -or $v -eq '1' }
$fc=0
while(-not $ffs.EndOfData){
  $g=$ffs.ReadFields(); $fc++
  $m=0
  if(T $g[$F_pa]){$m=$m -bor 1}; if(T $g[$F_scr]){$m=$m -bor 2}; if(T $g[$F_rpo]){$m=$m -bor 4}
  if(T $g[$F_mot]){$m=$m -bor 8}; if(T $g[$F_nh]){$m=$m -bor 16}; if(T $g[$F_oop]){$m=$m -bor 32}
  if(T $g[$F_snk]){$m=$m -bor 64}
  $bz=0; if($g[$F_blz] -match '^\d+$'){$bz=[int]$g[$F_blz]}
  if($bz -ge 1){$m=$m -bor 128}
  $pr=0; if($g[$F_prr] -match '^\d+$'){$pr=[int]$g[$F_prr]}
  $FTNJ[$g[$F_gid]+'|'+$g[$F_pid]]=$m + ($pr*256)
}
$ffs.Close()
Write-Host "FTN rows: $fc | joined keys: $($FTNJ.Count)"

# ---- pass 2: pbp stream -> per-team accumulators ----
$fs  = [System.IO.File]::OpenRead($Gz)
$gzs = New-Object System.IO.Compression.GZipStream($fs,[System.IO.Compression.CompressionMode]::Decompress)
$tp  = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($gzs)
$tp.TextFieldType=[Microsoft.VisualBasic.FileIO.FieldType]::Delimited
$tp.SetDelimiters(@(",")); $tp.HasFieldsEnclosedInQuotes=$true
$hdr=$tp.ReadFields(); $ix=@{}; for($i=0;$i -lt $hdr.Length;$i++){ $ix[$hdr[$i]]=$i }
function C([string]$n){ $ix[$n] }
$I_gid=C 'game_id'; $I_pid=C 'play_id'; $I_st=C 'season_type'; $I_pos=C 'posteam'; $I_def=C 'defteam'
$I_pass=C 'pass'; $I_rush=C 'rush'; $I_2pt=C 'two_point_attempt'; $I_ptype=C 'play_type'
function IsOne($v){ $v -eq '1' -or $v -eq '1.0' }

$OFF=@{}; $DEF=@{}
function OffT($t){ if(-not $OFF.ContainsKey($t)){ $OFF[$t]=@{db=0;ru=0;pa=0;scr=0;rpo=0;mot=0;nh=0;oop=0;snk=0} } $OFF[$t] }
function DefT($t){ if(-not $DEF.ContainsKey($t)){ $DEF[$t]=@{db=0;blz=0;prr=0;prN=0} } $DEF[$t] }
$n=0
while(-not $tp.EndOfData){
  $f=$tp.ReadFields(); $n++
  if($f[$I_st] -ne 'REG'){ continue }
  if(IsOne $f[$I_2pt]){ continue }
  $pt=$f[$I_ptype]; if($pt -eq 'qb_kneel' -or $pt -eq 'qb_spike'){ continue }
  $isP=IsOne $f[$I_pass]; $isR=IsOne $f[$I_rush]
  if(-not ($isP -or $isR)){ continue }
  $pos=$f[$I_pos]; $dt=$f[$I_def]
  if([string]::IsNullOrEmpty($pos) -or [string]::IsNullOrEmpty($dt)){ continue }
  $o=OffT $pos
  $k=$f[$I_gid]+'|'+$f[$I_pid]
  $m=0; $hasF=$FTNJ.ContainsKey($k); if($hasF){ $m=$FTNJ[$k] }
  if($m -band 4){$o.rpo++}; if($m -band 8){$o.mot++}; if($m -band 16){$o.nh++}
  if($isP){
    $o.db++
    if($m -band 1){$o.pa++}; if($m -band 2){$o.scr++}; if($m -band 32){$o.oop++}
    $d=DefT $dt
    $d.db++
    if($m -band 128){$d.blz++}
    if($hasF){ $pr=[math]::Floor($m/256); if($pr -gt 0){ $d.prr+=$pr; $d.prN++ } }
  } else {
    $o.ru++
    if($m -band 64){$o.snk++}
  }
}
$tp.Close()
Write-Host "pbp rows: $n | teams: $($OFF.Count)"

# ---- emit ----
$sb=New-Object System.Text.StringBuilder
[void]$sb.Append("// Per-team scheme-fingerprint counts - FTN charting x nflverse pbp, $Year regular season.`n")
[void]$sb.Append("// Offense: db/ru denominators; pa/scr/oop over dropbacks, rpo/mot/nh over all plays, snk over rushes.`n")
[void]$sb.Append("// Defense: db faced; blz = snaps with >=1 blitzer; prr/prN -> avg pass rushers.`n")
[void]$sb.Append("window.SCHEME={season:$Year,src:`"FTN charting via nflverse`",teams:{`n")
$teams=$OFF.Keys | Sort-Object
$first=$true
foreach($t in $teams){
  $o=$OFF[$t]; $d=DefT $t
  if(-not $first){ [void]$sb.Append(",`n") }; $first=$false
  [void]$sb.Append(" $t`:{db:$($o.db),ru:$($o.ru),pa:$($o.pa),scr:$($o.scr),rpo:$($o.rpo),mot:$($o.mot),nh:$($o.nh),oop:$($o.oop),snk:$($o.snk),dDb:$($d.db),dBlz:$($d.blz),dPrr:$($d.prr),dPrN:$($d.prN)}")
}
[void]$sb.Append("`n}};`n")
$outFile=Join-Path $OutDir "data/scheme.js"
[System.IO.File]::WriteAllText($outFile,$sb.ToString())
Write-Host "wrote $outFile ($([math]::Round((Get-Item $outFile).Length/1KB,1)) KB)"
foreach($t in @('NO','LA','PHI','BAL')){ if($OFF.ContainsKey($t)){ $o=$OFF[$t]; Write-Host ("{0}: db={1} ru={2} PA%={3:P1} RPO%={4:P1} motion%={5:P1}" -f $t,$o.db,$o.ru,($o.pa/[math]::Max(1,$o.db)),($o.rpo/([math]::Max(1,$o.db+$o.ru))),($o.mot/([math]::Max(1,$o.db+$o.ru)))) } }
