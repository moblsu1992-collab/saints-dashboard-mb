"""
build_fieldzones.py — field-zone tear-sheet dataset for the Saints dashboard.

Computes, for every needed team (Saints + 2026 opponents + proxy sources), per side
(offense = posteam, defense = defteam), per leverage state, per field zone:
  n plays, dropback pass%, EPA/play, pass EPA, rush EPA, success%, shot% (air>=20 of attempts),
  located-attempt count, blitz% (5+ rushers, FTN, defense view only),
  run direction [L,M,R] % of located runs,
  target grid 4x3: depth (BLOS / Short 0-9 / Int 10-19 / Deep 20+) x location (L,M,R), % of located attempts.

Zones (yardline_100): Backed Up >=90 · Own 60-89 · Midfield 41-59 · Green 21-40 · Red 1-20
  (validated to exactly reproduce the dashboard's existing fieldPos numbers).
Leverage (pre-snap score_differential, offense perspective):
  all · one (|diff|<=8) · trail (<=-9) · lead (>=9).
Play filter: (pass==1 | rush==1) & down in 1-4, REG+POST — same as the rest of the stack.

Output: fieldzones.json  {zones, levs, teams:{ABBR:{off:{lev:[5 zone arrays]},def:{...}}}, league:{lev:[5]}}
Zone array (compact): [n, pass, epa, pEpa, rEpa, succ, shot, att, blitz, [L,M,R], [12 grid vals]]
"""
import pandas as pd, numpy as np, json, re

PBP='/sessions/wizardly-dreamy-hamilton/mnt/uploads/play_by_play_2025 (1).csv'
FTN='/sessions/wizardly-dreamy-hamilton/mnt/uploads/ftn_charting_2025 (1).csv'
HTML='index.html'

usecols=['game_id','play_id','posteam','defteam','yardline_100','down','pass','rush',
         'qb_dropback','epa','success','air_yards','pass_location','run_location','score_differential']
df=pd.read_csv(PBP,usecols=usecols,low_memory=False)
d=df[(df['pass'].eq(1)|df['rush'].eq(1))&df.down.notna()&df.posteam.notna()&df.yardline_100.notna()].copy()

ftn=pd.read_csv(FTN,usecols=['nflverse_game_id','nflverse_play_id','n_pass_rushers'])
ftn=ftn.rename(columns={'nflverse_game_id':'game_id','nflverse_play_id':'play_id'})
d=d.merge(ftn,on=['game_id','play_id'],how='left')

d['zone']=np.select([d.yardline_100>=90,d.yardline_100>=60,d.yardline_100>=41,d.yardline_100>=21],
                    [0,1,2,3],default=4)
d['lev_one']=d.score_differential.abs()<=8
d['lev_trail']=d.score_differential<=-9
d['lev_lead']=d.score_differential>=9
d['depth']=np.select([d.air_yards<0,d.air_yards<10,d.air_yards<20],[0,1,2],default=3)
d.loc[d.air_yards.isna(),'depth']=-1
LOC={'left':0,'middle':1,'right':2}
d['ploc']=d.pass_location.map(LOC)
d['rloc']=d.run_location.map(LOC)
d['blitz5']=(d.n_pass_rushers>=5)
d['has_pr']=d.n_pass_rushers.notna()&d['pass'].eq(1)

ZONES=['Backed Up','Own','Midfield','Green','Red']
LEVS=[('all',None),('one','lev_one'),('trail','lev_trail'),('lead','lev_lead')]

def zstats(g,blitz):
    n=len(g)
    if n==0: return None
    r1=lambda x:None if x is None or (isinstance(x,float) and np.isnan(x)) else round(float(x),1)
    passes=g[g['pass'].eq(1)];runs=g[g.rush.eq(1)]
    att=passes[passes.air_yards.notna()]
    out=[n,r1(100*g['pass'].mean()),
         round(float(g.epa.mean()),3),
         round(float(passes.epa.mean()),3) if len(passes) else None,
         round(float(runs.epa.mean()),3) if len(runs) else None,
         r1(100*g.success.mean()),
         r1(100*(att.air_yards>=20).mean()) if len(att) else None,
         int(len(att))]
    if blitz:
        pr=g[g.has_pr]
        out.append(r1(100*pr.blitz5.mean()) if len(pr) else None)
    else:
        out.append(None)
    lr=runs[runs.rloc.notna()]
    out.append([r1(100*(lr.rloc==i).mean()) if len(lr) else None for i in range(3)])
    la=att[att.ploc.notna()&(att.depth>=0)]
    grid=[]
    for dep in range(4):
        for loc in range(3):
            grid.append(r1(100*((la.depth==dep)&(la.ploc==loc)).mean()) if len(la) else None)
    out.append(grid)
    return out

def teamSide(sub,blitz):
    res={}
    for lev,col in LEVS:
        s=sub if col is None else sub[sub[col]]
        res[lev]=[zstats(s[s.zone.eq(z)],blitz) for z in range(5)]
    return res

# teams needed: NO + opponents (off uses src, def uses abbr)
h=open(HTML).read()
D=json.loads(re.search(r'const DATA=(\{.*?\});\n',h,re.S).group(1))
need=set(['NO'])
for o in D['opponents']:
    need.add(o['abbr']);need.add(o['src'])
print('teams:',sorted(need))

FZ={'zones':ZONES,'levs':[l for l,_ in LEVS],'teams':{},'league':{}}
for ab in sorted(need):
    FZ['teams'][ab]={'off':teamSide(d[d.posteam.eq(ab)],False),
                     'def':teamSide(d[d.defteam.eq(ab)],True)}
FZ['league']=teamSide(d,True)   # league aggregate (same plays either side)

js=json.dumps(FZ,separators=(',',':'))
open('fieldzones.json','w').write(js)
print('fieldzones.json bytes:',len(js))
# sanity: NO red zone pass% all-lev should match fieldPos pass_Red
fp={r['abbr']:r for r in D['fieldPos']['rows']}
print('NO red pass:',FZ['teams']['NO']['off']['all'][4][1],'expected',fp['NO']['pass_Red'])
print('ATL green pass:',FZ['teams']['ATL']['off']['all'][3][1],'expected',fp['ATL']['pass_Green'])
print('NO off one-score zones n:',[z[0] for z in FZ['teams']['NO']['off']['one']])
print('NO def all blitz by zone:',[z[8] for z in FZ['teams']['NO']['def']['all']])
