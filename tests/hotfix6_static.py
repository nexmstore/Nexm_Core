from pathlib import Path
import re, sys
root=Path(__file__).resolve().parents[1]
mig=(root/'server/migrations.lua').read_text()
db=(root/'server/database.lua').read_text()
fx=(root/'fxmanifest.lua').read_text()
const=(root/'shared/constants.lua').read_text()
imp=(root/'import.lua').read_text()

checks=[]
def check(name, cond): checks.append((name,bool(cond)))

run=re.search(r'function Migrations\.Run\(resource\)(.*?)\nend\n\nfunction Migrations\.RunCore',mig,re.S)
check('Migrations.Run found', run is not None)
body=run.group(1) if run else ''
# Strip comments for protected-call assertions.
body_code=re.sub(r'--[^\n]*','',body)
db_code=re.sub(r'--[^\n]*','',db)
check('no xpcall in Migrations.Run', 'xpcall(' not in body_code)
check('no pcall wrapping runInternal', not re.search(r'pcall\s*\([^\n]*runInternal|pcall\s*\(\s*function\s*\([^)]*\).*runInternal',body_code,re.S))
check('runInternal called directly', 'local result, runErr = runInternal(resource)' in body)
check('running guard preserved', 'if running[resource] then' in body)
check('finishRun after runInternal', body.find('runInternal(resource)') < body.find('finishRun(resource)'))
check('cleanupPending preserved', 'cleanupPending[resource]' in mig and 'registry[resource] = nil' in mig)
check('checksum mismatch preserved', 'MIGRATION_CHECKSUM_MISMATCH' in mig)
check('applied SELECT unchanged', 'SELECT `migration`, `checksum` FROM `nexm_migrations` WHERE `resource` = ?' in mig)
check('tracking INSERT unchanged', 'INSERT INTO `nexm_migrations` (`resource`, `migration`, `checksum`) VALUES (?, ?, ?)' in mig)
check('no pcall Citizen.Await', not re.search(r'pcall\s*\(\s*Citizen\.Await',db_code))
check('direct Citizen.Await', 'local envelope = Citizen.Await(p)' in db)
check('callback errors remain enabled', "mysql_option 'return_callback_errors'" in fx)
check('version hotfix.6 consistent', "version '1.0.0-rc.1.hotfix.6'" in fx and "VERSION = '1.0.0-rc.1.hotfix.6'" in const)
check('build id consistent', 'mvp_rc1_migration_boundary_b612f3a0' in fx and 'mvp_rc1_migration_boundary_b612f3a0' in const and 'mvp_rc1_migration_boundary_b612f3a0' in imp)
check('no hotfix.5 build id left in runtime', 'mvp_rc1_migration_db_8d4f2c6a' not in fx+const+imp)

for n,ok in checks: print(('[PASS] ' if ok else '[FAIL] ')+n)
fail=sum(not ok for _,ok in checks)
print(f'RESULT tests={len(checks)} pass={len(checks)-fail} fail={fail}')
sys.exit(1 if fail else 0)
