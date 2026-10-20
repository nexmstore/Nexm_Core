local root = arg[1] or '.'
local total, failed = 0, 0
local function expect(name, condition, detail)
    total = total + 1
    if condition then
        print('[PASS] ' .. name)
    else
        failed = failed + 1
        print('[FAIL] ' .. name .. (detail and (' :: ' .. tostring(detail)) or ''))
    end
end
local function read(path)
    local f, err = io.open(root .. '/' .. path, 'rb')
    if not f then return nil, err end
    local s = f:read('*a'); f:close(); return s
end
local function contains(s, plain) return s and s:find(plain, 1, true) ~= nil end

-- Release/version consistency -------------------------------------------------
local constants = assert(read('shared/constants.lua'))
local manifest = assert(read('fxmanifest.lua'))
local version = constants:match("VERSION%s*=%s*'([^']+)'")
local buildId = constants:match("BUILD_ID%s*=%s*'([^']+)'")
local manifestVersion = manifest:match("\nversion%s+'([^']+)'")
local manifestBuildId = manifest:match("\nnexm_build%s+'([^']+)'")
expect('Phase 7 build uses explicit pre-RC development version', version == '1.0.0-dev.7', version)
expect('Manifest version matches Constants.VERSION', manifestVersion == version, tostring(manifestVersion) .. ' vs ' .. tostring(version))
expect('Internal build identifier is present without changing SemVer', type(buildId)=='string' and buildId:match('^rpc_transport_fix9_[0-9a-f]+$')~=nil, buildId)
expect('Manifest internal build metadata matches Constants.BUILD_ID', manifestBuildId == buildId, tostring(manifestBuildId)..' vs '..tostring(buildId))
expect('Phase 7 build is not prematurely labeled final 1.0.0', version ~= '1.0.0')
expect('Phase 7 build is not prematurely labeled rc.1', version ~= '1.0.0-rc.1')
expect('Release status explicitly records pre-RC unvalidated state', contains(constants, "RELEASE_STATUS = 'PRE_RC_UNVALIDATED'"))
expect('oxmysql remains explicit manifest dependency', contains(manifest, "dependency 'oxmysql'"))
expect('Consumer import.lua is explicitly shipped in the Core client packfile', contains(manifest, "files {") and contains(manifest, "'import.lua'"))
expect('Production manifest does not load tests', not contains(manifest, 'tests/'))
expect('Production manifest does not load mocks or fixtures', not manifest:lower():find('mock',1,true) and not manifest:lower():find('fixture',1,true))
expect('Escrow manifest keeps config.lua customer-editable', contains(manifest, "'config.lua'"))
expect('Escrow manifest keeps custom adapters customer-editable', contains(manifest, "'custom/*.lua'"))

-- API freeze inventory --------------------------------------------------------
local serverApi = assert(read('server/api.lua'))
local clientApi = assert(read('client/api.lua'))
local serverNamespaces = {
    'Version','Validate','Log','DB','Migrations','Resources','Services','Features','Integrations','Components',
    'Player','Jobs','Money','Inventory','Notify','Locale','Audit','Callback','RateLimit','Permissions','Events'
}
for _, name in ipairs(serverNamespaces) do
    expect('Server facade includes frozen namespace ' .. name,
        serverApi:find('facade%.' .. name .. '%s*=') ~= nil or (name == 'Validate' and contains(serverApi, 'facade.Validate = Validation')))
end
expect('Server facade retains approved root IsReady', contains(serverApi, 'facade.IsReady ='))
expect('Server facade retains approved root GetStatus', contains(serverApi, 'facade.GetStatus ='))
local clientNamespaces = {'Player','Callback','Notify','Locale','Events','Validate','Version'}
for _, name in ipairs(clientNamespaces) do
    expect('Client facade includes approved safe namespace ' .. name,
        clientApi:find(name .. '%s*=') ~= nil)
end
for _, name in ipairs({'Money','Inventory','Permissions','Audit','DB','Migrations','Resources','Services','Features','Integrations','Components','RateLimit'}) do
    expect('Client facade excludes sensitive/mutating namespace ' .. name,
        clientApi:find(name .. '%s*=') == nil)
end
expect('API freeze document exists', read('API_FREEZE.md') ~= nil)
expect('API freeze documents approved Phase 2 Migrations namespace', contains(assert(read('API_FREEZE.md')), '`Migrations`'))

-- Export and network surface inventory ---------------------------------------
local function productionFiles()
    local files = {}
    local cmd = string.format("find %q -type f -name '*.lua' \\( -path '*/server/*' -o -path '*/client/*' -o -path '*/shared/*' -o -path '*/adapters/*' -o -path '*/custom/*' \\) ! -path '*/tests/*' | sort", root)
    local p = io.popen(cmd)
    if not p then return files end
    for line in p:lines() do files[#files + 1] = line end
    p:close(); return files
end
local function slurpAbsolute(path)
    local f=io.open(path,'rb'); if not f then return '' end; local s=f:read('*a'); f:close(); return s
end
local files = productionFiles()
local exportDecl, regNet, trigServer, trigClient = {}, {}, {}, {}
local stopResourceFound, forbiddenGameplayFound, secretLiteralFound = false, false, false
local forbiddenGameplay = {'nexm_justice','nexm_evidence','nexm_contraband','nexm_citypulse'}
for _, path in ipairs(files) do
    local s = slurpAbsolute(path)
    for name in s:gmatch("exports%s*%(%s*['\"]([^'\"]+)['\"]") do exportDecl[#exportDecl+1]=name end
    for name in s:gmatch("RegisterNetEvent%s*%(%s*['\"]([^'\"]+)['\"]") do regNet[name]=true end
    for name in s:gmatch("TriggerServerEvent%s*%(%s*['\"]([^'\"]+)['\"]") do trigServer[name]=true end
    for name in s:gmatch("TriggerClientEvent%s*%(%s*['\"]([^'\"]+)['\"]") do trigClient[name]=true end
    for name in s:gmatch("TriggerClientEvent%s*,%s*['\"]([^'\"]+)['\"]") do trigClient[name]=true end
    if s:find('StopResource%s*%(') then stopResourceFound=true end
    for _, token in ipairs(forbiddenGameplay) do if s:lower():find(token,1,true) then forbiddenGameplayFound=true end end
    if s:match('https://discord%.com/api/webhooks/%d+') or s:match('mysql://[^%s]+:[^%s]+@') then secretLiteralFound=true end
end
expect('Only GetCoreObject is declared as NEXM export', #exportDecl == 2 and exportDecl[1]=='GetCoreObject' and exportDecl[2]=='GetCoreObject', table.concat(exportDecl,','))
expect('Production Core never calls StopResource', not stopResourceFound)
expect('Feature-freeze production paths contain no gameplay resource implementation names', not forbiddenGameplayFound)
expect('No embedded Discord/MySQL credential-shaped literals in production Lua', not secretLiteralFound)

local expectedRegister = {
 ['nexm_core:rpc:request']=true,
 ['nexm_core:server:requestLocalState']=true,
 ['nexm_core:client:playerState']=true,
 ['nexm_core:client:playerUnloaded']=true,
 ['nexm_core:client:frameworkUnavailable']=true,
 ['nexm_core:rpc:response']=true,
 ['nexm_core:client:notify']=true,
}
local expectedServer = { ['nexm_core:server:requestLocalState']=true, ['nexm_core:rpc:request']=true }
local expectedClient = {
 ['nexm_core:rpc:response']=true,
 ['nexm_core:client:playerState']=true,
 ['nexm_core:client:playerUnloaded']=true,
 ['nexm_core:client:frameworkUnavailable']=true,
 ['nexm_core:client:notify']=true,
}
local function sameSet(actual, expected)
    for k in pairs(actual) do if not expected[k] then return false, 'unexpected:'..k end end
    for k in pairs(expected) do if not actual[k] then return false, 'missing:'..k end end
    return true,nil
end
local ok, detail = sameSet(regNet, expectedRegister); expect('RegisterNetEvent inventory matches frozen network surface', ok, detail)
ok, detail = sameSet(trigServer, expectedServer); expect('TriggerServerEvent inventory matches frozen network surface', ok, detail)
ok, detail = sameSet(trigClient, expectedClient); expect('TriggerClientEvent inventory matches frozen network surface', ok, detail)
expect('Internal EventBus remains non-networked', not contains(assert(read('server/event_bus.lua')), 'RegisterNetEvent') and not contains(assert(read('server/event_bus.lua')), 'TriggerClientEvent'))
expect('No generic money mutation network event exists', not serverApi:find('nexm:money',1,true) and not clientApi:find('nexm:money',1,true))
expect('No generic inventory mutation network event exists', not serverApi:find('nexm:inventory',1,true) and not clientApi:find('nexm:inventory',1,true))
expect('Network surface document exists', read('NETWORK_SURFACE.md') ~= nil)

-- Privacy/diagnostics static audit --------------------------------------------
local diagnostics = assert(read('server/diagnostics.lua'))
local bootstrap = assert(read('server/bootstrap.lua'))
local stateSource = assert(read('server/state.lua'))
local _, buildLogCount = bootstrap:gsub('%[NEXM%] build=', '')
expect('Bootstrap emits internal build fingerprint exactly once', buildLogCount == 1, buildLogCount)
expect('GetStatus includes internal build identifier', contains(stateSource, 'buildId = Constants.BUILD_ID'))
expect('Status diagnostics print internal build identifier', contains(diagnostics, "println('Build',Constants.BUILD_ID"))
for _, token in ipairs({'DiscordWebhook','sv_licenseKey','mysql_connection_string','password','license:'}) do
    expect('Diagnostics do not reference sensitive field ' .. token, not diagnostics:find(token,1,true))
end
local config = assert(read('config.lua'))
expect('Default Discord webhook is empty', config:match("DiscordWebhook%s*=%s*''") ~= nil)
expect('Default Discord audit does not include identifiers', contains(config, 'DiscordIncludeIdentifiers = false'))

-- Release documentation / packaging ------------------------------------------
for _, doc in ipairs({'CHANGELOG.md','RELEASE_NOTES.md','COMPATIBILITY.md','UPGRADING.md','KNOWN_LIMITATIONS.md','LIVE_VALIDATION.md','RELEASE_CHECKLIST.md'}) do
    expect('Release document exists: ' .. doc, read(doc) ~= nil)
end
local compatibility = assert(read('COMPATIBILITY.md'))
expect('Compatibility matrix does not fabricate live PASS', compatibility:find('| PASS |',1,true) == nil)
local liveStatus = assert(read('LIVE_VALIDATION.md'))
expect('Live validation records mandatory environment blockers', contains(liveStatus, '| A |') and contains(liveStatus, '| D |') and contains(liveStatus, 'BLOCKED'))
expect('Live validation does not authorize rc.1', contains(liveStatus, '`1.0.0-rc.1` is not authorized'))
for _, profile in ipairs({'A_ESX_OX','B_QBCORE_QB','C_QBCORE_OX','D_QBOX_OX','E_ESX_NATIVE'}) do
    expect('Live test profile exists: ' .. profile, read('tests/live/profiles/'..profile..'/PROFILE.md') ~= nil)
end
expect('Developer-only live test resource exists', read('tests/live/nexm_core_test/fxmanifest.lua') ~= nil and read('tests/live/nexm_core_test/server.lua') ~= nil and read('tests/live/nexm_core_test/client.lua') ~= nil)
expect('Production manifest does not load live test resource', not contains(manifest, 'nexm_core_test'))

-- Configuration validation via actual bootstrap ------------------------------
local realPrint = print
local env
local function encode(v, seen)
    local t=type(v)
    if t=='nil' then return 'null' elseif t=='boolean' or t=='number' then return tostring(v) elseif t=='string' then return string.format('%q',v) end
    if t~='table' then error('unsupported '..t) end
    seen=seen or {}; if seen[v] then error('cycle') end; seen[v]=true
    local parts={}; for k,val in pairs(v) do parts[#parts+1]=string.format('%q',tostring(k))..':'..encode(val,seen) end
    seen[v]=nil; return '{'..table.concat(parts,',')..'}'
end
local function installStubs()
    env={resourceStates={oxmysql='started'},resourcePaths={},versions={},events={},commands={},invoking=nil,exportResources={},timeouts={},players={}}
    json={encode=function(v) return encode(v) end,decode=function() return {} end}
    print=realPrint
    function GetCurrentResourceName() return 'nexm_core' end
    function GetInvokingResource() return env.invoking end
    function GetResourceState(n) return env.resourceStates[n] or 'missing' end
    function GetResourcePath(n) return env.resourcePaths[n] or ('/resources/'..n) end
    function GetResourceMetadata(n,k)
        if k=='version' then return env.versions[n] end
        if n=='nexm_core' and k=='nexm_build' then return buildId end
        return nil
    end
    function GetConvarInt() return 0 end
    function GetPlayers() return {} end
    function GetPlayerIdentifierByType() return nil end
    function GetPlayerName() return nil end
    function GetGameTimer() return 1000 end
    function IsPlayerAceAllowed() return false end
    function RegisterCommand(n,cb) env.commands[n]=cb end
    function AddEventHandler(n,cb) env.events[n]=env.events[n] or {}; local id=(env.nextHandler or 0)+1; env.nextHandler=id; env.events[n][id]=cb; return id end
    function RemoveEventHandler(id) for _,g in pairs(env.events) do g[id]=nil end end
    function RegisterNetEvent(n,cb) if cb then return AddEventHandler(n,cb) end end
    function TriggerEvent(n,...) for _,cb in pairs(env.events[n] or {}) do cb(...) end end
    function TriggerClientEvent() end
    function TriggerServerEvent() end
    function SetTimeout(ms,cb) env.timeouts[#env.timeouts+1]={ms=ms,callback=cb} end
    function CreateThread(fn) fn() end
    function Wait() end
    function PerformHttpRequest(_,cb) cb(204,'',{}) end
    source=0
    exports=setmetatable({}, {__call=function() end,__index=function(_,resource) return setmetatable({}, {__index=function(_,method) return function(_self,...)
        local r=env.exportResources[resource]; local f=r and r[method]; if not f then error(('missing export %s:%s'):format(resource,method)) end; return f(...)
    end end}) end})
    MySQL={query={await=function(sql) if sql and sql:find('SELECT `migration`',1,true) then return {} end return {} end},single={await=function() return nil end},scalar={await=function() return 1 end},insert={await=function() return 1 end},update={await=function() return 1 end},transaction={await=function() return true end}}
    promise={}; function promise.new() local p={}; function p:resolve(v) self.value=v end; return p end
    Citizen={}; function Citizen.Await(p) return p.value end
end
local sharedFiles={'shared/init.lua','shared/constants.lua','shared/errors.lua','shared/validation.lua','shared/transport.lua','shared/semver.lua','shared/identity.lua','shared/network_validation.lua','shared/safe_data.lua','shared/locale.lua','shared/notify_contract.lua'}
local serverFiles={'server/state.lua','server/logger.lua','server/ownership.lua','server/database.lua','server/migrations.lua','server/migrations/core.lua','server/registry_base.lua','server/managers/resources.lua','server/managers/services.lua','server/managers/features.lua','server/managers/integrations.lua','server/readiness.lua','server/framework_contract.lua','adapters/framework/esx.lua','adapters/framework/qbcore.lua','adapters/framework/qbox.lua','adapters/framework/standalone.lua','server/managers/framework.lua','server/player_cache.lua','server/player.lua','server/jobs.lua','server/lifecycle.lua','server/session_guard.lua','server/money.lua','server/inventory_contract.lua','custom/inventory.lua','adapters/inventory/ox_inventory.lua','adapters/inventory/qb_inventory.lua','adapters/inventory/esx.lua','adapters/inventory/qs_inventory.lua','server/managers/inventory.lua','server/inventory.lua','custom/audit.lua','server/audit.lua','server/rate_limit.lua','server/event_bus.lua','server/permissions.lua','server/callbacks.lua','server/managers/notify.lua','server/notify.lua','server/components.lua','server/diagnostics.lua'}
local function boot(mutator)
    installStubs(); Config=nil; NEXM_INTERNAL=nil; NEXM_CUSTOM_INVENTORY_ADAPTER=nil; NEXM_CUSTOM_NOTIFY_ADAPTER=nil; NEXM_CUSTOM_AUDIT_BACKEND=nil
    dofile(root..'/config.lua')
    for _,f in ipairs(sharedFiles) do dofile(root..'/'..f) end
    for _,f in ipairs(serverFiles) do dofile(root..'/'..f) end
    Config.Framework='standalone'; Config.Inventory='none'; Config.Notify='none'; Config.Audit.Enabled=false
    if mutator then mutator(Config) end
    dofile(root..'/server/bootstrap.lua')
    return NEXM_INTERNAL.Modules.State.GetStatus()
end
local validStatus=boot()
expect('Valid hardened configuration boots Core READY in stub runtime', validStatus.state=='READY', validStatus.lastError and validStatus.lastError.code)
local invalidCases={
    {'Framework selector', function(c)c.Framework='madeup' end},
    {'Inventory selector', function(c)c.Inventory='madeup' end},
    {'Notify selector', function(c)c.Notify='madeup' end},
    {'Logging level', function(c)c.Logging.level='verbose' end},
    {'Locale identifier', function(c)c.Locale='bad locale!' end},
    {'Money transaction max', function(c)c.Security.MaxMoneyTransaction=0 end},
    {'RPC global limit', function(c)c.Security.RPCGlobalLimit.limit=0 end},
    {'RPC payload depth', function(c)c.Network.request.maxDepth=0 end},
    {'Audit queue size', function(c)c.Audit.Queue.maxSize=0 end},
    {'Audit drop policy', function(c)c.Audit.Queue.dropPolicy='infinite' end},
    {'Notify default duration', function(c)c.NotifyDefaults.duration=999999 end},
    {'Database health query', function(c)c.Database.healthQuery='' end},
}
for _,case in ipairs(invalidCases) do
    local st=boot(case[2])
    expect('Invalid config fails clearly: '..case[1], st.state=='FAILED' and st.lastError and st.lastError.code=='INVALID_ARGUMENT', st.lastError and st.lastError.code)
end

-- FiveM cross-resource function-reference compatibility -----------------------
boot()
local function fakeCfxRef(fn)
    return setmetatable({__cfx_functionReference='phase7-fake-ref'}, {__call=function(_,...) return fn(...) end})
end
local Callable=NEXM_INTERNAL.Modules.Callable
expect('Internal callable helper accepts native functions', Callable.Is(function() end)==true)
expect('Internal callable helper accepts Cfx function-reference tables', Callable.Is(fakeCfxRef(function() end))==true)
expect('Internal callable helper rejects ordinary tables', Callable.Is({})==false)

local Readiness=NEXM_INTERNAL.Modules.Readiness
local readyCalls=0
local readyOk,readyErr=Readiness.Subscribe(fakeCfxRef(function() readyCalls=readyCalls+1 end),'phase7_external')
expect('Readiness accepts cross-resource function references', readyOk==true and readyCalls==1, type(readyErr)=='table' and readyErr.code or tostring(readyErr))

local Lifecycle=NEXM_INTERNAL.Modules.Lifecycle
local lifeOk,lifeErr=Lifecycle.Subscribe('jobChanged',fakeCfxRef(function() end),'phase7_external')
expect('Lifecycle accepts cross-resource function references', lifeOk==true, type(lifeErr)=='table' and lifeErr.code or tostring(lifeErr))

local EventBus=NEXM_INTERNAL.Modules.EventBus
local eventSeen=0
local eventOk,eventErr=EventBus.On('phase7:externalRef',fakeCfxRef(function(payload) eventSeen=payload.value end),'phase7_external')
local emitOk=EventBus.Emit('phase7:externalRef',{value=7})
expect('EventBus accepts and invokes cross-resource function references', eventOk==true and emitOk==true and eventSeen==7, type(eventErr)=='table' and eventErr.code or tostring(eventErr))

local Permissions=NEXM_INTERNAL.Modules.Permissions
local permOk,permErr=Permissions.Define('external_custom',{mode='any',custom=fakeCfxRef(function() return true end)},'phase7_external')
expect('Permissions accepts cross-resource custom resolver references', permOk==true, type(permErr)=='table' and permErr.code or tostring(permErr))

local Callbacks=NEXM_INTERNAL.Modules.Callbacks
local callbackCalls=0
local cbOk,cbErr=Callbacks.Register('external_echo',fakeCfxRef(function(_,payload) callbackCalls=callbackCalls+1; return {echo=payload.value} end),{validate=fakeCfxRef(function(payload) return type(payload)=='table' end)},'phase7_external')
local handleOk,handleErr=Callbacks.HandleRequest(1,'phase7-request-1','phase7_external','external_echo',{value=9})
expect('Callbacks accept cross-resource handler/validator references', cbOk==true and handleOk==true and callbackCalls==1, (type(cbErr)=='table' and cbErr.code) or (type(handleErr)=='table' and handleErr.code) or tostring(cbErr or handleErr))

local Services=NEXM_INTERNAL.Managers.Services
local svcOk,svcErr=Services.Register('external_service',{Ping=fakeCfxRef(function() return 'pong' end),Nested={value=1}},{version='1.0.0',apiVersion=1},'phase7_external')
local svc,svcGetErr=Services.Get('external_service',{apiVersion=1})
local pingOk,pingValue=pcall(function() return svc and svc.Ping() end)
if svc and svc.Nested then svc.Nested.value=999 end
local svcAgain=Services.Get('external_service',{apiVersion=1})
expect('Services preserve callable Cfx refs in portable snapshots', svcOk==true and svc~=nil and Callable.Is(svc.Ping) and pingOk and pingValue=='pong', (type(svcErr)=='table' and svcErr.code) or (type(svcGetErr)=='table' and svcGetErr.code) or tostring(svcErr or svcGetErr))
expect('Service snapshot mutation cannot alter authoritative registry state', svcAgain and svcAgain.Nested and svcAgain.Nested.value==1)

-- Public source arguments remain strict (no numeric-string coercion). ----------
local function expectInvalidSource(label, value, err)
    expect(label, (value==nil or value==false) and type(err)=='table' and err.code=='INVALID_ARGUMENT', type(err)=='table' and err.code or tostring(err))
end
local SourceValidation=NEXM_INTERNAL.Modules.Validation
for _,case in ipairs({
    {label='integer',value=1,valid=true}, {label='numeric string',value='1'}, {label='leading-zero string',value='01'},
    {label='integral float',value=1.0,valid=true}, {label='fraction',value=1.5}, {label='zero',value=0}, {label='negative',value=-1},
    {label='NaN',value=0/0}, {label='Infinity',value=math.huge}
}) do
    local ok,e=SourceValidation.Source(case.value)
    if case.valid then expect('Validation.Source accepts '..case.label,ok==true and e==nil,type(e)=='table' and e.code or tostring(e))
    else expect('Validation.Source rejects '..case.label,ok==false and type(e)=='table' and e.code=='INVALID_ARGUMENT',type(e)=='table' and e.code or tostring(e)) end
end
local Player=NEXM_INTERNAL.Modules.Player
local Jobs=NEXM_INTERNAL.Modules.Jobs
local Money=NEXM_INTERNAL.Modules.Money
local Inventory=NEXM_INTERNAL.Modules.Inventory
for _,bad in ipairs({'1','01',1.5,0,-1,0/0,math.huge}) do
    local label=type(bad)=='string' and ('string '..bad) or tostring(bad)
    local v,e=Player.Get(bad); expectInvalidSource('Player.Get rejects '..label..' source',v,e)
    v,e=Player.Exists(bad); expectInvalidSource('Player.Exists rejects '..label..' source',v,e)
end
for _,api in ipairs({
    {'GetIdentifier',Player.GetIdentifier},{'GetCharacterIdentifier',Player.GetCharacterIdentifier},{'GetAccountIdentifier',Player.GetAccountIdentifier},
    {'GetLicense',Player.GetLicense},{'GetCharacterName',Player.GetCharacterName},{'GetJob',Player.GetJob},{'GetJobGrade',Player.GetJobGrade}
}) do local v,e=api[2]('1'); expectInvalidSource('Player.'..api[1]..' rejects numeric-string source',v,e) end
local v,e=Jobs.Get('1'); expectInvalidSource('Jobs.Get rejects numeric-string source',v,e)
v,e=Jobs.Has('1','police'); expectInvalidSource('Jobs.Has rejects numeric-string source',v,e)
v,e=Money.Get('1','cash'); expectInvalidSource('Money.Get rejects numeric-string source',v,e)
v,e=Money.CanAfford('1','cash',1); expectInvalidSource('Money.CanAfford rejects numeric-string source',v,e)
v,e=Inventory.GetItemCount('1','water'); expectInvalidSource('Inventory.GetItemCount rejects numeric-string source',v,e)
v,e=Inventory.HasItem('1','water',1); expectInvalidSource('Inventory.HasItem rejects numeric-string source',v,e)

-- Server facade boundary repeats strict source validation before domain calls. -
env.invoking='phase7_external'; dofile(root..'/server/api.lua'); local publicCore=GetCoreObject(); env.invoking=nil
v,e=publicCore.Player.Get('1'); expectInvalidSource('Server facade Player.Get rejects numeric-string source before domain dispatch',v,e)
v,e=publicCore.Jobs.Get('1'); expectInvalidSource('Server facade Jobs.Get rejects numeric-string source before domain dispatch',v,e)
v,e=publicCore.Money.Get('1','cash'); expectInvalidSource('Server facade Money.Get rejects numeric-string source before domain dispatch',v,e)
v,e=publicCore.Inventory.GetItemCount('1','water'); expectInvalidSource('Server facade Inventory.GetItemCount rejects numeric-string source before domain dispatch',v,e)

-- Real-client ownership regression: initial export may have no invoker, while --
-- the later Cfx facade function-reference call does. Routing must bind lazily. -
local capturedClientOwner=nil
local clientInvoker=nil
local clientEnvelopeMode='success'
local clientTransportMarker='__phase7_client_transport__'
local function phase7Pack(...)
    local tuple=table.pack(...); local entries={}
    for i=1,tuple.n do entries[i]=tuple[i]==nil and {isNil=true} or {value=tuple[i]} end
    return {__nexmTransport=clientTransportMarker,n=tuple.n,entries=entries}
end
local function phase7Unpack(envelope)
    local out={n=envelope.n}
    for i=1,envelope.n do local entry=envelope.entries[i]; if entry.isNil~=true then out[i]=entry.value end end
    return table.unpack(out,1,out.n)
end
local ClientCallbacksMock={}
function ClientCallbacksMock.AwaitEnvelope(owner,name,payload,options)
    capturedClientOwner=owner
    if clientEnvelopeMode=='success' then return {ok=true,value={name=name}} end
    if clientEnvelopeMode=='false-success' then return {ok=true,value=false} end
    return {ok=false,error={code=clientEnvelopeMode,message='phase7 '..clientEnvelopeMode}}
end
function ClientCallbacksMock.Await(owner,name,payload,options)
    local response=ClientCallbacksMock.AwaitEnvelope(owner,name,payload,options)
    if response.ok then return response.value,nil end
    return nil,response.error
end
NEXM_INTERNAL={Modules={
    ClientPlayerState={Get=function() return {} end,IsLoaded=function() return true end},
    ClientEvents={Subscribe=function(_,_,owner) capturedClientOwner=owner; return true,nil end},
    Validation=SourceValidation,
    Transport={MARKER=clientTransportMarker,IsRequested=function(v) return v==clientTransportMarker end,Pack=phase7Pack,WrapFacade=function(v) return v end},
    Constants={VERSION='1.0.0-dev.7',ERROR_CODES={RPC_UNAVAILABLE='RPC_UNAVAILABLE'}},
    Errors={Create=function(code,message,context) return {code=code,message=message,context=context or {}} end},
    ClientCallbacks=ClientCallbacksMock,
    ClientNotify={Send=function() return true,nil end},
    Locale={Register=function(_,_,owner) capturedClientOwner=owner; return true,nil end,Get=function(_,_,owner) capturedClientOwner=owner; return 'ok' end,SetFallback=function(_,owner) capturedClientOwner=owner; return true,nil end,CleanupOwner=function() end}
}}
Config={}
function GetCurrentResourceName() return 'nexm_core' end
function GetInvokingResource() return clientInvoker end
function AddEventHandler() return 1 end
exports=function() end
dofile(root..'/client/api.lua')
clientInvoker=nil
local deferredFacade=GetCoreObject()
clientInvoker='nexm_core_test'
local rpcValue,rpcErr=deferredFacade.Callback.Await('echo',{},{})
expect('Client facade resolves RPC routing owner lazily from real method invoker when export-time invoker is unavailable',capturedClientOwner=='nexm_core_test' and rpcValue and rpcErr==nil,capturedClientOwner)
clientInvoker='nexm_client_bound'
local boundFacade=GetCoreObject()
clientInvoker=nil
boundFacade.Locale.Register('en',{x='x'})
expect('Client facade preserves valid export-time owner when later method invoker is unavailable',capturedClientOwner=='nexm_client_bound',capturedClientOwner)

-- Yielding RPC error results stay in one envelope until the transport edge. --
clientInvoker='nexm_core_test'
local rpcTransportFacade=GetCoreObject(clientTransportMarker)
for _,code in ipairs({'RPC_TIMEOUT','RPC_CALLBACK_NOT_FOUND','RPC_INVALID_RESPONSE','PERMISSION_DENIED','RATE_LIMITED','INVALID_PAYLOAD','STALE_CHARACTER_SESSION'}) do
    clientEnvelopeMode=code
    local packed=rpcTransportFacade.Callback.Await('phase7_error',{}, {})
    local rv,re=phase7Unpack(packed)
    expect('Client transport facade preserves '..code..' as public nil,error tuple',rv==nil and re and re.code==code,re and re.code)
end
clientEnvelopeMode='success'
local packedSuccess=rpcTransportFacade.Callback.Await('phase7_success',{}, {})
local successValue,successErr=phase7Unpack(packedSuccess)
expect('Client transport facade preserves success as result,nil',type(successValue)=='table' and successErr==nil,successErr and successErr.code)
clientEnvelopeMode='false-success'
local packedFalse=rpcTransportFacade.Callback.Await('phase7_false',{}, {})
local falseValue,falseErr=phase7Unpack(packedFalse)
expect('Client transport facade preserves false success distinctly from failure',falseValue==false and falseErr==nil,falseErr and falseErr.code)


-- Cfx function-reference transport preserves leading-nil error tuples. --------
boot()
local Transport=NEXM_INTERNAL.Modules.Transport
local transportErr={code='INVALID_ARGUMENT',message='transport test'}
local envelope=Transport.Pack(nil,transportErr)
expect('Transport envelope records leading-nil tuple arity',type(envelope)=='table' and envelope.n==2 and type(envelope.entries)=='table' and #envelope.entries==2)
expect('Transport envelope represents nil as a dense slot',envelope.entries[1] and envelope.entries[1].isNil==true)
expect('Transport envelope preserves structured error after leading nil',envelope.entries[2] and envelope.entries[2].value and envelope.entries[2].value.code=='INVALID_ARGUMENT')
local function unwrapTransport(x)
    local n=x and x.n or 0; local entries=x and x.entries or {}; local vals={n=n}
    for i=1,n do local e=entries[i]; if e and e.isNil~=true then vals[i]=e.value end end
    return table.unpack(vals,1,n)
end
local tv,te=unwrapTransport(envelope)
expect('Transport envelope reconstructs nil,error contract',tv==nil and te and te.code=='INVALID_ARGUMENT',te and te.code)
local wrapped=Transport.WrapFacade({Get=function() return nil,transportErr end,Pred=function() return false,transportErr end})
tv,te=unwrapTransport(wrapped.Get())
expect('Transport-wrapped getter preserves nil,error contract',tv==nil and te and te.code=='INVALID_ARGUMENT',te and te.code)
local pv,pe=unwrapTransport(wrapped.Pred())
expect('Transport-wrapped predicate preserves false,error contract',pv==false and pe and pe.code=='INVALID_ARGUMENT',pe and pe.code)
expect('Transport false slot remains dense',Transport.Pack(false,transportErr).entries[1].value==false)
local mid=Transport.Pack('a',nil,'c')
expect('Transport middle-nil tuple remains dense',#mid.entries==3 and mid.entries[2].isNil==true and mid.entries[3].value=='c')

-- Services mismatches remain structured through the transport facade. --------
local ServicesTransport=NEXM_INTERNAL.Managers.Services
ServicesTransport.Register('transport_version_service',{Ping=function() return 'pong' end},{version='1.0.0',apiVersion=1},'phase7_transport')
local transportServiceFacade=Transport.WrapFacade({Get=function(name,options) return ServicesTransport.Get(name,options) end})
local sv,se=unwrapTransport(transportServiceFacade.Get('transport_version_service',{apiVersion=999}))
expect('Transport preserves SERVICE_API_VERSION_MISMATCH getter error',sv==nil and se and se.code=='SERVICE_API_VERSION_MISMATCH',se and se.code)

-- Consumer import patches the real exports object in place --------------------
-- This models the real Cfx public acquisition path. A consumer script may hold
-- a reference to the original scheduler-created `exports` table before
-- @nexm_core/import.lua runs. The import must mutate that object in place,
-- request the transport facade, and restore exact Lua return arity locally.
local savedExports=exports
local importMarkerSeen=nil
local fakeCfxExports={}
setmetatable(fakeCfxExports,{
    __index=function(_,resource)
        return setmetatable({}, {
            __index=function(_,exportName)
                return function(_, ...)
                    if resource=='nexm_core' and exportName=='GetCoreObject' then
                        local args=table.pack(...)
                        importMarkerSeen=args[1]
                        local callbackErrors={
                            timeout='RPC_TIMEOUT',
                            unknown='RPC_CALLBACK_NOT_FOUND',
                            invalid='RPC_INVALID_RESPONSE',
                            permission='PERMISSION_DENIED',
                            rate='RATE_LIMITED',
                            payload='INVALID_PAYLOAD'
                        }
                        local rawFacade={
                            Generic={
                                One=function() return 'ok' end,
                                False=function() return false end,
                                Error=function() return nil,{code='TEST_ERROR',message='transport test',context={}} end,
                                ValueNil=function() return 'value',nil end,
                                NilNil=function() return nil,nil end,
                                ValueFalse=function() return 'value',false end,
                                TableNil=function() return {ok=true},nil end
                            },
                            Callback={
                                Await=function(name)
                                    if name=='success' then return {ok=true},nil end
                                    local code=callbackErrors[name]
                                    if code then return nil,{code=code,message='rpc transport test',context={}} end
                                    return nil,{code='RPC_CALLBACK_NOT_FOUND',message='rpc transport test',context={}}
                                end
                            }
                        }
                        return Transport.WrapFacade(rawFacade)
                    end
                    return 'other-export'
                end
            end,
            __newindex=function() error('cannot set values on fake export resource') end
        })
    end,
    __newindex=function() error('cannot set values on fake exports') end,
    __call=function() end
})
exports=fakeCfxExports
local capturedExports=fakeCfxExports
local savedDuplicity=IsDuplicityVersion
IsDuplicityVersion=function() return false end
dofile(root..'/import.lua')
expect('Consumer import patches existing Cfx exports table in place',exports==fakeCfxExports and capturedExports==fakeCfxExports)
local importedCore=capturedExports['nexm_core']:GetCoreObject()
expect('Consumer import requests the transport facade through canonical GetCoreObject syntax',importMarkerSeen==Transport.MARKER,importMarkerSeen)
local importDiag=rawget(_G,'__NEXM_IMPORT_DIAGNOSTICS')
expect('Consumer import client-runtime regression proves side=client',type(importDiag)=='table' and importDiag.runtimeSide=='client' and importDiag.importLoaded==true and importDiag.facadeInitialized==true,importDiag and importDiag.runtimeSide)
expect('Consumer import records expected build identity',type(importDiag)=='table' and importDiag.expectedBuildId==buildId and importDiag.metadataBuildId==buildId and importDiag.facadeBuildId==buildId and importDiag.buildIdentityMatch==true,importDiag and importDiag.facadeBuildId)
expect('Consumer import proves transport proxy is installed',type(importDiag)=='table' and importDiag.proxyInstalled==true and importDiag.transportRequested==true)
expect('Consumer import proves remote Callback.Await is a Cfx-style reference in facade model',type(importDiag)=='table' and importDiag.remoteCallbackKind=='function' or (type(importDiag)=='table' and importDiag.remoteCallbackKind=='cfx_function_ref'),importDiag and importDiag.remoteCallbackKind)
expect('Consumer import exposes Callback.Await as a local Lua wrapper',type(importDiag)=='table' and importDiag.publicCallbackKind=='function' and importDiag.callbackLocallyProxied==true,importDiag and importDiag.publicCallbackKind)
expect('Import transport self-probe passes before RPC',type(importDiag)=='table' and importDiag.probePassed==true)
expect('Import records explicit Callback.Await local-proxy metadata',type(importDiag)=='table' and importDiag.callbackLocallyProxied==true and type(importDiag.proxiedMethods)=='table' and importDiag.proxiedMethods['Callback.Await']==true and importDiag.callbackWrapperState=='LOCAL_PROXY')
local realProbeOk,realProbeResults=importDiag.runRealConsumerProbe()
expect('Real consumer generic probe passes through the shared local wrapper path',realProbeOk==true)
expect('Real consumer generic probe preserves leading nil structured error',type(realProbeResults)=='table' and type(realProbeResults.error)=='table' and realProbeResults.error.decodedReturnCount==2 and realProbeResults.error.decodedFirstType=='nil' and realProbeResults.error.decodedSecondType=='table' and realProbeResults.error.decodedErrorCode=='TEST_ERROR')
expect('Real consumer generic probe preserves table,nil tuple',type(realProbeResults)=='table' and type(realProbeResults.tableNil)=='table' and realProbeResults.tableNil.decodedReturnCount==2 and realProbeResults.tableNil.decodedFirstType=='table' and realProbeResults.tableNil.decodedFirstTableOk==true and realProbeResults.tableNil.decodedSecondType=='nil')

expect('Transport diagnostics do not leak build marker into public facade',importedCore.__nexmBuildId==nil and importedCore.__nexmTransportProbe==nil)
local function packedCall(fn,...)
    return table.pack(fn(...))
end
local gp=packedCall(importedCore.Generic.One)
expect('Generic transport preserves one string return',gp.n==1 and gp[1]=='ok',gp.n)
gp=packedCall(importedCore.Generic.False)
expect('Generic transport preserves one false return',gp.n==1 and gp[1]==false,gp.n)
gp=packedCall(importedCore.Generic.Error)
expect('Generic transport preserves leading nil structured error',gp.n==2 and gp[1]==nil and type(gp[2])=='table' and gp[2].code=='TEST_ERROR',gp[2] and gp[2].code)
gp=packedCall(importedCore.Generic.ValueNil)
expect('Generic transport preserves value,nil arity',gp.n==2 and gp[1]=='value' and gp[2]==nil,gp.n)
gp=packedCall(importedCore.Generic.NilNil)
expect('Generic transport preserves explicit nil,nil arity',gp.n==2 and gp[1]==nil and gp[2]==nil,gp.n)
gp=packedCall(importedCore.Generic.ValueFalse)
expect('Generic transport preserves value,false tuple',gp.n==2 and gp[1]=='value' and gp[2]==false,gp.n)
gp=packedCall(importedCore.Generic.TableNil)
expect('Generic transport preserves table,nil tuple',gp.n==2 and type(gp[1])=='table' and gp[1].ok==true and gp[2]==nil,gp.n)
for name,code in pairs({
    timeout='RPC_TIMEOUT',
    unknown='RPC_CALLBACK_NOT_FOUND',
    invalid='RPC_INVALID_RESPONSE',
    permission='PERMISSION_DENIED',
    rate='RATE_LIMITED',
    payload='INVALID_PAYLOAD'
}) do
    local rp=packedCall(importedCore.Callback.Await,name)
    expect('Imported public Callback.Await preserves '..code,rp.n==2 and rp[1]==nil and type(rp[2])=='table' and rp[2].code==code,rp[2] and rp[2].code)
end
local successRpc=packedCall(importedCore.Callback.Await,'success')
expect('Imported public Callback.Await preserves success result,nil',successRpc.n==2 and type(successRpc[1])=='table' and successRpc[1].ok==true and successRpc[2]==nil,successRpc.n)
local otherExport=capturedExports['other_resource']:Anything()
expect('Consumer import leaves non-NEXM exports behavior untouched',otherExport=='other-export',otherExport)
exports=savedExports
IsDuplicityVersion=savedDuplicity

-- Cfx callable response values are rejected before RPC response serialization. -
local NetworkValidation=NEXM_INTERNAL.Modules.NetworkValidation
local fakeResponseRef=setmetatable({__cfx_functionReference='phase7-response-ref'},{__call=function() end})
local safeResponse,responseErr=NetworkValidation.Response({bad=fakeResponseRef})
expect('RPC response validation rejects Cfx function-reference values',safeResponse==nil and responseErr and responseErr.code=='RPC_INVALID_RESPONSE',responseErr and responseErr.code)

-- Compile every production Lua file -------------------------------------------
local compileOk, compileErr = true, nil
for _, path in ipairs(files) do
    local chunk, err = loadfile(path)
    if not chunk then compileOk=false; compileErr=path..': '..tostring(err); break end
end
expect('All Phase 2-7 production Lua files compile in harness', compileOk, compileErr)

print(('PHASE7 TESTS: %d, FAILED: %d'):format(total, failed))
if failed > 0 then error(('Phase 7 tests failed: %d'):format(failed)) end
