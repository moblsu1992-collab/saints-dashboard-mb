"""
build_personnel.py — personnel-grouping splits for the Saints dashboard.

Joins nflverse pbp_participation (offense_personnel) to play-by-play and computes,
per team (Saints + 2026 opponents + proxy sources), per side (off = posteam, def = defteam),
per personnel grouping (backs digit = RB+FB, TE digit; e.g. 11, 12, 21, 13):
  n, usage% , dropback pass%, EPA/play, success%, deep-shot% (air>=20 of attempts),
  aDOT, run direction [L,M,R] % of located runs, target side [L,M,R] % of located attempts.

Groups with fewer than 25 team plays roll into 'Oth'. League reference computed per group.
Play filter identical to the rest of the stack: (pass==1|rush==1), downs 1-4, REG+POST.

Output: personnel.json {order:[...], teams:{AB:{off:{grp:[...]}, def:{...}}}, league:{grp:[...]}}
Group array: [n, usage, pass, epa, succ, shot, adot, [rl,rm,rr], [tl,tm,tr]]
"""
import pandas as pd, numpy as np, json, re

PBP='/sessions/wizardly-dreamy-hamilton/mnt/uploads/play_by_play_2025 (1).csv'
PART='/sessions/wizardly-dreamy-hamilton/mnt/uploads/pbp_participation_2025.csv'
HTML='index.html'

usecols=['game_id','play_id','posteam','defteam','down','pass','rush','epa','success',
         'air_yards','pass_location','run_location']
d=pd.read_csv(PBP,usecols=usecols,low_memory=False)
d=d[(d['pass'].eq(1)|d.rush.eq(1))&d.down.notna()&d.posteam.notna()]

part=pd.read_csv(PART,usecols=['nflverse_game_id','play_id','offense_personnel'])
part=part.rename(columns={'nflverse_game_id':'game_id'})

def label(s):
    if not isinstance(s,str):return None
    rb=fb=te=0
    for cnt,pos in re.findall(r'(\d+)\s*(RB|FB|TE)\b',s):
        if pos=='RB':rb=int(cnt)
        elif pos=='FB':fb=int(cnt)
        else:te=int(cnt)
    backs=rb+fb
    if backs>4 or te>4:return None      # junk/ST rows
    return f'{backs}{te}'
part['grp']=part.offense_personnel.apply(label)

m=d.merge(part[['game_id','play_id','grp']],on=['game_id','play_id'],how='left')
print('plays:',len(m),' with personnel:',m.grp.notna().sum(),
      f'({100*m.grp.notna().mean():.1f}% match)')
m=m[m.grp.notna()].copy()
LOC={'left':0,'middle':1,'right':2}
m['ploc']=m.pass_location.map(LOC);m['rloc']=m.run_location.map(LOC)

def gstats(g,total):
    n=len(g)
    r1=lambda x:round(float(x),1)
    passes=g[g['pass'].eq(1)];runs=g[g.rush.eq(1)]
    att=passes[passes.air_yards.notna()]
    lr=runs[runs.rloc.notna()];la=att[att.ploc.notna()]
    return [n,r1(100*n/total),r1(100*g['pass'].mean()),
            round(float(g.epa.mean()),3),r1(100*g.success.mean()),
            r1(100*(att.air_yards>=20).mean()) if len(att) else None,
            r1(att.air_yards.mean()) if len(att) else None,
            [r1(100*(lr.rloc==i).mean()) if len(lr) else None for i in range(3)],
            [r1(100*(la.ploc==i).mean()) if len(la) else None for i in range(3)]]

def side(sub,minN=25):
    total=len(sub)
    if total==0:return {}
    out={};small=[]
    for grp,g in sub.groupby('grp'):
        if len(g)>=minN:out[grp]=gstats(g,total)
        else:small.append(g)
    if small:
        sm=pd.concat(small)
        if len(sm)>=10:out['Oth']=gstats(sm,total)
    return dict(sorted(out.items(),key=lambda kv:-kv[1][1]))

h=open(HTML).read()
D=json.loads(re.search(r'const DATA=(\{.*?\});\n',h,re.S).group(1))
need=set(['NO'])
for o in D['opponents']:need.add(o['abbr']);need.add(o['src'])

PS={'teams':{},'league':{}}
for ab in sorted(need):
    PS['teams'][ab]={'off':side(m[m.posteam.eq(ab)]),'def':side(m[m.defteam.eq(ab)])}
PS['league']=side(m,minN=100)

js=json.dumps(PS,separators=(',',':'))
open('personnel.json','w').write(js)
print('personnel.json bytes:',len(js))
# sanity vs SumerSports aggregates already in dashboard
for o in D['opponents'][:3]:
    src=o['src'];sm=o.get('pers')
    if sm and src in PS['teams']:
        offp=PS['teams'][src]['off']
        print(o['abbr'],'(src',src+') computed 11/12:',offp.get('11',[None,None])[1],offp.get('12',[None,None])[1],
              '| SumerSports 11/12:',sm[0],sm[1])
print('NO off groups:',{k:v[1] for k,v in PS['teams']['NO']['off'].items()})
print('NO def faced:',{k:v[1] for k,v in PS['teams']['NO']['def'].items()})
