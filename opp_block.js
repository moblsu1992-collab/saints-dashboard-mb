// ---------- OPPONENTS ----------
// Lookup maps (built once from DATA)
const RT={},ET={},NEU={},PRO={},FTH={},LCK={},SER={},FPR={},OBR={},DBR={};
DATA.ratings.teams.forEach(t=>RT[t.abbr]=t);
DATA.leagueEPA.teams.forEach(t=>ET[t.abbr]=t);
DATA.leagueEPA.neutral.forEach(t=>NEU[t.abbr]=t);
DATA.leagueEPA.proe.forEach(t=>PRO[t.abbr]=t);
DATA.leagueEPA.fourth.forEach(t=>FTH[t.abbr]=t);
DATA.leagueEPA.luck.forEach(t=>LCK[t.abbr]=t);
DATA.leagueEPA.series.forEach(t=>SER[t.abbr]=t);
DATA.fieldPos.rows.forEach(r=>FPR[r.abbr]=r);
const OBI={},DBI={};DATA.offBoard.cols.forEach((c,i)=>OBI[c]=i);DATA.defBoard.cols.forEach((c,i)=>DBI[c]=i);
DATA.offBoard.rows.forEach(r=>{if(r[0]!=='LEAGUE')OBR[r[0]]=r});
DATA.defBoard.rows.forEach(r=>{if(r[0]!=='LEAGUE')DBR[r[0]]=r});
const DBLG=DATA.defBoard.rows.find(r=>r[0]==='LEAGUE');
// Helpers
const ORDS=['th','st','nd','rd'];
const ord=n=>{const x=n%100;return n+(ORDS[(x-20)%10]||ORDS[x]||ORDS[0]);};
const rankOf=(arr,v,desc)=>{const s=arr.filter(x=>typeof x==='number').sort((a,b)=>desc?b-a:a-b);return s.indexOf(v)+1;};
const meanSd=a=>{const v=a.filter(x=>typeof x==='number');if(!v.length)return[0,1];const m=v.reduce((s,x)=>s+x,0)/v.length;const sd=Math.sqrt(v.reduce((s,x)=>s+(x-m)*(x-m),0)/v.length);return[m,sd||1];};
const rkTag=(r,n=32)=>{if(!r)return '';const q=r/n;const c=q<=.25?'#1e7a34':q<=.5?'#2e5496':q<=.75?'#b07d12':'#a23b3b';return `<span class="rk" style="color:${c}">${ord(r)}${n!==32?'/'+n:''}</span>`;};
// Deviation cell: blue = above league avg, orange = below; intensity = |z|
function devCell(v,m,sd,dec=1){if(typeof v!=='number')return '<td>—</td>';const z=(v-m)/(sd||1);const a=Math.min(1,Math.abs(z)/2.2);const bg=z>=0?`rgba(46,84,150,${(0.07+0.35*a).toFixed(2)})`:`rgba(216,134,33,${(0.07+0.35*a).toFixed(2)})`;const d=v-m;return `<td style="background:${bg}"><b>${fmt(v)}</b><span class="dv">${d>=0?'+':'-'}${Math.abs(d).toFixed(dec)}</span></td>`;}
const SUMM2OB={'Neutral ED Pass%':'Neutral ED Pass%','PROE':'PROE','Play-action%':'PlayAction%','Motion%':'Motion%','Deep% (air>=20)':'Deep% (air>=20)','3rd & 7+ Pass%':'3rd&7+ Pass%','Red Zone Pass%':'RedZone Pass%','Shotgun%':'Shotgun%','No-Huddle%':'NoHuddle%'};
// Rule-based scouting angles. h = angle when tendency is high, l = when low.
const ANG={
 'Neutral ED Pass%':{h:'throws even when nothing forces it — early-down pass-rush plan matters more than run fits',l:'run-committed on early downs — box counts and early-down run fits decide this game'},
 'PROE':{h:'passes far beyond what situations dictate — coverage disguise and rush wins carry the plan',l:'leans run beyond what situations call for — expect patience on the ground even behind schedule'},
 'Play-action%':{h:'heavy play-action — second-level eye discipline; LBs cannot trigger downhill on first run key',l:'rarely fakes it — defenders can play their run/pass keys honestly'},
 'Motion%':{h:'constant pre-snap motion to ID coverage and steal leverage — disguise late, lock in bunch/stack rules',l:'static pre-snap — coverage disguise holds its value all the way to the snap'},
 'Deep% (air>=20)':{h:'shot-play offense — safety depth is non-negotiable, no peeking in the backfield',l:'dink-and-dunk profile — rally and tackle, make them earn 12-play drives'},
 '3rd & 7+ Pass%':{h:'fully predictable in long yardage — pin ears back on 3rd & 7+',l:'will run draws/screens in long yardage — rush with lane discipline'},
 'Red Zone Pass%':{h:'throws to finish drives — match routes and plaster late in the red zone',l:'ground-and-pound inside the 20 — heavy fronts and gap control finish these drives'},
 'Shotgun%':{h:'lives in shotgun — run game skews zone-read/draw; backfield depth tips run scheme',l:'real under-center usage — duo/wide-zone plus play-action shot pairs off it'},
 'No-Huddle%':{h:'tempo team — substitution risk; carry calls that work from the personnel already on the field',l:''},
 'P11':{h:'almost exclusively 11 personnel — nickel can live on the field all game',l:'rotates well beyond 11 personnel — package recognition matters every snap'},
 'P12':{h:'heavy 12 personnel — base-defense bodies; TEs stress edge run fits and the seams',l:''},
 'P13':{h:'13-personnel package team — short-yardage/goal-line run identity, set hard edges',l:''},
 'AfterFail':{h:'abandons balance behind schedule — win first down and the pass is coming',l:'stays balanced behind schedule — no free run/pass tell after a lost down'},
 'ShotGreen':{h:'hunts shots in the green zone (opp 21-40) — deepest coverage of the drive comes just before FG range',l:'will not take the cheap shot — expect them to grind once across midfield'},
 'Man %':{h:'man-heavy — stack/bunch releases, mesh and rub concepts win; motion to ID it early',l:''},
 'Zone %':{h:'zone-heavy — settle into windows, attack the hook/curl and hole defenders',l:''},
 '1-High/MOFC %':{h:'single-high dominant — post/seam shots are there, but the run game faces a loaded box',l:''},
 '2-High/MOFO %':{h:'two-high shell — light boxes invite the run; in-breakers find the open intermediate middle',l:''},
 'Blitz %':{h:'pressure defense — quick game, screens and hot answers must be carried every snap',l:'rushes four and trusts coverage — time exists but windows stay tight; checkdowns and scramble yards are the release valve'},
 'Light box %':{h:'plays light boxes — the downhill run game should travel all day',l:''},
 'Heavy box %':{h:'stacks the box — play-action and perimeter throws beat the extra hat',l:''},
 'Sub pkg %':{h:'lives in sub-packages — 12/13 personnel forces base defense or creates coverage mismatches',l:'stays in base — spread sets force their LBs to cover in space'},
 'Sack%':{h:'elite at getting home — protection plan, chips and quick rhythm are required',l:'struggles to finish rushes — deeper-developing concepts get their time'},
 'Expl% allowed':{h:'leaks explosive plays — shot plays belong in the opening script',l:'allows nothing cheap — sustain drives; red-zone efficiency decides it'}
};
function buildKeys(o){
 const offC=[];
 Object.entries(SUMM2OB).forEach(([k,col])=>{const[,sd]=meanSd(Object.values(OBR).map(r=>r[OBI[col]]));const v=o.summ[k];const m=DATA.leagueSumm[k];if(typeof v==='number')offC.push({lab:k,v,m,z:(v-m)/sd,a:ANG[k]});});
 const persIdx={'11':0,'12':1,'13':3};
 Object.entries(persIdx).forEach(([g,i])=>{const[,sd]=meanSd(DATA.opponents.map(x=>x.pers?x.pers[i]:null));const v=o.pers?o.pers[i]:null;const m=o.persLG[i];if(typeof v==='number')offC.push({lab:g+' personnel %',v,m,z:(v-m)/sd,a:ANG['P'+g]});});
 {const vals=DATA.opponents.map(x=>x.seq['After failure']);const[m,sd]=meanSd(vals);const v=o.seq['After failure'];if(typeof v==='number')offC.push({lab:'Pass% after failed play',v,m,z:(v-m)/sd,a:ANG['AfterFail']});}
 {const fp=FPR[o.src]||FPR[o.abbr];if(fp){const[m,sd]=meanSd(DATA.fieldPos.rows.map(r=>r.shot_Green));const v=fp.shot_Green;if(typeof v==='number')offC.push({lab:'Green-zone shot %',v,m,z:(v-m)/sd,a:ANG['ShotGreen']});}}
 const defC=[];
 const covLab=['Man %','Zone %','1-High/MOFC %','2-High/MOFO %'],frLab=['Blitz %','Light box %','Heavy box %','Sub pkg %'];
 covLab.forEach((l,i)=>{const[,sd]=meanSd(DATA.opponents.map(x=>x.cov?x.cov[i]:null));const v=o.cov?o.cov[i]:null;const m=DATA.covLG[i];if(typeof v==='number')defC.push({lab:l,v,m,z:(v-m)/sd,a:ANG[l]});});
 frLab.forEach((l,i)=>{const[,sd]=meanSd(DATA.opponents.map(x=>x.def2?x.def2[i]:null));const v=o.def2?o.def2[i]:null;const m=DATA.defLG[i];if(typeof v==='number')defC.push({lab:l,v,m,z:(v-m)/sd,a:ANG[l]});});
 ['Sack%','Expl% allowed'].forEach(col=>{const[,sd]=meanSd(Object.values(DBR).map(r=>r[DBI[col]]));const r=DBR[o.abbr];const m=DBLG[DBI[col]];if(r&&typeof r[DBI[col]]==='number')defC.push({lab:col,v:r[DBI[col]],m,z:(r[DBI[col]]-m)/sd,a:ANG[col]});});
 const dedupe=(arr,pairs)=>{pairs.forEach(p=>{const c=arr.filter(x=>p.includes(x.lab));if(c.length>1){c.sort((a,b)=>Math.abs(b.z)-Math.abs(a.z));c.slice(1).forEach(x=>x.drop=true);}});return arr.filter(x=>!x.drop);};
 const pick=arr=>arr.filter(x=>x.a&&Math.abs(x.z)>=0.55&&(x.z>0?x.a.h:x.a.l)).sort((a,b)=>Math.abs(b.z)-Math.abs(a.z)).slice(0,5);
 return [pick(offC),pick(dedupe(defC,[['Man %','Zone %'],['1-High/MOFC %','2-High/MOFO %'],['Light box %','Heavy box %']]))];
}
const keyLi=k=>`<li><b>${k.lab} ${fmt(k.v)}</b> <span class="rk" style="color:#667">(avg ${fmt(k.m)} · ${k.z>0?'+':''}${k.z.toFixed(1)}σ)</span> — ${k.z>0?k.a.h:k.a.l}</li>`;
const keyUl=arr=>arr.length?`<ul class="keys">${arr.map(keyLi).join('')}</ul>`:'<p class="note">No extreme tendencies — a league-typical profile. Beat the players, not the scheme.</p>';
// ----- Matchup tab -----
function matchupHTML(o){
 const oe=ET[o.src]||ET[o.abbr],te=ET[o.abbr],ne=ET['NO'];
 const offE=DATA.leagueEPA.teams.map(t=>t.off.epa),defE=DATA.leagueEPA.teams.map(t=>t.deff.epa);
 const rTO=rankOf(offE,oe.off.epa,true),rND=rankOf(defE,ne.deff.epa,false),rTD=rankOf(defE,te.deff.epa,false),rNO=rankOf(offE,ne.off.epa,true);
 const edge1=(()=>{const d=rND-rTO;return d>=6?[o.abbr+' O edge','#a23b3b']:d<=-6?['Saints D edge','#1e7a34']:['Even','#6b7280'];})();
 const edge2=(()=>{const d=rNO-rTD;return d>=6?[o.abbr+' D edge','#a23b3b']:d<=-6?['Saints O edge','#1e7a34']:['Even','#6b7280'];})();
 const side=(epa,r)=>`<div class="mbig">${epa.toFixed(3)}</div><div class="msub">EPA/play · ${ord(r)} of 32</div>`;
 const strip=(t1,h1,t2,h2,e)=>`<div class="mstrip"><div><div class="mttl">${t1}</div>${h1}</div><div class="medge"><span class="edge" style="background:${e[1]}">${e[0]}</span></div><div style="text-align:right"><div class="mttl">${t2}</div>${h2}</div></div>`;
 const mRank=(grp,met,v,desc)=>rankOf(DATA.ratings.teams.map(t=>t[grp][met]?t[grp][met].v:null),v,desc);
 const cell=(v,r,dec=1)=>typeof v==='number'?`<td><b>${dec===3?v.toFixed(3):fmt(v)}</b> ${rkTag(r)}</td>`:'<td>—</td>';
 const oM=RT[o.src]?RT[o.src].offM:null,nDM=RT['NO'].defM,tDM=RT[o.abbr].defM,nOM=RT['NO'].offM;
 const serO=SER[o.src]||SER[o.abbr];
 const t1rows=[
  ['EPA/play',cell(oe.off.epa,rTO,3)+cell(ne.deff.epa,rND,3)],
  ['Success %',cell(oe.off.succ,rankOf(DATA.leagueEPA.teams.map(t=>t.off.succ),oe.off.succ,true))+cell(ne.deff.succ,rankOf(DATA.leagueEPA.teams.map(t=>t.deff.succ),ne.deff.succ,false))],
  ['Pass EPA/play',cell(oe.off.passEPA,rankOf(DATA.leagueEPA.teams.map(t=>t.off.passEPA),oe.off.passEPA,true),3)+cell(ne.deff.passEPA,rankOf(DATA.leagueEPA.teams.map(t=>t.deff.passEPA),ne.deff.passEPA,false),3)],
  ['Rush EPA/play',cell(oe.off.rushEPA,rankOf(DATA.leagueEPA.teams.map(t=>t.off.rushEPA),oe.off.rushEPA,true),3)+cell(ne.deff.rushEPA,rankOf(DATA.leagueEPA.teams.map(t=>t.deff.rushEPA),ne.deff.rushEPA,false),3)],
  ['Series success %',cell(serO.off,rankOf(DATA.leagueEPA.series.map(x=>x.off),serO.off,true))+cell(SER['NO'].deff,rankOf(DATA.leagueEPA.series.map(x=>x.deff),SER['NO'].deff,false))],
  ['3rd-down %',oM?cell(oM['3rd-Down %'].v,mRank('offM','3rd-Down %',oM['3rd-Down %'].v,true))+cell(nDM['3rd-Down % Allowed'].v,mRank('defM','3rd-Down % Allowed',nDM['3rd-Down % Allowed'].v,false)):'<td>—</td><td>—</td>'],
  ['Explosive %',oM?cell(oM['Explosive Play %'].v,mRank('offM','Explosive Play %',oM['Explosive Play %'].v,true))+cell(nDM['Explosive % Allowed'].v,mRank('defM','Explosive % Allowed',nDM['Explosive % Allowed'].v,false)):'<td>—</td><td>—</td>'],
  ['Red Zone TD %',oM?cell(oM['Red Zone TD %'].v,mRank('offM','Red Zone TD %',oM['Red Zone TD %'].v,true))+'<td>—</td>':'<td>—</td><td>—</td>']
 ];
 const t2rows=[
  ['EPA/play',cell(te.deff.epa,rTD,3)+cell(ne.off.epa,rNO,3)],
  ['Success %',cell(te.deff.succ,rankOf(DATA.leagueEPA.teams.map(t=>t.deff.succ),te.deff.succ,false))+cell(ne.off.succ,rankOf(DATA.leagueEPA.teams.map(t=>t.off.succ),ne.off.succ,true))],
  ['Pass EPA/play',cell(te.deff.passEPA,rankOf(DATA.leagueEPA.teams.map(t=>t.deff.passEPA),te.deff.passEPA,false),3)+cell(ne.off.passEPA,rankOf(DATA.leagueEPA.teams.map(t=>t.off.passEPA),ne.off.passEPA,true),3)],
  ['Rush EPA/play',cell(te.deff.rushEPA,rankOf(DATA.leagueEPA.teams.map(t=>t.deff.rushEPA),te.deff.rushEPA,false),3)+cell(ne.off.rushEPA,rankOf(DATA.leagueEPA.teams.map(t=>t.off.rushEPA),ne.off.rushEPA,true),3)],
  ['Series success %',cell(SER[o.abbr].deff,rankOf(DATA.leagueEPA.series.map(x=>x.deff),SER[o.abbr].deff,false))+cell(SER['NO'].off,rankOf(DATA.leagueEPA.series.map(x=>x.off),SER['NO'].off,true))],
  ['3rd-down %',cell(tDM['3rd-Down % Allowed'].v,mRank('defM','3rd-Down % Allowed',tDM['3rd-Down % Allowed'].v,false))+cell(nOM['3rd-Down %'].v,mRank('offM','3rd-Down %',nOM['3rd-Down %'].v,true))],
  ['Explosive %',cell(tDM['Explosive % Allowed'].v,mRank('defM','Explosive % Allowed',tDM['Explosive % Allowed'].v,false))+cell(nOM['Explosive Play %'].v,mRank('offM','Explosive Play %',nOM['Explosive Play %'].v,true))],
  ['Sacks',cell(tDM['Sacks/G'].v,mRank('defM','Sacks/G',tDM['Sacks/G'].v,true))+cell(nOM['Sack % Allowed'].v,mRank('offM','Sack % Allowed',nOM['Sack % Allowed'].v,false))]
 ];
 const mkT=(hdL,hdR,rows)=>`<table><thead><tr><th class="tl">Metric</th><th>${hdL}</th><th>${hdR}</th></tr></thead><tbody>${rows.map(r=>`<tr><td class="tl">${r[0]}</td>${r[1]}</tr>`).join('')}</tbody></table><p class="note">Rank colors: green = top 8 · blue = 9-16 · gold = 17-24 · red = bottom 8. Defensive ranks already account for direction (lower allowed = better rank).</p>`;
 const nProxy=o.proxy?`<p class="note">⚠ Offense side uses 2025 ${o.srcName} (new play-caller proxy). Defense side is 2025 ${o.abbr} actuals.</p>`:'';
 const lk=LCK[o.abbr],ft=FTH[o.abbr],nu=NEU[o.src]||NEU[o.abbr],pr=PRO[o.src]||PRO[o.abbr];
 const idc=[
  `Neutral pass <b>${fmt(nu.neutralPass)}%</b> ${rkTag(rankOf(DATA.leagueEPA.neutral.map(x=>x.neutralPass),nu.neutralPass,true))}`,
  `PROE <b>${pr.proe>0?'+':''}${fmt(pr.proe)}</b> ${rkTag(rankOf(DATA.leagueEPA.proe.map(x=>x.proe),pr.proe,true))}`,
  `4th-down go <b>${fmt(ft.goRate)}%</b> ${rkTag(rankOf(DATA.leagueEPA.fourth.map(x=>x.goRate),ft.goRate,true))}`,
  `1-score record <b>${lk.osW}-${lk.osL}</b>`,
  `Fumble recovery <b>${fmt(lk.fumRec)}%</b>`,
  `TO margin <b>${lk.toMargin>0?'+':''}${fmt(lk.toMargin)}/g</b>`
 ].map(x=>`<span class="pill">${x}</span>`).join('');
 const [offK,defK]=buildKeys(o);
 return `${strip('Their offense'+(o.proxy?' (proxy)':''),side(oe.off.epa,rTO),'Saints defense',side(ne.deff.epa,rND),edge1)}
 ${strip('Their defense',side(te.deff.epa,rTD),'Saints offense',side(ne.off.epa,rNO),edge2)}
 <div class="idrow"><span class="mttl" style="display:block;margin-bottom:4px">Identity & game management — 2025</span>${idc}</div>${nProxy}
 <div class="grid2" style="margin-top:12px">
 <div><div class="sechead o">Their offense vs Saints defense</div>${mkT(o.abbr+' offense','NO defense',t1rows)}</div>
 <div><div class="sechead d">Their defense vs Saints offense</div>${mkT(o.abbr+' defense','NO offense',t2rows)}</div></div>
 <div class="grid2" style="margin-top:4px">
 <div><div class="sechead o">Game-plan keys — defending their offense</div>${keyUl(offK)}</div>
 <div><div class="sechead d">Game-plan keys — attacking their defense</div>${keyUl(defK)}</div></div>
 <p class="note">Keys are auto-flagged tendencies ≥0.55σ from league/opponent-sample average, ranked by extremity. σ from the 15-team tendency boards (offense) and the 14-opponent sample (defense).</p>`;
}
// ----- Their Offense tab -----
function offHTML(o){
 const oe=ET[o.src]||ET[o.abbr];const serO=SER[o.src]||SER[o.abbr];
 const eff=`<div class="idrow"><span class="pill">EPA/play <b>${oe.off.epa.toFixed(3)}</b> ${rkTag(rankOf(DATA.leagueEPA.teams.map(t=>t.off.epa),oe.off.epa,true))}</span><span class="pill">Success <b>${fmt(oe.off.succ)}%</b> ${rkTag(rankOf(DATA.leagueEPA.teams.map(t=>t.off.succ),oe.off.succ,true))}</span><span class="pill">Series success <b>${fmt(serO.off)}%</b> ${rkTag(rankOf(DATA.leagueEPA.series.map(x=>x.off),serO.off,true))}</span><span class="pill">Pass EPA <b>${oe.off.passEPA.toFixed(3)}</b></span><span class="pill">Rush EPA <b>${oe.off.rushEPA.toFixed(3)}</b></span></div>`;
 const summOrder=['Neutral ED Pass%','PROE','Play-action%','Motion%','Deep% (air>=20)','3rd & 7+ Pass%','Red Zone Pass%','Shotgun%','No-Huddle%'];
 const summ=`<table><thead><tr><th class="tl">Tendency</th><th>${o.abbr} <span class="dv" style="color:#dfe6f2">Δ vs avg</span></th><th>NFL avg</th></tr></thead><tbody>${summOrder.map(k=>{const[,sd]=meanSd(Object.values(OBR).map(r=>r[OBI[SUMM2OB[k]]]));return `<tr><td class="tl">${k}</td>${devCell(o.summ[k],DATA.leagueSumm[k],sd)}<td style="color:#888">${fmt(DATA.leagueSumm[k])}</td></tr>`;}).join('')}</tbody></table>`;
 const persLab=['11','12','21','13','22'];
 const pers=`<table><thead><tr><th class="tl">Personnel</th><th>${o.abbr}</th><th>NFL avg</th></tr></thead><tbody>${persLab.map((l,i)=>{const[,sd]=meanSd(DATA.opponents.map(x=>x.pers?x.pers[i]:null));return `<tr><td class="tl">${l} personnel %</td>${devCell(o.pers?o.pers[i]:null,o.persLG[i],sd)}<td style="color:#888">${fmt(o.persLG[i])}</td></tr>`;}).join('')}</tbody></table>`;
 const seq=`<table><thead><tr><th class="tl">Sequencing</th><th>Pass %</th><th>Opp avg</th></tr></thead><tbody>${Object.entries(o.seq).map(([k,v])=>{const[m,sd]=meanSd(DATA.opponents.map(x=>x.seq[k]));return `<tr><td class="tl">${k}</td>${devCell(v,m,sd)}<td style="color:#888">${fmt(m)}</td></tr>`;}).join('')}</tbody></table><p class="note">Early-down pass % by previous-play result. Avg = 14-opponent sample.</p>`;
 const dd=`<table><thead><tr><th>Dn\\Dist</th>${o.ddCols.map(c=>`<th>${c}</th>`).join('')}</tr></thead><tbody>${o.ddRows.map((r,ri)=>`<tr><td class="tl"><b>${r[0]}</b></td>${r.slice(1).map((v,ci)=>{const cnt=o.ddCount[ri][ci+1];const mut=cnt<10?'color:#999':'';return `<td style="${v==null?'':heatRYG(v)};${mut}">${v==null?'—':v}</td>`}).join('')}</tr>`).join('')}</tbody></table>`;
 const dirCell=(v,lg)=>{if(typeof v!=='number')return '<td>—</td>';const d=v-lg;const st=Math.abs(d)>=5?(d>0?'background:rgba(46,84,150,.22)':'background:rgba(216,134,33,.22)'):'';return `<td style="${st}">${fmt(v)}</td>`;};
 const dpH=['Pass split','aDOT','Deep 20+','Interm','Short<10','Middle','Perim'];
 const dirP=`<table><thead><tr>${dpH.map((h,i)=>`<th class="${i==0?'tl':''}">${h}</th>`).join('')}</tr></thead><tbody>${o.dirPass.map(r=>`<tr><td class="tl">${r[0]}</td>${r.slice(1).map((v,i)=>dirCell(v,o.dirPassLG[i])).join('')}</tr>`).join('')}<tr class="lg"><td class="tl">NFL avg</td>${o.dirPassLG.map(v=>`<td>${fmt(v)}</td>`).join('')}</tr></tbody></table>`;
 const drH=['Run split','Left','Mid','Right','Int G','OffTkl','Edge'];
 const dirR=`<table><thead><tr>${drH.map((h,i)=>`<th class="${i==0?'tl':''}">${h}</th>`).join('')}</tr></thead><tbody>${o.dirRun.map(r=>`<tr><td class="tl">${r[0]}</td>${r.slice(1).map((v,i)=>dirCell(v,o.dirRunLG[i])).join('')}</tr>`).join('')}<tr class="lg"><td class="tl">NFL avg</td>${o.dirRunLG.map(v=>`<td>${fmt(v)}</td>`).join('')}</tr></tbody></table>`;
 const fp=FPR[o.src]||FPR[o.abbr];let fpT='';
 if(fp){const zones=DATA.fieldPos.zones;
  fpT=`<table><thead><tr><th class="tl">Field zone</th><th>Pass %</th><th>Shot %</th><th>PROE</th></tr></thead><tbody>${zones.map(z=>{const cells=['pass_','shot_','proe_'].map(p=>{const k=p+z;const[m,sd]=meanSd(DATA.fieldPos.rows.map(r=>r[k]));return devCell(fp[k],m,sd);}).join('');return `<tr><td class="tl">${z}</td>${cells}</tr>`;}).join('')}</tbody></table><p class="note">Shot = deep attempt (air ≥20). Green zone = opp 21-40. Δ vs 32-team average. Green-zone shots from 25-35: <b>${fmt(fp.green2535)}%</b>.</p>`;}
 return `${eff}
 <div class="sechead o">▣ Their Offense — what the Saints D must stop ${o.proxy?`<small class="src" style="color:#dfe6f2">· data: 2025 ${o.srcName}</small>`:''}</div>
 <div class="grid2"><div>${summ}<div style="height:10px"></div>${pers}</div><div>${seq}</div></div>
 <div style="margin-top:12px"><b style="font-size:12.5px">Pass % by Down × Distance</b>${dd}</div>
 <div class="grid2" style="margin-top:12px"><div><b style="font-size:12.5px">Pass depth & location</b>${dirP}</div><div><b style="font-size:12.5px">Run direction & gap</b>${dirR}</div></div>
 <p class="note">Gaps = % of gap-charted runs; depth/location = % of attempts. Middle = between the hashes. Shaded cells deviate ≥5 pts from league average (blue above, orange below).</p>
 <div style="margin-top:12px"><b style="font-size:12.5px">Field-position behavior</b>${fpT||'<p class="note">No field-position data for this team.</p>'}</div>`;
}
// ----- Their Defense tab -----
function defHTML(o){
 const te=ET[o.abbr];
 const eff=`<div class="idrow"><span class="pill">EPA/play allowed <b>${te.deff.epa.toFixed(3)}</b> ${rkTag(rankOf(DATA.leagueEPA.teams.map(t=>t.deff.epa),te.deff.epa,false))}</span><span class="pill">Success allowed <b>${fmt(te.deff.succ)}%</b> ${rkTag(rankOf(DATA.leagueEPA.teams.map(t=>t.deff.succ),te.deff.succ,false))}</span><span class="pill">Series allowed <b>${fmt(SER[o.abbr].deff)}%</b> ${rkTag(rankOf(DATA.leagueEPA.series.map(x=>x.deff),SER[o.abbr].deff,false))}</span><span class="pill">Pass EPA <b>${te.deff.passEPA.toFixed(3)}</b></span><span class="pill">Rush EPA <b>${te.deff.rushEPA.toFixed(3)}</b></span></div>`;
 const covLab=['Man %','Zone %','1-High/MOFC %','2-High/MOFO %'],frLab=['Blitz %','Light box %','Heavy box %','Sub pkg %'];
 const cov=`<table><thead><tr><th class="tl">Coverage / Front</th><th>${o.abbr}</th><th>NFL avg</th></tr></thead><tbody>${covLab.map((l,i)=>{const[,sd]=meanSd(DATA.opponents.map(x=>x.cov?x.cov[i]:null));return `<tr><td class="tl">${l}</td>${devCell(o.cov?o.cov[i]:null,DATA.covLG[i],sd)}<td style="color:#888">${fmt(DATA.covLG[i])}</td></tr>`;}).join('')}${frLab.map((l,i)=>{const[,sd]=meanSd(DATA.opponents.map(x=>x.def2?x.def2[i]:null));return `<tr><td class="tl">${l}</td>${devCell(o.def2?o.def2[i]:null,DATA.defLG[i],sd)}<td style="color:#888">${fmt(DATA.defLG[i])}</td></tr>`;}).join('')}</tbody></table>`;
 const prCols=['Blitz% (5+ rush)','Avg Pass Rushers','Sack%','QB OOP%','Avg Box','Light Box% (<=6)','Heavy Box% (>=8)','Expl% allowed','PROE faced'];
 const dbr=DBR[o.abbr];let press='';
 if(dbr){press=`<table><thead><tr><th class="tl">Pressure & box profile</th><th>${o.abbr}</th><th>NFL avg</th></tr></thead><tbody>${prCols.map(c=>{const[,sd]=meanSd(Object.values(DBR).map(r=>r[DBI[c]]));const dec=(c==='Avg Pass Rushers'||c==='Avg Box')?2:1;return `<tr><td class="tl">${c}</td>${devCell(dbr[DBI[c]],DBLG[DBI[c]],sd,dec)}<td style="color:#888">${fmt(DBLG[DBI[c]])}</td></tr>`;}).join('')}</tbody></table><p class="note">From the defense tendency board (2025 charting). PROE faced = how pass-happy offenses play against them — a funnel indicator.</p>`;}
 const ne=ET['NO'],nu=NEU['NO'],pr=PRO['NO'];
 const noCtx=`<p class="note" style="margin-top:8px"><b>Saints O for reference:</b> EPA/play ${ne.off.epa.toFixed(3)} (${ord(rankOf(DATA.leagueEPA.teams.map(t=>t.off.epa),ne.off.epa,true))}) · neutral pass ${fmt(nu.neutralPass)}% · PROE ${pr.proe>0?'+':''}${fmt(pr.proe)}.</p>`;
 return `${eff}
 <div class="sechead d">▣ Their Defense — what the Saints O will see ${o.defNew?'· ⚠ NEW DC for 2026':''}</div>
 <div class="grid2"><div>${cov}</div><div><p class="note" style="margin-top:0">${o.defNote}</p>${noCtx}</div></div>
 <div style="margin-top:12px">${press}</div>
 ${o.align?(`<div style="margin-top:10px"><b style="font-size:12.5px">Defensive alignment vs offensive personnel</b>`+alignTable(o.align)+`<p class="note">% = defensive package deployed vs each offensive grouping (2025, all offenses). Source: Ferraiola Matching Personnel.</p></div>`):`<p class="note">vs-personnel alignment data pending for this defense.</p>`}`;
}
function alignTable(al){const grps=['11','12','13','21','10'].filter(g=>al[g]);const HH=['Off pers','Plays','Base','Nickel','Dime','Qtr','Heavy'];return `<table><thead><tr>${HH.map((h,i)=>`<th class="${i==0?'tl':''}">${h}</th>`).join('')}</tr></thead><tbody>${grps.map(g=>{const v=al[g];return `<tr><td class="tl">${g} pers</td><td>${v[0]}</td>${v.slice(1).map(x=>`<td>${x==null?'—':x}</td>`).join('')}</tr>`}).join('')}</tbody></table>`;}
// ----- Shell -----
let curOpp=null,curOTab='match';
function renderOpponents(){
 const s=$('#opponents');
 s.innerHTML=`<h2>Opponent Scouting Packages</h2><p class="lead">Saints' 2026 opponents. Matchup view scores their units against the Saints' with league ranks and auto-flagged game-plan keys; offense/defense views carry the full tendency detail. New-staff teams are proxy-matched to the new play-caller's 2025 unit.</p><div class="oppbtns" id="obtns"></div><div id="ocard"></div>`;
 const ob=$('#obtns');DATA.opponents.forEach((o,i)=>{const b=document.createElement('button');b.textContent=o.abbr;b.title=o.name;if(i==0)b.classList.add('on');b.onclick=()=>{document.querySelectorAll('#obtns button').forEach(x=>x.classList.remove('on'));b.classList.add('on');curOpp=o;drawOpp();};ob.appendChild(b);});
 curOpp=DATA.opponents[0];drawOpp();
}
function drawOpp(){
 const o=curOpp,box=$('#ocard');
 const tabs=[['match','Matchup vs Saints'],['off','Their Offense'],['def','Their Defense']];
 const tb=`<div class="subnav" style="margin-top:10px">${tabs.map(([id,lab])=>`<button class="${id===curOTab?'on':''}" data-ot="${id}">${lab}</button>`).join('')}</div>`;
 const body=curOTab==='match'?matchupHTML(o):curOTab==='off'?offHTML(o):defHTML(o);
 box.innerHTML=`<div class="card"><h2 style="margin-top:0">${o.name}</h2>
 <div class="staff">2026: HC ${o.hc} · OC ${o.oc} · DC ${o.dc}</div>
 ${o.banner?`<div class="banner">⚠ ${o.banner}</div>`:''}${tb}${body}</div>`;
 box.querySelectorAll('[data-ot]').forEach(b=>b.onclick=()=>{curOTab=b.dataset.ot;drawOpp();});
}
