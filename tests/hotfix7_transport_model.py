# Model regression for the request/result ownership and dedupe semantics.
class Transport:
    def __init__(self):
        self.active={}
    def request(self, invoking, claimed, req, token):
        if not invoking: return (False,'INVALID_ARGUMENT')
        if claimed != invoking: return (False,'OWNER_MISMATCH')
        bucket=self.active.setdefault(invoking,{})
        if req in bucket:
            if bucket[req] == token: return ('IGNORED_REPLAY',None)
            return (False,'MIGRATION_ERROR')
        bucket[req]=token
        return ('STARTED',None)
    def finish(self, owner, req, token, ok=True, err=None):
        bucket=self.active.get(owner,{})
        if bucket.get(req)!=token: return None
        del bucket[req]
        if not bucket: self.active.pop(owner,None)
        return (ok,err)

t=Transport(); tests=[]
def ex(name, cond): tests.append((name, bool(cond)))
ex('valid owner starts', t.request('nexm_factoryworks','nexm_factoryworks','1','t1')[0]=='STARTED')
ex('same request replay ignored', t.request('nexm_factoryworks','nexm_factoryworks','1','t1')[0]=='IGNORED_REPLAY')
ex('same id different token rejected', t.request('nexm_factoryworks','nexm_factoryworks','1','evil')[1]=='MIGRATION_ERROR')
ex('owner spoof rejected', t.request('other','nexm_factoryworks','2','t2')[1]=='OWNER_MISMATCH')
ex('missing invoking rejected', t.request(None,'nexm_factoryworks','3','t3')[1]=='INVALID_ARGUMENT')
ex('successful finish returns once', t.finish('nexm_factoryworks','1','t1',True,None)==(True,None))
ex('finished request cannot respond twice', t.finish('nexm_factoryworks','1','t1',True,None) is None)
# independent owners
ex('second owner independent', t.request('nexm_justice','nexm_justice','1','j1')[0]=='STARTED')
ex('second owner completes independently', t.finish('nexm_justice','1','j1',False,'DB')==(False,'DB'))
for n,v in tests: print(('[PASS] ' if v else '[FAIL] ')+n)
f=sum(not v for _,v in tests)
print(f'RESULT tests={len(tests)} pass={len(tests)-f} fail={f}')
raise SystemExit(1 if f else 0)
