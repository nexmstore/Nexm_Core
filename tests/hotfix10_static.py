from pathlib import Path
import hashlib, re, sys
root=Path(__file__).resolve().parents[1]
checks=[]
def c(name, cond):
    checks.append((name,bool(cond)))

fx=(root/'fxmanifest.lua').read_text()
imp=(root/'import.lua').read_text()
const=(root/'shared/constants.lua').read_text()
tr=(root/'server/public_db_transport.lua').read_text()

version_match = re.search(r"^version '([^']+)'", fx, re.M)
const_version = re.search(r"VERSION = '([^']+)'", const)
build_match = re.search(r"nexm_build '([^']+)'", fx)
const_build = re.search(r"BUILD_ID = '([^']+)'", const)
c('current version identity consistent', bool(version_match and const_version and version_match.group(1) == const_version.group(1)))
c('current build id consistent', bool(build_match and const_build and build_match.group(1) == const_build.group(1) and build_match.group(1) in imp))
c('public db transport in manifest', "'server/public_db_transport.lua'" in fx)
c('transport loads after database', fx.index("'server/database.lua'") < fx.index("'server/public_db_transport.lua'") < fx.index("'server/migrations.lua'"))
c('server local request event', "AddEventHandler(REQUEST_EVENT" in tr and 'RegisterNetEvent' not in tr)
c('server local result event', "TriggerEvent(RESULT_EVENT" in tr)
c('owner derived/validated', 'GetInvokingResource' in tr and 'claimedOwner' in tr and 'invokingOwner' in tr)
c('resource stop cancels pending result', "AddEventHandler('onResourceStop'" in tr and 'active[key] = nil' in tr)
c('internal DB executes in Core thread', 'CreateThread(function()' in tr and 'DB.Query' in tr and 'DB.Update' in tr)
for method, op in [('Query','query'),('Single','single'),('Scalar','scalar'),('Insert','insert'),('Update','update'),('Transaction','transaction')]:
    c(f'import proxies DB.{method}', f'publicFacade.DB.{method} = function' in imp and f"invokePublicDb('{op}'" in imp)
c('consumer request has no callback function', 'TriggerEvent(PUBLIC_DB_REQUEST_EVENT, payload)' in imp and 'payload.callback' not in imp)
c('consumer result deferred', 'deferResolvePromise(pending.promise, payload)' in imp)
c('transaction keeps false,error contract', "if operation == 'transaction' then return false, err end" in imp)
c('getter keeps nil,error contract', 'return nil, err' in imp)
c('migration runner unchanged from hotfix.9 baseline', hashlib.sha256((root/'server/migrations.lua').read_bytes()).hexdigest() == '3e7aa01ca20ce688940bb05741060e195240235cdbee099f39bb39379168f261')
c('internal DB unchanged from hotfix.9 baseline', hashlib.sha256((root/'server/database.lua').read_bytes()).hexdigest() == '5bd7a22b1efdbb06cb2d9449ec7a6b222afe1b421f9cc9ab78bc5788fa2575c4')
c('JS DB bridge unchanged from hotfix.9 baseline', hashlib.sha256((root/'server/db_bridge.js').read_bytes()).hexdigest() == '920481a8fd6f00d23a70740c2b4901cf081adbe8a8af5968b1dedf56aa5ecf2e')
c('no FactoryWorks files in Core package', not any('factoryworks' in str(p).lower() for p in root.rglob('*')))

passed=sum(v for _,v in checks); failed=len(checks)-passed
for name,ok in checks: print(('PASS' if ok else 'FAIL'), name)
print(f'TOTAL={len(checks)} PASS={passed} FAIL={failed}')
sys.exit(1 if failed else 0)
