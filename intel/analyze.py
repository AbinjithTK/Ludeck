import json
p=r'C:\Users\user\.kiro\crew\workspace\shipaton\data\projects.json'
d=json.load(open(p,encoding='utf-8'))
print('TOTAL',len(d))
def stores(links):
    a=any('apps.apple.com' in (l.get('url') or '') for l in links)
    g=any('play.google.com' in (l.get('url') or '') for l in links)
    return a,g
print('=== ONESIGNAL ===')
for x in d:
    bw=[b.lower() for b in x.get('built_with',[])]
    if 'onesignal' in bw:
        a,g=stores(x.get('links',[]))
        print(x['name'],'| likes=',x['likes'],'| apple=',a,'play=',g)
print()
print('=== KMP / COMPOSE-MP ===')
for x in d:
    bw=[b.lower() for b in x.get('built_with',[])]
    if 'kotlin-multiplatform' in bw or 'compose-multiplatform' in bw:
        a,g=stores(x.get('links',[]))
        tags=[t for t in ('kotlin-multiplatform','compose-multiplatform') if t in bw]
        print(x['name'],'|',','.join(tags),'| likes=',x['likes'],'| apple=',a,'play=',g)
