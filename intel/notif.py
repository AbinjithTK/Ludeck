import json,re
p=r'C:\Users\user\.kiro\crew\workspace\shipaton\data\projects.json'
d=json.load(open(p,encoding='utf-8'))
byname={x['name']:x for x in d}
targets=['Homeworld: Chores, Together','Add One Thing','FlyRight: Flight Tracker','NextSay','Petame','StoryClub — Stories that belong to your child','Cadge','Third Eye: AI Chat Analyzer','Itino: Plan Trips Smarter','VitaCircle','Birdwatching with Robin','PushRank: Push Up Counter Game','Bite Club - Family Meal Planner','LearnSnap','Doorman','Riverside Files - Idle Tycoon','Rehearso: Leadership Coach','Outside','Japatan: Learn Japanese & JLPT (N5–N1)']
for t in targets:
    x=byname.get(t)
    if not x: 
        print('MISSING',t); continue
    desc=x['description']
    # find sentences mentioning notification/onesignal/push/reminder/alert
    print('#####',t,'| likes',x['likes'])
    for kw in ['onesignal','notif','push','reminder','alert']:
        for m in re.finditer(kw,desc,re.I):
            s=max(0,m.start()-160); e=min(len(desc),m.end()+160)
            print('  ...',desc[s:e].replace(chr(10),' '),'...')
            break
    print()
