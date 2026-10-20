# Model the hotfix.10 owner/request lifecycle without FiveM runtime dependencies.
class CoreTransport:
    def __init__(self):
        self.active={}; self.results=[]; self.started=set()
    def start(self, owner): self.started.add(owner)
    def stop(self, owner):
        self.started.discard(owner)
        for k in list(self.active):
            if k[0]==owner: self.active.pop(k,None)
    def request(self, owner, rid, token):
        k=(owner,rid)
        if k in self.active: return False
        self.active[k]=token; return True
    def finish(self, owner, rid, token, result):
        k=(owner,rid)
        if self.active.get(k)!=token: return False
        self.active.pop(k,None)
        if owner not in self.started: return False
        self.results.append((owner,rid,result)); return True

def expect(name, cond, out): out.append((name,bool(cond)))
R=[]; t=CoreTransport(); owner='nexm_factoryworks'
t.start(owner)
expect('old request accepted', t.request(owner,'old','tok-old'), R)
t.stop(owner)
expect('stop clears old pending', (owner,'old') not in t.active, R)
t.start(owner)
expect('old completion orphaned after restart', not t.finish(owner,'old','tok-old',123) and not t.results, R)
expect('new request accepted independently', t.request(owner,'new','tok-new'), R)
expect('new completion delivered', t.finish(owner,'new','tok-new',456) and t.results==[(owner,'new',456)], R)
for n,ok in R: print(('PASS' if ok else 'FAIL'),n)
print(f'TOTAL={len(R)} PASS={sum(v for _,v in R)} FAIL={sum(not v for _,v in R)}')
raise SystemExit(1 if any(not v for _,v in R) else 0)
