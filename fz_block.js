// ---------- FIELD-ZONE TEAR SHEET ----------
const FZSTATE={opp:{side:'off',lev:'all'},saints:{side:'off',lev:'all'}};
const FZLEVS=[['all','All situations'],['one','One-score game'],['trail','Trailing 9+'],['lead','Leading 9+']];
const FZYARDS=['Own 1-10','Own 11-40','Own 41 → Opp 42','Opp 21-40','Opp 1-20'];
const FZW=[10,30,19,20,20];
function fzStrip(){
 const W=720,H=42,EZ=26,sc=(W-2*EZ)/100;let x=EZ;
 const cols=['#e3dbd0','#d2e2d2','#dfe9df','#cfe0cf','#dcc9c9'],labels=['BACKED UP','OWN','MIDFIELD','GREEN','RED'];
 let rects='',ltxt='';
 FZW.forEach((w,i)=>{rects+=`<rect x="${x.toFixed(1)}" y="6" width="${(w*sc).toFixed(1)}" height="${H-12}" fill="${cols[i]}" stroke="#9fb59f" stroke-width="0.6"/>`;ltxt+=`<text x="${(x+w*sc/2).toFixed(1)}" y="${H/2+3}" text-anchor="middle" font-size="8.5" font-weight="700" fill="#33503f">${labels[i]}</text>`;x+=w*sc;});
 let ticks='';for(let yd=10;yd<100;yd+=10){const tx=EZ+yd*sc;ticks+=`<line x1="${tx.toFixed(1)}" y1="8" x2="${tx.toFixed(1)}" y2="${H-8}" stroke="#fff" stroke-width="1"/>`;}
 return `<svg viewBox="0 0 ${W} ${H}" style="width:100%;max-width:980px;display:block;margin:2px 0 8px"><rect x="0" y="6" width="${EZ}" height="${H-12}" fill="#1f3864" rx="2"/><rect x="${W-EZ}" y="6" width="${EZ}" height="${H-12}" fill="#a23b3b" rx="2"/>${rects}${ticks}${ltxt}<text x="${W-EZ-4}" y="${H-1}" text-anchor="end" font-size="8.5" fill="#667">drive direction →</text></svg>`;
}
function fzDelta(v,lg,inv,dec){if(v==null||lg==null)return '';const d=v-lg;const good=inv?d<0:d>0;const thin=dec===2?0.02:1.5;const c=Math.abs(d)<thin?'#888':good?'#1e7a34':'#a23b3b';return `<span class="fzd" style="color:${c}">${d>=0?'+':''}${d.toFixed(dec)}</span>`;}
function fzDevN(v,lg,dec=1){if(v==null||lg==null)return '';const d=v-lg;const c=Math.abs(d)<1.5?'#888':d>0?'#2e5496':'#b06a10';return `<span class="fzd" style="color:${c}">${d>=0?'+':''}${d.toFixed(dec)}</span>`;}
function fzZone(zi,Z,L,side){
 const name=DATA.fieldZones.zones[zi];
 if(!Z)return `<div class="fzz fzmute"><div class="fzh">${name}</div><div class="fzy">${FZYARDS[zi]}</div><p class="note">no plays in this situation</p></div>`;
 const [n,pass,epa,pe,re,succ,shot,att,bz,run,grid]=Z;
 const lpass=L?L[1]:null,lepa=L?L[2]:null,lshot=L?L[6]:null,lbz=L?L[8]:null;
 const mute=n<20?' fzmute':'';
 const runPct=pass==null?null:Math.round((100-pass)*10)/10;
 const bar=pass==null?'':`<div class="fzbar"><div class="p" style="width:${pass}%"></div><div class="r" style="width:${runPct}%"></div></div><div class="fzm" style="display:flex;justify-content:space-between"><span>Pass <b>${pass}%</b>${fzDevN(pass,lpass)}</span><span>Run <b>${runPct}%</b></span></div>`;
 const epaRow=`<div class="fzm">EPA/play <b>${epa==null?'—':epa.toFixed(2)}</b>${fzDelta(epa,lepa,side==='def',2)} · Succ <b>${succ==null?'—':succ+'%'}</b></div>`;
 const pr=`<div class="fzm">Pass EPA <b>${pe==null?'—':pe.toFixed(2)}</b> · Run EPA <b>${re==null?'—':re.toFixed(2)}</b></div>`;
 const shotRow=`<div class="fzm">Deep shot <b>${shot==null?'—':shot+'%'}</b>${fzDevN(shot,lshot)}${side==='def'?` · Blitz <b>${bz==null?'—':bz+'%'}</b>${fzDevN(bz,lbz)}`:''}</div>`;
 const rd=run&&run[0]!=null?`<div class="fzm" style="margin-top:5px"><span class="fzlab">Run direction ${side==='def'?'faced':''}</span><div class="fzrun">${['L','M','R'].map((l,i)=>`<div class="fzrc"><div class="fzrb" style="height:${Math.max(3,(run[i]||0)*0.55).toFixed(1)}px"></div>${l} ${run[i]==null?'—':Math.round(run[i])}</div>`).join('')}</div></div>`:'';
 let g='';
 if(grid&&grid[0]!=null&&att>0){
  const mx=Math.max(...grid.filter(x=>x!=null),1);
  const rowsOrd=[3,2,1,0],names=['BLOS','0-9','10-19','20+'];
  g=`<div class="fzm" style="margin-top:5px"><span class="fzlab">Targets — depth × side${side==='def'?' (faced)':''}</span><div class="fzgw${att<12?' fzmute':''}"><div class="fzgr"><span></span><span style="color:#6b7280;font-weight:700">L</span><span style="color:#6b7280;font-weight:700">M</span><span style="color:#6b7280;font-weight:700">R</span></div>${rowsOrd.map(ri=>`<div class="fzgr"><span class="fzgl">${names[ri]}</span>${[0,1,2].map(ci=>{const v=grid[ri*3+ci];const t=v==null?0:v/mx;return `<span class="fzg" style="background:rgba(46,84,150,${(0.06+0.55*t).toFixed(2)});${t>0.55?'color:#fff':''}">${v==null?'—':Math.round(v)}</span>`;}).join('')}</div>`).join('')}</div>${att<12?'<span class="fzy">thin sample ('+att+' located att)</span>':''}</div>`;
 }
 return `<div class="fzz${mute}"><div class="fzh">${name}</div><div class="fzy">${FZYARDS[zi]} · <b>${n}</b> plays${n<20?' · small sample':''}</div>${bar}${epaRow}${pr}${shotRow}${rd}${g}</div>`;
}
function fzPanel(ab,side,lev,proxyNote){
 const FZ=DATA.fieldZones;const tm=FZ.teams[ab];
 if(!tm)return '<p class="note">No field-zone data for this team.</p>';
 const rows=tm[side][lev],lg=FZ.league[lev];
 return `${fzStrip()}<div class="fz">${rows.map((z,i)=>fzZone(i,z,lg[i],side)).join('')}</div><p class="note">${FZLEVS.find(x=>x[0]===lev)[1]}${proxyNote||''} · Δ = vs league average, same zone & situation. EPA Δ green/red = better/worse for ${side==='def'?'this defense':'this offense'}; blue/orange Δ = above/below league frequency. Targets = % of located attempts (depth: BLOS = behind line of scrimmage). Greyed zone = under 20 plays; greyed grid = under 12 located attempts.</p>`;
}
function fzControls(key,offLab,defLab){
 const st=FZSTATE[key];
 const sideB=[['off',offLab],['def',defLab]].map(([id,lab])=>`<button data-fzside="${id}" data-fzkey="${key}" class="${st.side===id?'on':''}">${lab}</button>`).join('');
 const levB=FZLEVS.map(([id,lab])=>`<button data-fzlev="${id}" data-fzkey="${key}" class="${st.lev===id?'on':''}">${lab}</button>`).join('');
 return `<div class="subnav" style="margin:10px 0 6px">${sideB}<span style="flex-basis:100%;height:0"></span>${levB}</div>`;
}
function bindFZ(box,rerender){
 box.querySelectorAll('[data-fzside]').forEach(b=>b.onclick=()=>{FZSTATE[b.dataset.fzkey].side=b.dataset.fzside;rerender();});
 box.querySelectorAll('[data-fzlev]').forEach(b=>b.onclick=()=>{FZSTATE[b.dataset.fzkey].lev=b.dataset.fzlev;rerender();});
}
function fzOppHTML(o){
 const st=FZSTATE.opp;
 const ab=st.side==='off'?(o.src||o.abbr):o.abbr;
 const proxy=st.side==='off'&&o.proxy?` · ⚠ offense proxied: 2025 ${o.srcName}`:'';
 return fzControls('opp','Their Offense','Their Defense')+fzPanel(ab,st.side,st.lev,proxy);
}
