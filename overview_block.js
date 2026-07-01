// ---------- OVERVIEW (start here) ----------
function goSection(id){const idx=SECTIONS.findIndex(x=>x[0]===id);const btn=document.querySelectorAll('#nav button')[idx];if(btn)show(id,btn);}
function gotoOpp(ab){goSection('opponents');const b=[...document.querySelectorAll('#obtns button')].find(x=>x.textContent===ab);if(b)b.onclick();}
function gotoField(ab){curFZTeam=ab;renderField();goSection('field');}
function ovSaintsBullets(){
 const ne=ET['NO'];
 const offE=DATA.leagueEPA.teams.map(t=>t.off.epa),defE=DATA.leagueEPA.teams.map(t=>t.deff.epa);
 const rNO=rankOf(offE,ne.off.epa,true),rND=rankOf(defE,ne.deff.epa,false);
 const rPassD=rankOf(DATA.leagueEPA.teams.map(t=>t.deff.passEPA),ne.deff.passEPA,false);
 const rRushD=rankOf(DATA.leagueEPA.teams.map(t=>t.deff.rushEPA),ne.deff.rushEPA,false);
 const off=[],deff=[];
 off.push(`<b>${ord(rNO)} offense</b> by EPA/play (${ne.off.epa.toFixed(3)}) — every 2026 matchup starts from the premise that our offense needs schematic help.`);
 const ps=DATA.persSplits.teams['NO'];
 if(ps&&ps.off){const ent=Object.entries(ps.off).filter(([g])=>g!=='Oth');
  if(ent.length>1){const s=[...ent].sort((a,b)=>b[1][3]-a[1][3]);const bg=s[0],wg=s[s.length-1];
   off.push(`Personnel tell: our best football is in <b>${bg[0]} personnel</b> (${bg[1][3].toFixed(2)} EPA, ${bg[1][1]}% usage); <b>${wg[0]}</b> is the weak spot (${wg[1][3].toFixed(2)}).`);}}
 const cv=DATA.coverage.teams['NO'];
 if(cv&&cv.off&&Object.keys(cv.off.fam).length>1){const fe=Object.entries(cv.off.fam);
  const fs=[...fe].sort((a,b)=>b[1][2]-a[1][2]);const fb=fs[0],fw=fs[fs.length-1];
  off.push(`vs coverage: handle <b>${CVFAM[fb[0]]}</b> best (${fb[1][2].toFixed(2)} EPA), struggle most against <b>${CVFAM[fw[0]]}</b> (${fw[1][2].toFixed(2)} on ${fw[1][0]} dropbacks) — expect heavy doses of it until we prove otherwise.`);}
 if(cv&&cv.off&&cv.off.pr){const[rate,ep,ec]=cv.off.pr;const lp=DATA.coverage.league.pr;
  off.push(`Pressure allowed <b>${rate}%</b> (lg ${lp[0]}%); EPA goes from ${ec.toFixed(2)} clean to <b>${ep.toFixed(2)}</b> pressured — protection plans are weekly priority one.`);}
 deff.push(`<b>${ord(rND)} defense</b> by EPA allowed (${ne.deff.epa.toFixed(3)}) — the unit that keeps us in games. Pass D ranks ${ord(rPassD)}, run D ${ord(rRushD)}.`);
 if(cv&&cv.def&&Object.keys(cv.def.fam).length>1){const fe=Object.entries(cv.def.fam);
  const fs=[...fe].sort((a,b)=>a[1][2]-b[1][2]);const fb=fs[0],fw=fs[fs.length-1];
  deff.push(`Best call: <b>${CVFAM[fb[0]]}</b> (${fb[1][2].toFixed(2)} EPA allowed, ${fb[1][1]}% usage); most vulnerable in <b>${CVFAM[fw[0]]}</b> (${fw[1][2].toFixed(2)}).`);}
 if(cv&&cv.def&&cv.def.pr){const[rate,ep,ec]=cv.def.pr;
  deff.push(`We generate pressure on <b>${rate}%</b> of dropbacks (lg ${DATA.coverage.league.pr[0]}%); when we get home, offenses fall to ${ep.toFixed(2)} EPA — when we don't, they sit at ${ec.toFixed(2)}.`);}
 const lk=LCK['NO'];
 deff.push(`Context: <b>${lk.osW}-${lk.osL}</b> in one-score games, ${lk.toMargin>0?'+':''}${lk.toMargin} turnover margin/game, ${lk.fumRec}% fumble-recovery luck — read the record accordingly.`);
 return {off,deff,rNO,rND};
}
function renderOverview(){
 const s=$('#overview');
 const ne=ET['NO'];
 const offE=DATA.leagueEPA.teams.map(t=>t.off.epa),defE=DATA.leagueEPA.teams.map(t=>t.deff.epa);
 const {off,deff,rNO,rND}=ovSaintsBullets();
 const hol=holisticList();const hIdx=hol.findIndex(t=>t.abbr==='NO');
 const [tn,tc]=tier(hol[hIdx].h);
 // --- slate verdicts ---
 const slate=DATA.opponents.map(o=>{
  const oe=ET[o.src]||ET[o.abbr],te=ET[o.abbr];
  const rTO=rankOf(offE,oe.off.epa,true),rTD=rankOf(defE,te.deff.epa,false);
  const edge=((rTO-rND)+(rTD-rNO))/2;
  const [offK,defK]=buildKeys(o);
  const top=[...offK.map(k=>({k,side:'Their O'})),...defK.map(k=>({k,side:'Their D'}))].sort((a,b)=>Math.abs(b.k.z)-Math.abs(a.k.z))[0];
  const ho=hol.find(t=>t.abbr===o.abbr);
  return {o,rTO,rTD,edge,top,h:ho?ho.h:null};
 }).sort((a,b)=>a.edge-b.edge);
 const verdict=e=>e>=14?['Clear edge','#1e7a34']:e>=6?['Favorable','#2e7d4f']:e>-6?['Even','#6b7280']:e>-14?['Tough','#b3661a']:['Very tough','#a23b3b'];
 const rows=slate.map(x=>{
  const[vl,vc]=verdict(x.edge);
  const flags=[x.o.proxy?'proxy O':'',x.o.defNew?'new DC':''].filter(Boolean).join(' · ');
  const key=x.top?`<b>${x.side||x.top.side}:</b> ${x.top.k.lab} ${fmt(x.top.k.v)} <span class="rk" style="color:#667">(${x.top.k.z>0?'+':''}${x.top.k.z.toFixed(1)}σ)</span>`:'—';
  const d1=x.rTO-rND, d2=x.rTD-rNO;
  const cell=(d)=>`<td style="color:${d>=6?'#1e7a34':d<=-6?'#a23b3b':'#555'}">${d>0?'+':''}${d}</td>`;
  return `<tr data-go="${x.o.abbr}" style="cursor:pointer"><td class="tl"><b>${x.o.name}</b>${flags?` <small class="src">⚠ ${flags}</small>`:''}</td><td>${x.h==null?'—':x.h.toFixed(1)}</td><td>${ord(x.rTO)} vs ${ord(rND)}</td>${cell(x.rTO-rND)}<td>${ord(x.rTD)} vs ${ord(rNO)}</td>${cell(x.rTD-rNO)}<td><span class="tier" style="background:${vc}">${vl}</span></td><td class="tl" style="white-space:normal;min-width:240px;font-size:11.5px">${key}</td></tr>`;
 }).join('');
 const slateT=`<div class="scroll"><table><thead><tr><th class="tl">Opponent</th><th>Holistic</th><th>Their O vs our D</th><th>O edge</th><th>Their D vs our O</th><th>D edge</th><th>Verdict</th><th class="tl">Biggest tell</th></tr></thead><tbody>${rows}</tbody></table></div><p class="note">Sorted toughest → most favorable. Edge columns = rank gaps (their unit's league rank minus ours; <b>positive favors the Saints</b>, ±6 ≈ even). Verdict averages both. Tell = the most extreme tendency from the auto game-plan keys. <b>Click any row to open that opponent's full card.</b></p>`;
 const guide=[
  ['1 · Overview','this page — the verdicts. Everything below is the evidence.'],
  ['2 · Team Ratings','the league as a whole: 3-phase 0–100 ratings, adjustable holistic weights, benchmark detail.'],
  ['3 · League EPA','efficiency league-wide — the two-axis map, then offense / defense / QB charts, pass identity, 4th downs, luck.'],
  ['4 · Saints Self Scout','us, one click: situational tendencies, field-zone tear sheet, personnel splits, coverage & pressure profile.'],
  ['5 · Opponents','one card per 2026 opponent: Matchup (the verdict + game-plan keys), Their Offense, Their Defense.'],
  ['6 · Field Position','any team, any zone: the tear sheet and passing-volume map, filterable by score state.'],
  ['7 · Philosophy','reference: every staff, scheme and coaching lineage.']
 ].map(([a,b])=>`<li><b>${a}</b> — ${b}</li>`).join('');
 const hidden=[
  '<b>Every table sorts</b> — click a column header (click again to flip); the # column re-ranks live.',
  '<b>Side & score-state toggles</b> on Saints Self Scout and Field Position re-cut everything: tear sheet, volume map, routes.',
  '<b>Hover for exact numbers</b> — chart bars, heat cells, volume maps and delta chips all carry tooltips.',
  '<b>Raw tables hide under disclosures</b> — "View as sortable tables" beneath the passing volume map.',
  '<b>Color language:</b> gold = Saints · blue/orange = above/below league frequency · green/red = good/bad for the unit shown · row tints = a team\\'s best/worst grouping.'
 ].map(x=>`<li>${x}</li>`).join('');
 s.innerHTML=`<h2>2026 Saints Scouting — Start Here</h2>
 <p class="lead">The story runs left to right: the league as a whole → efficiency and QBs → ourselves → each opponent → the field itself. This page is the executive summary; every claim on it is computed live from the data behind the other tabs.</p>
 <div class="card"><div class="sechead">Who we are — 2025 baseline <small class="src" style="color:#dfe6f2">· holistic ${hol[hIdx].h.toFixed(1)}, ${ord(hIdx+1)} overall · <span class="tier" style="background:${tc}">${tn}</span></small></div>
 <div class="grid2"><div><div class="sechead o">Offense</div><ul class="keys">${off.map(x=>`<li>${x}</li>`).join('')}</ul></div>
 <div><div class="sechead d">Defense</div><ul class="keys">${deff.map(x=>`<li>${x}</li>`).join('')}</ul></div></div></div>
 <div class="card"><div class="sechead">The 2026 slate — matchup verdicts</div>${slateT}</div>
 <div class="card"><div class="grid2"><div><div class="sechead">How this dashboard reads</div><ul class="keys">${guide}</ul></div>
 <div><div class="sechead">Don't miss</div><ul class="keys">${hidden}</ul></div></div></div>`;
 s.querySelectorAll('[data-go]').forEach(r=>r.onclick=()=>gotoOpp(r.dataset.go));
}
