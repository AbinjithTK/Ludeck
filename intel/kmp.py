import json,re
p=r'C:\Users\user\.kiro\crew\workspace\shipaton\data\projects.json'
d=json.load(open(p,encoding='utf-8'))
byname={x['name']:x for x in d}

# FlyRight extra: retention segments / OneSignal
for t in ['FlyRight: Flight Tracker']:
    desc=byname[t]['description']
    for m in re.finditer('OneSignal',desc):
        s=max(0,m.start()-60); e=min(len(desc),m.end()+320)
        print('FLYRIGHT:',desc[s:e].replace(chr(10),' '));print()

# KMP both-store finalists - grab cross-platform / shared / polish quotes
kmp=['Vocabloot','Boxlet — Daily Visual Journal','OnSkillDemand','Machine Elements','QuestLog','Grovia','Heavyday','Woodworking Designs','Oneiric Diary','Clipzy','Add One Thing','Cohesive']
for t in kmp:
    x=byname.get(t)
    if not x: print('MISSING',t);continue
    desc=x['description']
    print('#####',t,'| likes',x['likes'],'| chars',x['description_chars'])
    for kw in ['shared','both platform','iOS and Android','consistent','polished','commonMain','identical','93%','same ']:
        m=re.search(re.escape(kw),desc,re.I)
        if m:
            s=max(0,m.start()-120); e=min(len(desc),m.end()+140)
            print('   [',kw,']',desc[s:e].replace(chr(10),' '))
    print()
