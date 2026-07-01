"""
build_coverage.py — coverage / pressure / route-by-zone dataset for the Saints dashboard.

From nflverse pbp_participation tags joined to play-by-play (downs 1-4, pass|rush):
 - Man/Zone + coverage-family splits on tagged dropbacks:
     [n, share%, EPA/play, success%, aDOT, deep% (air>=20 of known-air attempts)]
   offense side = what that offense FACED and did against it; defense side = what that defense RAN.
 - Pressure (dropbacks with was_pressure tag): [pressure rate%, EPA when pressured, EPA clean, avg time-to-throw]
 - Route distribution by field zone (targeted route per play): 13 routes x (5 zones + All),
   % of that zone's routed targets, plus per-zone target counts.

Output: coverage.json
 {routes:[13], fams:[...], teams:{AB:{off:{mz,fam,pr,rt},def:{...}}}, league:{mz,fam,pr,rt}}
"""
import pandas as pd, numpy as np, json, re

PBP='/sessions/wizardly-dreamy-hamilton/mnt/uploads/play_by_play_2025 (1).csv'
PART='/sessions/wizardly-dreamy-hamilton/mnt/uploads/pbp_participation_2025.csv'
HTML='index.html'

d=pd.read_csv(PBP,usecols=['game_id','play_id','posteam','defteam','down','pass','rush',
                           'epa','success','air_yards','yardline_100','score_differential'],low_memory=False)
d=d[(d['pass'].eq(1)|d.rush.eq(1))&d.down.notna()&d.posteam.notna()]
part=pd.read_csv(PART,usecols=['nflverse_game_id','play_id','route','defense_man_zone_type',
                               'defense_coverage_type','was_pressure','time_to_throw'])
part=part.rename(columns={'nflverse_game_id':'game_id'})
m=d.merge(part,on=['game_id','play_id'],how='left')
m['zone']=np.select([m.yardline_100>=90,m.yardline_100>=60,m.yardline_100>=41,m.yardline_100>=21],
                    [0,1,2,3],default=4)
m['lev_one']=m.score_differential.abs()<=8
m['lev_trail']=m.score_differential<=-9
m['lev_lead']=m.score_differential>=9
LEVS=[('all',None),('one','lev_one'),('trail','lev_trail'),('lead','lev_lead')]

ROUTES=['QUICK OUT','HITCH/CURL','GO','SCREEN','IN/DIG','DEEP OUT','SHALLOW CROSS/DRAG',
        'SLANT','POST','SWING','CORNER','WHEEL','TEXAS/ANGLE']
FAMS=['COVER_3','COVER_1','COVER_2','COVER_4','COVER_6','2_MAN','COVER_0','COVER_9']
r1=lambda x:None if x is None or (isinstance(x,float) and np.isnan(x)) else round(float(x),1)

def covStats(g,total):
    n=len(g)
    if n<25:return None
    att=g[g.air_yards.notna()]
    return [n,r1(100*n/total),round(float(g.epa.mean()),3),r1(100*g.success.mean()),
            r1(att.air_yards.mean()) if len(att) else None,
            r1(100*(att.air_yards>=20).mean()) if len(att) else None]

def sideStats(sub):
    out={}
    db=sub[sub['pass'].eq(1)]
    tagged=db[db.defense_man_zone_type.notna()]
    tot=len(tagged)
    mz={}
    if tot>=50:
        man=covStats(tagged[tagged.defense_man_zone_type.eq('MAN_COVERAGE')],tot)
        zon=covStats(tagged[tagged.defense_man_zone_type.eq('ZONE_COVERAGE')],tot)
        if man:mz['Man']=man
        if zon:mz['Zone']=zon
    fam={}
    famtag=db[db.defense_coverage_type.notna()]
    ft=len(famtag)
    if ft>=50:
        for f in FAMS:
            s=covStats(famtag[famtag.defense_coverage_type.eq(f)],ft)
            if s:fam[f]=s
    out['mz']=mz;out['fam']=dict(sorted(fam.items(),key=lambda kv:-kv[1][1]))
    prd=db[db.was_pressure.notna()]
    if len(prd)>=50:
        pr=prd[prd.was_pressure.eq(True)];cl=prd[prd.was_pressure.eq(False)]
        ttt=prd[prd.time_to_throw.notna()]
        out['pr']=[r1(100*len(pr)/len(prd)),
                   round(float(pr.epa.mean()),3) if len(pr) else None,
                   round(float(cl.epa.mean()),3) if len(cl) else None,
                   round(float(ttt.time_to_throw.mean()),2) if len(ttt) else None]
    else:out['pr']=None
    # routes: raw counts per leverage state x zone (percentages computed client-side)
    rt=sub[sub.route.notna()]
    rtout={}
    for lev,col in LEVS:
        s=rt if col is None else rt[rt[col]]
        mats=[];ns=[]
        for zi in list(range(5))+[None]:
            z=s if zi is None else s[s.zone.eq(zi)]
            ns.append(int(len(z)))
            mats.append([int((z.route.eq(r)).sum()) for r in ROUTES])
        rtout[lev]={'c':mats,'n':ns}
    out['rt']=rtout
    return out

h=open(HTML).read()
D=json.loads(re.search(r'const DATA=(\{.*?\});\n',h,re.S).group(1))
need=set(['NO'])
for o in D['opponents']:need.add(o['abbr']);need.add(o['src'])

CV={'routes':ROUTES,'fams':FAMS,'teams':{},'league':{}}
for ab in sorted(need):
    CV['teams'][ab]={'off':sideStats(m[m.posteam.eq(ab)]),'def':sideStats(m[m.defteam.eq(ab)])}
CV['league']=sideStats(m)

js=json.dumps(CV,separators=(',',':'))
open('coverage.json','w').write(js)
print('coverage.json bytes:',len(js))
print('league mz:',CV['league']['mz'])
print('league pr:',CV['league']['pr'])
print('NO off fam:',{k:v[1] for k,v in CV['teams']['NO']['off']['fam'].items()})
print('NO def fam:',{k:v[1] for k,v in CV['teams']['NO']['def']['fam'].items()})
rtall=CV['teams']['NO']['off']['rt']['all'];tot=rtall['n'][5]
print('NO off route all-zone top5:',sorted(zip(ROUTES,[round(100*c/tot,1) for c in rtall['c'][5]]),key=lambda x:-x[1])[:5])
rt1=CV['teams']['NO']['off']['rt']['one'];tot1=rt1['n'][5]
print('NO off route one-score top5:',sorted(zip(ROUTES,[round(100*c/tot1,1) for c in rt1['c'][5]]),key=lambda x:-x[1])[:5])
