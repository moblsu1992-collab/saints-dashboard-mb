// ---------- ROUTE TREE / DEPTH HEAT VISUAL ----------
const RTGEO={
 'GO':[[75,195],[75,22]],
 'POST':[[75,195],[75,85],[38,30]],
 'CORNER':[[75,195],[75,85],[112,30]],
 'DEEP OUT':[[75,195],[75,88],[136,88]],
 'IN/DIG':[[75,195],[75,98],[14,98]],
 'HITCH/CURL':[[75,195],[75,128],[67,141]],
 'SLANT':[[75,195],[75,172],[30,132]],
 'QUICK OUT':[[75,195],[75,152],[132,152]],
 'SHALLOW CROSS/DRAG':[[75,195],[75,176],[12,158]],
 'SCREEN':[[75,195],[98,186]],
 'SWING':[[75,195],[112,192],[134,180]],
 'WHEEL':[[75,195],[124,168],[124,60]],
 'TEXAS/ANGLE':[[75,195],[52,172],[88,142]]
};
const RTSHORT={'GO':'GO','POST':'POST','CORNER':'CRN','DEEP OUT':'D-OUT','IN/DIG':'DIG','HITCH/CURL':'HTCH','SLANT':'SLNT','QUICK OUT':'Q-OUT','SHALLOW CROSS/DRAG':'DRAG','SCREEN':'SCRN','SWING':'SWG','WHEEL':'WHL','TEXAS/ANGLE':'ANGL'};
function rtViz(ab,side,lev){
 const CV=DATA.coverage,FZ=DATA.fieldZones;
 const tm=CV.teams[ab],fzt=FZ.teams[ab];
 if(!tm||!tm[side]||!tm[side].rt||!tm[side].rt[lev]||!fzt)return '<p class="note">No data for this team.</p>';
 const R=tm[side].rt[lev],zonesArr=fzt[side][lev],zn=[...FZ.zones,'All'];
 const grids=zonesArr.map(z=>z&&z[10]&&z[10][0]!=null?z[10]:null);
 const atts=zonesArr.map(z=>z?z[7]:0);
 const tot=atts.reduce((s,a,i)=>grids[i]?s+a:s,0);
 let allG=null;
 if(tot>0)allG=Array.from({length:12},(_,k)=>grids.reduce((s,g,i)=>g?s+g[k]*atts[i]:s,0)/tot);
 const DEPN=['Behind LOS','0-9 yds','10-19 yds','20+ yds'],SIDN=['left','middle','right'];
 const panels=zn.map((z,zi)=>{
  const grid=zi<5?grids[zi]:allG;
  const att=zi<5?atts[zi]:tot;
  const n=R.n[zi];
  if(!grid&&!n)return `<div class="rtvp fzmute"><div class="fzh">${z}</div><p class="note">no data in this situation</p></div>`;
  const thin=n<15&&att<15;
  const yB=[[170,200],[120,170],[70,120],[10,70]];
  let cells='';
  if(grid){const mx=Math.max(...grid.map(v=>v||0),1);
   for(let dep=0;dep<4;dep++)for(let ci=0;ci<3;ci++){const v=grid[dep*3+ci];const t=(v||0)/mx;
    cells+=`<rect x="${ci*50}" y="${yB[dep][0]}" width="50" height="${yB[dep][1]-yB[dep][0]}" fill="rgba(46,84,150,${(0.03+0.5*t).toFixed(2)})"><title>${DEPN[dep]} ${SIDN[ci]}: ${v==null?'—':v.toFixed(1)}% of targets</title></rect>`;}}
  let branches='',labels='';
  if(n>=5){
   const pct=ri=>100*R.c[zi][ri]/n;
   const order=CV.routes.map((r,ri)=>[ri,pct(ri)]).sort((a,b)=>b[1]-a[1]).slice(0,5).filter(x=>x[1]>0);
   order.forEach(([ri,p],idx)=>{
    const pts=RTGEO[CV.routes[ri]];if(!pts)return;
    const w=Math.min(9,0.8+p*0.32);
    branches+=`<polyline points="${pts.map(pt=>pt.join(',')).join(' ')}" fill="none" stroke="#b58a2a" stroke-opacity="${idx<3?0.95:0.55}" stroke-width="${w.toFixed(1)}" stroke-linecap="round" stroke-linejoin="round"><title>${CV.routes[ri]}: ${p.toFixed(1)}% of routed targets</title></polyline>`;
    if(idx<3){const tip=pts[pts.length-1];
     labels+=`<text x="${Math.min(118,Math.max(3,tip[0]-12))}" y="${Math.max(9,tip[1]-5)}" font-size="8" font-weight="800" fill="#6b4f12" stroke="#fff" stroke-width="2.5" style="paint-order:stroke">${RTSHORT[CV.routes[ri]]} ${Math.round(p)}</text>`;}
   });
  }
  const los=`<line x1="0" y1="170" x2="150" y2="170" stroke="#555" stroke-dasharray="5 3" stroke-width="1"/><text x="3" y="167" font-size="6.5" fill="#888">LOS</text><text x="3" y="17" font-size="6.5" fill="#888">20+</text>`;
  return `<div class="rtvp${thin?' fzmute':''}"><div class="fzh">${z}</div><div class="fzy">${zi<5?FZYARDS[zi]+' · ':''}${n} routed tgt${thin?' · thin':''}</div><svg viewBox="0 0 150 205" style="width:100%;background:#fbfcfe;border:1px solid var(--line);border-radius:6px">${cells}${los}${branches}${labels}</svg></div>`;
 }).join('');
 return `<div class="rtv">${panels}</div><p class="note">Background heat = share of located targets by depth band × side (offense driving upward; dashed line = line of scrimmage). Gold branches = top-5 routes in that zone & situation, width ∝ usage, top-3 labeled (% of routed targets). Hover any band or branch for exact numbers. Responds to the side and score-state filters above.</p>`;
}
