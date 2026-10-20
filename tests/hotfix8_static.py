from pathlib import Path
import re, sys
root=Path(__file__).resolve().parents[1]
db=(root/'server/database.lua').read_text()
imp=(root/'import.lua').read_text()
mt=(root/'server/migration_transport.lua').read_text()
mig=(root/'server/migrations.lua').read_text()
fx=(root/'fxmanifest.lua').read_text()
const=(root/'shared/constants.lua').read_text()
checks=[]
def c(n,v): checks.append((n,bool(v)))
c('version hotfix.8', "version '1.0.0-rc.1.hotfix.8'" in fx and "VERSION = '1.0.0-rc.1.hotfix.8'" in const)
c('build id consistent', all('mvp_rc1_deferred_db_resume_c91e4b27' in x for x in [fx,const,imp]))
c('callback errors enabled', "mysql_option 'return_callback_errors'" in fx)
cb=re.search(r'method\(sql, params, function\(result, callbackErr\)(.*?)\n\s*end\)', db, re.S)
body=cb.group(1) if cb else ''
c('db callback found', cb is not None)
c('db callback defers resume', "SetTimeout(0, function()" in body and 'p:resolve(envelope)' in body)
c('db callback no direct pre-defer resolve', body.find('p:resolve(envelope)') > body.find('SetTimeout(0, function()'))
c('db Await remains outside protected call', 'local envelope = Citizen.Await(p)' in db and not re.search(r'pcall\s*\(\s*Citizen\.Await', db))
handler=re.search(r'AddEventHandler\(MIGRATION_RUN_RESULT_EVENT, function\(payload\)(.*?)\n\s*end\)', imp, re.S)
hbody=handler.group(1) if handler else ''
c('migration result handler found', handler is not None)
c('migration result defers consumer resume', "SetTimeout(0, function()" in hbody and 'pending.promise:resolve(envelope)' in hbody)
c('migration transport still server-local', 'RegisterNetEvent' not in re.sub(r'--[^\n]*','',mt))
c('checksum guard preserved', 'MIGRATION_CHECKSUM_MISMATCH' in mig)
c('duplicate run guard preserved', 'if running[resource] then' in mig)
c('cleanupPending preserved', 'cleanupPending[resource]' in mig)
c('applied SQL unchanged', 'SELECT `migration`, `checksum` FROM `nexm_migrations` WHERE `resource` = ?' in mig)
c('bookkeeping SQL unchanged', 'INSERT INTO `nexm_migrations` (`resource`, `migration`, `checksum`) VALUES (?, ?, ?)' in mig)
for n,v in checks: print(('[PASS] ' if v else '[FAIL] ')+n)
fail=sum(not v for _,v in checks)
print(f'RESULT tests={len(checks)} pass={len(checks)-fail} fail={fail}')
sys.exit(1 if fail else 0)
