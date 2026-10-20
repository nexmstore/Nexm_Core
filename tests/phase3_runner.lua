local root = arg[1] or '.'
local total, failed = 0, 0
local function expect(name, condition, detail)
    total = total + 1
    if condition then print('[PASS] ' .. name) else failed = failed + 1; print('[FAIL] ' .. name .. (detail and (' :: '..tostring(detail)) or '')) end
end

local env = {}
local function installStubs()
    env = { resourceStates = { oxmysql = 'started', ox_inventory = 'started' }, resourcePaths = {}, versions = {}, playerIdentifiers = {}, players = {}, events = {}, clientEvents = {}, commands = {}, invoking = nil, exportResources = {}, nextHandler = 0, removedHandlers = 0 }
    json = { encode = function() return '{}' end, decode = function() return {} end }
    function GetCurrentResourceName() return 'nexm_core' end
    function GetInvokingResource() return env.invoking end
    function GetResourceState(name) return env.resourceStates[name] or 'missing' end
    function GetResourcePath(name) return env.resourcePaths[name] end
    function GetResourceMetadata(name, key) if key == 'version' then return env.versions[name] end return nil end
    function GetPlayers() local out = {}; for _, s in ipairs(env.players) do out[#out+1]=tostring(s) end; return out end
    function GetPlayerIdentifierByType(src, typ) local t=env.playerIdentifiers[tonumber(src)] or {}; return t[typ] end
    function GetPlayerName(src) return 'Player' .. tostring(src) end
    function RegisterCommand(name, cb) env.commands[name] = cb end
    function AddEventHandler(name, cb)
        env.nextHandler = env.nextHandler + 1
        env.events[name] = env.events[name] or {}
        env.events[name][env.nextHandler] = cb
        return env.nextHandler
    end
    function RemoveEventHandler(token)
        for _, group in pairs(env.events) do if group[token] then group[token] = nil; env.removedHandlers = env.removedHandlers + 1; return end end
    end
    function RegisterNetEvent(name, cb) if cb then return AddEventHandler(name, cb) end end
    function TriggerEvent(name, ...)
        local group=env.events[name] or {}; local ids={}; for id in pairs(group) do ids[#ids+1]=id end; table.sort(ids)
        for _, id in ipairs(ids) do if group[id] then group[id](...) end end
    end
    function TriggerClientEvent(name, target, ...)
        env.clientEvents[#env.clientEvents+1] = { name=name, target=target, args={...} }
    end
    function TriggerServerEvent(name, ...)
        env.serverEventRequests = env.serverEventRequests or {}
        env.serverEventRequests[#env.serverEventRequests+1] = { name=name, args={...} }
    end
    function CreateThread(fn) fn() end
    function Wait() end
    source = 0

    local registeredExports = {}
    exports = setmetatable({}, {
        __call = function(_, name, fn) registeredExports[name] = fn end,
        __index = function(_, resource)
            return setmetatable({}, { __index = function(_, method)
                return function(_, ...)
                    local r = env.exportResources[resource]
                    local f = r and r[method]
                    if not f then error(('missing export %s:%s'):format(resource, method)) end
                    return f(...)
                end
            end })
        end
    })
    env.registeredExports = registeredExports

    env.exportResources.ox_inventory = {
        GetItemCount=function() return 0 end, AddItem=function() return true end, RemoveItem=function() return true end,
        CanCarryItem=function() return true end, GetInventoryItems=function() return {} end
    }

    MySQL = {
        query = { await = function(sql) if sql:find('SELECT `migration`',1,true) then return {} end return {} end },
        single = { await = function() return nil end },
        scalar = { await = function() return 1 end },
        insert = { await = function() return 1 end },
        update = { await = function() return 1 end },
        transaction = { await = function() return true end }
    }
end

local function loadBase(includeApi)
    installStubs()
    Config=nil; NEXM_INTERNAL=nil; GetCoreObject=nil; NEXM_TEST_BOOT_ORDER=nil; NEXM_CUSTOM_INVENTORY_ADAPTER=nil
    dofile(root..'/config.lua')
    dofile(root..'/shared/init.lua'); dofile(root..'/shared/constants.lua'); dofile(root..'/shared/errors.lua'); dofile(root..'/shared/validation.lua'); dofile(root..'/shared/transport.lua'); dofile(root..'/shared/semver.lua'); dofile(root..'/shared/identity.lua'); dofile(root..'/shared/safe_data.lua'); dofile(root..'/shared/locale.lua'); dofile(root..'/shared/notify_contract.lua')
    dofile(root..'/server/state.lua'); dofile(root..'/server/logger.lua'); dofile(root..'/server/ownership.lua'); dofile(root..'/server/database.lua'); dofile(root..'/server/migrations.lua'); dofile(root..'/server/migrations/core.lua')
    dofile(root..'/server/registry_base.lua'); dofile(root..'/server/managers/resources.lua'); dofile(root..'/server/managers/services.lua'); dofile(root..'/server/managers/features.lua'); dofile(root..'/server/managers/integrations.lua'); dofile(root..'/server/readiness.lua')
    dofile(root..'/server/framework_contract.lua')
    dofile(root..'/adapters/framework/esx.lua'); dofile(root..'/adapters/framework/qbcore.lua'); dofile(root..'/adapters/framework/qbox.lua'); dofile(root..'/adapters/framework/standalone.lua')
    dofile(root..'/server/managers/framework.lua'); dofile(root..'/server/player_cache.lua'); dofile(root..'/server/player.lua'); dofile(root..'/server/jobs.lua'); dofile(root..'/server/lifecycle.lua')
    dofile(root..'/server/session_guard.lua'); dofile(root..'/server/money.lua'); dofile(root..'/server/inventory_contract.lua'); dofile(root..'/custom/inventory.lua')
    dofile(root..'/adapters/inventory/ox_inventory.lua'); dofile(root..'/adapters/inventory/qb_inventory.lua'); dofile(root..'/adapters/inventory/esx.lua'); dofile(root..'/adapters/inventory/qs_inventory.lua'); dofile(root..'/server/managers/inventory.lua'); dofile(root..'/server/inventory.lua')
    dofile(root..'/custom/audit.lua'); dofile(root..'/server/audit.lua'); dofile(root..'/server/managers/notify.lua'); dofile(root..'/server/notify.lua'); dofile(root..'/server/components.lua'); dofile(root..'/server/diagnostics.lua')
    if includeApi then dofile(root..'/server/api.lua') end
    return NEXM_INTERNAL
end

local function validAdapter(name, resource)
    local callbacks = {}
    local adapter = { metadata = { name=name, resource=resource, version='1.0.0', capabilities={ player={identity={character=true,account=true,license=true},job=true,duty=true}, jobs={multiple=false}, money={cash=true,bank=true}, framework={permissions=false} } } }
    function adapter.IsAvailable() return true end; function adapter.Initialize() return true,nil end; function adapter.Shutdown() return true,nil end; function adapter.GetState() return 'HEALTHY' end
    function adapter.GetPlayer() return {} end; function adapter.IsPlayerLoaded() return true end; function adapter.GetCharacterIdentifier() return 'ABC',nil end; function adapter.GetAccountIdentifier() return 'acct',nil end; function adapter.GetLicense() return 'license:abc',nil end; function adapter.GetCharacterName() return 'Test Player',nil end
    function adapter.GetJob() return {name='police',label='Police',grade=1,gradeName='officer',onDuty=true},nil end
    function adapter.GetMoney(_, account) return account == 'cash' and 100 or 500,nil end; function adapter.AddMoney() return true,nil end; function adapter.RemoveMoney() return true,nil end
    function adapter.SubscribePlayerLoaded(cb) callbacks.load=cb; return true,nil end; function adapter.SubscribePlayerUnloaded(cb) callbacks.unload=cb; return true,nil end; function adapter.SubscribeJobChanged(cb) callbacks.job=cb; return true,nil end; function adapter.SubscribeDutyChanged(cb) callbacks.duty=cb; return true,nil end
    adapter._callbacks=callbacks
    return adapter
end

-- Phase-2 foundation regressions ---------------------------------------------
local R0 = loadBase(true)
local SemVer, Validation0, Errors0 = R0.Modules.SemVer, R0.Modules.Validation, R0.Modules.Errors
local cmp = SemVer.Compare('1.0.0-alpha','1.0.0'); expect('Regression: SemVer prerelease precedence',cmp==-1)
local sat = SemVer.Satisfies('1.5.0','>=1.3.0 <2.0.0'); expect('Regression: SemVer compound range',sat==true)
sat = SemVer.Satisfies('0.2.9','^0.2.3'); expect('Regression: SemVer caret 0.x',sat==true)
sat = SemVer.Satisfies('1.2.9','~1.2.3'); expect('Regression: SemVer tilde',sat==true)
sat = SemVer.Satisfies('2.1.0','^1.0.0 || >=2.0.0 <3.0.0'); expect('Regression: SemVer OR range',sat==true)
local vok,verr=Validation0.Number(0/0); expect('Regression: validation rejects NaN',vok==false and Errors0.Is(verr,'INVALID_ARGUMENT'))
vok,verr=Validation0.Identifier('bad id'); expect('Regression: identifier validation rejects spaces',vok==false)
local DB0=R0.Modules.DB; local qold=MySQL.query.await; MySQL.query.await=function() error('db down') end; local _,dberr=DB0.Query('SELECT 1',{},'test'); expect('Regression: DB wrapper normalizes thrown failure',Errors0.Is(dberr,'DATABASE_ERROR')); MySQL.query.await=qold
env.invoking='nexm_dep'; local preReadyApi=GetCoreObject(); local _,gateErr=preReadyApi.DB.Query('SELECT 1'); expect('Regression: public DB remains READY-gated',Errors0.Is(gateErr,'CORE_NOT_READY'))
local Int=R0.Managers.Integrations; Int.RegisterInternal({category='inventory',name='ox_inventory',version='1.0.0',critical=true,state='AVAILABLE',adapter={}},'nexm_core'); Int.RegisterInternal({category='inventory',name='qb-inventory',version='1.0.0',critical=true,state='AVAILABLE',adapter={}},'nexm_core')
local iok,ierr=Int.Select('inventory','auto',{}); expect('Regression: ambiguous critical inventory still fails closed',iok==false and Errors0.Is(ierr,'AMBIGUOUS_INVENTORY_INTEGRATION'))
local chosen; iok,chosen=Int.Select('inventory','auto',{'ox_inventory'}); expect('Regression: explicit inventory priority resolves ambiguity',iok==true and chosen=='ox_inventory')
iok,ierr=Int.Select('inventory','qb-inventory',{}); expect('Regression: critical integration selection stays sticky',iok==false and Errors0.Is(ierr,'INTEGRATION_SELECTION_LOCKED'))

-- Contract + pure identity ----------------------------------------------------
local I = loadBase(false)
local Contract, Errors, Identity = I.Modules.FrameworkContract, I.Modules.Errors, I.Modules.Identity
local fake = validAdapter('qbox','qbx_core')
local ok, err = Contract.Validate(fake); expect('Framework contract accepts complete adapter', ok == true and err == nil)
local broken = validAdapter('qbox','qbx_core'); broken.GetCharacterIdentifier=nil
ok, err = Contract.Validate(broken); expect('Framework contract rejects missing required method', ok == false and Errors.Is(err,'INVALID_FRAMEWORK_ADAPTER'))
local badCaps = validAdapter('qbox','qbx_core'); badCaps.metadata.capabilities.player.job='yes'
ok, err = Contract.Validate(badCaps); expect('Framework contract rejects non-boolean capability', ok == false and Errors.Is(err,'INVALID_FRAMEWORK_ADAPTER'))
local qbid = Identity.CanonicalCharacter('qbcore','ABC'); local qxid = Identity.CanonicalCharacter('qbox','ABC')
expect('Canonical identifiers namespace framework', qbid == 'qbcore:character:ABC' and qxid == 'qbox:character:ABC' and qbid ~= qxid)
local esxid = Identity.CanonicalCharacter('esx','char1:license:abc'); expect('ESX native identifier shape is preserved, not hardcoded', esxid == 'esx:character:char1:license:abc')

-- Framework detection ---------------------------------------------------------
local Framework = I.Managers.Framework
Framework.RegisterBuiltinAdapters()
env.resourceStates.es_extended='started'; Config.Framework='auto'
local selected = Framework.ResolveSelection('auto',{}); expect('Detect only es_extended -> ESX', selected == 'esx')
env.resourceStates.es_extended='missing'; env.resourceStates['qb-core']='started'; env.resourceStates.qbx_core='missing'
selected = Framework.ResolveSelection('auto',{}); expect('Detect only qb-core -> QBCore', selected == 'qbcore')
env.resourceStates.qbx_core='started'; env.resourceStates['qb-core']='started'; env.resourcePaths.qbx_core='/resources/qbx_core'; env.resourcePaths['qb-core']='/resources/qbx_core'
selected, err = Framework.ResolveSelection('auto',{}); expect('Qbox provide qb-core alias is not double-counted', selected == 'qbox' and err == nil)
env.resourcePaths['qb-core']='/resources/qb-core'
selected, err = Framework.ResolveSelection('auto',{}); expect('Actual qbx_core + actual qb-core fails closed', selected == nil and Errors.Is(err,'AMBIGUOUS_FRAMEWORK_INTEGRATION'))
selected, err = Framework.ResolveSelection('qbox',{}); expect('Manual qbox resolves real dual-framework installation', selected == 'qbox' and err == nil)
selected, err = Framework.ResolveSelection('auto',{'qbox','qbcore'}); expect('Explicit framework priority resolves ambiguity', selected == 'qbox' and err == nil)
env.resourceStates.qbx_core='missing'; env.resourceStates['qb-core']='missing'
selected, err = Framework.ResolveSelection('qbox',{}); expect('Configured missing framework returns FRAMEWORK_UNAVAILABLE', selected == nil and Errors.Is(err,'FRAMEWORK_UNAVAILABLE'))
Config.FrameworkAutoStandalone=false; selected,err=Framework.ResolveSelection('auto',{}); expect('Auto with no framework fails without explicit standalone policy', selected==nil and Errors.Is(err,'FRAMEWORK_UNAVAILABLE'))
Config.FrameworkAutoStandalone=true; selected,err=Framework.ResolveSelection('auto',{}); expect('Explicit auto-standalone policy permits standalone', selected=='standalone' and err==nil)

-- Official adapter normalization ---------------------------------------------
I = loadBase(false); Errors=I.Modules.Errors
env.resourceStates.es_extended='started'; env.versions.es_extended='1.15.2'; env.playerIdentifiers[1]={license='license:rockstar1'}
local xPlayer={identifier='char7:abcd',license='license:account1',name='Alice ESX',job={name='police',label='Police',grade=3,grade_name='sergeant',onDuty=true}}
function xPlayer.getIdentifier() return xPlayer.identifier end; function xPlayer.getName() return xPlayer.name end; function xPlayer.getJob() return xPlayer.job end
env.exportResources.es_extended={getSharedObject=function() return {GetPlayerFromId=function(src) return src==1 and xPlayer or nil end,IsPlayerLoaded=function(src) return src==1 end} end}
local esx=I.Adapters.Framework.esx; ok,err=esx.Initialize(); expect('ESX adapter initializes from official getSharedObject export',ok==true)
local v=esx.GetCharacterIdentifier(1); expect('ESX character identity uses active xPlayer identifier',v=='char7:abcd')
v=esx.GetAccountIdentifier(1); expect('ESX account identity kept separate',v=='license:account1')
v=esx.GetLicense(1); expect('ESX Rockstar license read separately',v=='license:rockstar1')
local job=esx.GetJob(1); expect('ESX job normalized to integer grade + duty',job.grade==3 and job.gradeName=='sergeant' and job.onDuty==true)

I = loadBase(false); env.resourceStates['qb-core']='started'; env.versions['qb-core']='1.3.0'; env.playerIdentifiers[2]={license='license:qb2'}
local qbPlayer={PlayerData={citizenid='ABC123',license='license:qb-account',charinfo={firstname='Bob',lastname='QB'},job={name='ambulance',label='EMS',grade={level=2,name='doctor'},onduty=false}}}
env.exportResources['qb-core']={GetCoreObject=function() return {Functions={GetPlayer=function(src) return src==2 and qbPlayer or nil end}} end}
local qb=I.Adapters.Framework.qbcore; ok=qb.Initialize(); expect('QBCore adapter initializes from official GetCoreObject export',ok==true)
v=qb.GetCharacterIdentifier(2); expect('QBCore character identity uses citizenid',v=='ABC123')
v=qb.GetAccountIdentifier(2); expect('QBCore account association remains separate from character',v=='license:qb-account')
job=qb.GetJob(2); expect('QBCore nested grade table normalized',job.grade==2 and job.gradeName=='doctor' and job.onDuty==false)

I = loadBase(false); env.resourceStates.qbx_core='started'; env.versions.qbx_core='1.24.0'; env.playerIdentifiers[3]={license='license:qbox3'}
local qxPlayer={PlayerData={citizenid='ABC123',userId=42,license='license:qbox-account',charinfo={firstname='Cara',lastname='Qbox'},job={name='police',label='Police',grade={level=4,name='lieutenant'},onduty=true},jobs={police=4,mechanic=1}}}
env.exportResources.qbx_core={GetPlayer=function(src) return src==3 and qxPlayer or nil end}
local qx=I.Adapters.Framework.qbox; ok=qx.Initialize(); expect('Qbox adapter initializes from qbx_core exports',ok==true)
v=qx.GetCharacterIdentifier(3); expect('Qbox character identity uses citizenid',v=='ABC123')
v=qx.GetAccountIdentifier(3); expect('Qbox account identity uses userId',v=='42')
job=qx.GetJob(3); expect('Qbox exposes only normalized primary job',job.name=='police' and job.grade==4)
expect('Qbox declares multi-job capability without exposing generic multi-job API',qx.metadata.capabilities.jobs.multiple==true)

I = loadBase(false); Config.Framework='standalone'; env.playerIdentifiers[4]={license='license:standalone4'}
local st=I.Adapters.Framework.standalone; st.Initialize(); v,err=st.GetCharacterIdentifier(4); expect('Standalone never substitutes license for character identity',v==nil and Errors.Is(err,'UNSUPPORTED_FEATURE'))
v=st.GetLicense(4); expect('Standalone may expose license capability separately',v=='license:standalone4')

-- Service mutation and ownership regressions ---------------------------------
I = loadBase(false); local Services=I.Managers.Services
local implementation={AddViolation=function(x) return 'owner:'..x end,nested={enabled=true}}
ok,err=Services.Register('justice',implementation,{version='1.0.0',apiVersion=1},'nexm_justice'); expect('Service registration succeeds',ok==true)
local view=Services.Get('justice'); expect('Read-only service facade remains callable',view.AddViolation('x')=='owner:x')
local mutateOk=pcall(function() view.AddViolation=function() return 'bad' end end); local viewAgain=Services.Get('justice'); expect('Service snapshot mutation cannot alter authoritative method',mutateOk==true and implementation.AddViolation('x')=='owner:x' and viewAgain.AddViolation('x')=='owner:x')
local nestedOk=pcall(function() view.nested.enabled=false end); local nestedAgain=Services.Get('justice'); expect('Service snapshot nested mutation cannot alter authoritative state',nestedOk==true and implementation.nested.enabled==true and nestedAgain.nested.enabled==true)
rawset(view,'AddViolation',function() return 'shadow' end); local freshView=Services.Get('justice'); expect('Rawset can only shadow one consumer facade, not registry/other consumers',freshView.AddViolation('x')=='owner:x')
ok,err=Services.Register('justice',{}, {version='1.0.0',apiVersion=1},'nexm_fake'); expect('Foreign service ownership collision remains REGISTRATION_CONFLICT',ok==false and Errors.Is(err,'REGISTRATION_CONFLICT'))
local removed=Services.CleanupOwner('nexm_justice'); ok=Services.Register('justice',{}, {version='1.0.0',apiVersion=1},'nexm_justice'); expect('Same resource can re-register cleanly after stop cleanup',removed==1 and ok==true)
expect('MigrationService has explicit privileged internal DB interface',I.Modules.InternalDB==I.Modules.DB)

-- Ready callback isolation ----------------------------------------------------
I = loadBase(false); local State=I.Modules.State; local S=I.Modules.Constants.STATES; local Ready=I.Modules.Readiness
State.Set(S.DATABASE); State.Set(S.MIGRATING); State.Set(S.FRAMEWORK); State.Set(S.PLATFORM)
local secondRan=false; Ready.Subscribe(function() error('dependent failure') end,'bad_resource'); Ready.Subscribe(function() secondRan=true end,'good_resource'); State.Set(S.READY); Ready.MarkReady()
expect('Ready callback failure does not block remaining subscribers',secondRan==true)
expect('Ready callback failure does not flip healthy Core to FAILED',State.Get()==S.READY)

-- Player cache, lifecycle, sessions ------------------------------------------
I = loadBase(false); Framework=I.Managers.Framework; State=I.Modules.State; S=I.Modules.Constants.STATES
local fakePlayers={ [12]={character='A',account='acctA',license='license:A',name='Alice',job={name='police',label='Police',grade=1,gradeName='officer',onDuty=true}} }
local cbs={}; local shutdowns,inits=0,0
local fa=validAdapter('qbox','qbx_core')
fa.metadata.capabilities.jobs.multiple=true
function fa.Initialize() inits=inits+1; return true,nil end
function fa.Shutdown() shutdowns=shutdowns+1; cbs={}; return true,nil end
function fa.GetPlayer(src) return fakePlayers[src] end
function fa.IsPlayerLoaded(src) return fakePlayers[src]~=nil end
function fa.GetCharacterIdentifier(src) local p=fakePlayers[src]; if not p then return nil,Errors.Create('PLAYER_NOT_FOUND','missing') end; return p.character,nil end
function fa.GetAccountIdentifier(src) return fakePlayers[src].account,nil end
function fa.GetLicense(src) return fakePlayers[src].license,nil end
function fa.GetCharacterName(src) return fakePlayers[src].name,nil end
function fa.GetJob(src) local p=fakePlayers[src]; if not p then return nil,Errors.Create('PLAYER_NOT_FOUND','missing') end; local j=p.job; return {name=j.name,label=j.label,grade=j.grade,gradeName=j.gradeName,onDuty=j.onDuty},nil end
function fa.SubscribePlayerLoaded(cb) cbs.load=cb; return true,nil end; function fa.SubscribePlayerUnloaded(cb) cbs.unload=cb; return true,nil end; function fa.SubscribeJobChanged(cb) cbs.job=cb; return true,nil end; function fa.SubscribeDutyChanged(cb) cbs.duty=cb; return true,nil end
I.Adapters.Framework={qbox=fa}; env.resourceStates.qbx_core='started'; Config.Framework='qbox'; Framework.RegisterBuiltinAdapters()
State.Set(S.DATABASE); State.Set(S.MIGRATING); State.Set(S.FRAMEWORK); ok,err=Framework.InitializeSelected(); expect('FrameworkManager initializes selected validated adapter',ok==true and Framework.GetName()=='qbox')
State.Set(S.PLATFORM); local Lifecycle=I.Modules.Lifecycle; Lifecycle.InitializeGlobal(); ok,err=Lifecycle.AttachAdapter(fa); expect('Lifecycle subscribes through formal adapter contract',ok==true)
local loads,unloads,jobs,duties=0,0,0,0
Lifecycle.Subscribe('playerLoaded',function() loads=loads+1 end,'nexm_test'); Lifecycle.Subscribe('playerUnloaded',function() unloads=unloads+1 end,'nexm_test'); Lifecycle.Subscribe('jobChanged',function() jobs=jobs+1 end,'nexm_test'); Lifecycle.Subscribe('dutyChanged',function() duties=duties+1 end,'nexm_test')
ok=Lifecycle.HandlePlayerLoaded(12); expect('Player load creates normalized cache',ok==true and I.Modules.PlayerCache.Count()==1)
local sessionA=I.Modules.PlayerCache.GetSession(12); local snap=I.Modules.Player.Get(12); expect('Canonical player identity constructed server-side',snap.identifier=='qbox:character:A' and snap.identity.character=='A')
snap.name='MALICIOUS'; local snapAgain=I.Modules.Player.Get(12); expect('Returned Player snapshot mutation cannot mutate internal cache',snapAgain.name=='Alice')
Lifecycle.HandlePlayerLoaded(12); expect('Duplicate playerLoaded for same character session is deduplicated',loads==1)
fakePlayers[12].job={name='ambulance',label='EMS',grade=2,gradeName='doctor',onDuty=true}; cbs.job(12); expect('Authoritative job refresh updates normalized cache and emits jobChanged',I.Modules.Player.Get(12).job.name=='ambulance' and jobs==1)
fakePlayers[12].job.onDuty=false; cbs.duty(12); expect('Duty update emits normalized dutyChanged once',I.Modules.Player.Get(12).job.onDuty==false and duties==1)
local staleOk,staleErr=I.Modules.PlayerCache.UpdateJob(12,{name='bad'},sessionA-1); expect('Stale character session update is rejected',staleOk==false and Errors.Is(staleErr,'STALE_CHARACTER_SESSION'))
cbs.unload(12,'logout'); Lifecycle.HandlePlayerUnloaded(12,'playerDropped'); expect('Framework unload + playerDropped overlap emits one logical unload',unloads==1 and I.Modules.PlayerCache.Count()==0)
fakePlayers[12].character='B'; fakePlayers[12].name='Bob'; Lifecycle.HandlePlayerLoaded(12); local sessionB=I.Modules.PlayerCache.GetSession(12)
expect('Character switch receives new characterSessionId',sessionB>sessionA)
expect('Old character index does not survive multichar switch',I.Modules.PlayerCache.IsOnline('qbox:character:A')==false and I.Modules.PlayerCache.IsOnline('qbox:character:B')==true)
Lifecycle.HandlePlayerUnloaded(12,'disconnect'); fakePlayers[12].character='C'; Lifecycle.HandlePlayerLoaded(12); expect('Source reuse cannot resurrect old character identity',I.Modules.Player.Get(12).identifier=='qbox:character:C' and I.Modules.PlayerCache.IsOnline('qbox:character:B')==false)

-- Reconstruction does not double-run logical gameplay load.
Lifecycle.HandlePlayerUnloaded(12,'test'); fakePlayers[21]={character='R',account='acctR',license='license:R',name='Reconstructed',job={name='police',label='Police',grade=0,gradeName='cadet',onDuty=false}}; env.players={21}
local beforeLoads=loads; local rok,count=Lifecycle.ReconstructPlayers(); expect('Core restart reconstruction caches already-loaded characters',rok==true and count==1 and I.Modules.PlayerCache.Get(21)~=nil)
expect('Reconstruction intentionally does not emit normal playerLoaded',loads==beforeLoads)

-- Runtime framework restart / sticky recovery --------------------------------
State.Set(S.READY); Framework.InstallResourceMonitoring(); env.resourceStates.qbx_core='stopped'; TriggerEvent('onResourceStop','qbx_core')
expect('Framework stop degrades Core and invalidates cache',State.Get()==S.DEGRADED and I.Modules.PlayerCache.Count()==0)
local _,fwErr=I.Modules.Player.Get(21); expect('Framework-dependent player calls fail closed while framework unavailable',Errors.Is(fwErr,'FRAMEWORK_UNAVAILABLE'))
env.resourceStates.qbx_core='started'; TriggerEvent('onResourceStart','qbx_core')
expect('Same sticky framework recovers to HEALTHY/READY',State.Get()==S.READY and Framework.GetName()=='qbox' and I.Modules.PlayerCache.Get(21)~=nil)
expect('Framework recovery reinitializes same adapter rather than hot-switching',inits>=2 and shutdowns>=1)
local recoveredSession=I.Modules.PlayerCache.GetSession(21); expect('Framework recovery creates fresh character sessions',type(recoveredSession)=='number' and recoveredSession>sessionB)

-- Public facade and ownership cleanup ----------------------------------------
I = loadBase(true); env.invoking='nexm_justice'; local api=GetCoreObject(); env.invoking='nexm_evidence'; local api2=GetCoreObject(); expect('GetCoreObject returns resource-bound facades',api~=api2)
local State2=I.Modules.State; local SS=I.Modules.Constants.STATES; Config.Framework='standalone'; State2.Set(SS.DATABASE); State2.Set(SS.MIGRATING); State2.Set(SS.FRAMEWORK); I.Managers.Framework.RegisterBuiltinAdapters(); I.Managers.Framework.InitializeSelected(); State2.Set(SS.PLATFORM); State2.Set(SS.READY)
ok=api.Events.OnPlayerLoaded(function() end); expect('Lifecycle registration public surface is ergonomic and owner-bound',ok==true)
local cleaned=I.Modules.Lifecycle.CleanupOwner('nexm_justice'); expect('Lifecycle registrations clean by ownerResource on resource restart',cleaned==1)

-- Bootstrap ordering regression ---------------------------------------------
I = loadBase(false); Config.Framework='standalone'; Config.FrameworkAutoStandalone=false; NEXM_TEST_BOOT_ORDER={}; dofile(root..'/server/bootstrap.lua')
local expected={'STATE:DATABASE','DB_CONNECT','STATE:MIGRATING','MIGRATION_TABLE','CORE_MIGRATIONS','ADAPTER_REGISTRY','STATE:FRAMEWORK','FRAMEWORK_INIT','STATE:PLATFORM','LIFECYCLE_SUBSCRIBE','PLAYER_CACHE_RECONSTRUCT','INVENTORY_INIT','NOTIFY_INIT','AUDIT_INIT','DIAGNOSTICS','STATE:READY','READY_EVENT'}
local orderOk=#NEXM_TEST_BOOT_ORDER==#expected
for idx,val in ipairs(expected) do orderOk=orderOk and NEXM_TEST_BOOT_ORDER[idx]==val end
expect('Core migrations remain before framework initialization in bootstrap',orderOk)
expect('Bootstrap reaches READY only after framework/lifecycle/cache foundation',I.Modules.State.Get()==I.Modules.Constants.STATES.READY)


-- Built-in adapter subscription cleanup / generation safety -------------------
I = loadBase(false); env.resourceStates['qb-core']='started'; env.playerIdentifiers[5]={license='license:5'}
local bp={PlayerData={citizenid='P5',license='license:5',charinfo={firstname='Five',lastname='Player'},job={name='police',label='Police',grade={level=1,name='officer'},onduty=true}}}
env.exportResources['qb-core']={GetCoreObject=function() return {Functions={GetPlayer=function(src) return src==5 and bp or nil end}} end}
qb=I.Adapters.Framework.qbcore; qb.Initialize(); local loadedEvents=0; qb.SubscribePlayerLoaded(function() loadedEvents=loadedEvents+1 end)
source=5; TriggerEvent('QBCore:Server:OnPlayerLoaded'); qb.Shutdown(); qb.Initialize(); qb.SubscribePlayerLoaded(function() loadedEvents=loadedEvents+1 end); TriggerEvent('QBCore:Server:OnPlayerLoaded'); source=0
expect('Framework adapter restart does not accumulate duplicate event emissions',loadedEvents==2)
expect('Adapter shutdown physically removes FiveM handlers when RemoveEventHandler is available',env.removedHandlers>=1)

-- Jobs/player lookup semantics ------------------------------------------------
I = loadBase(false); Framework=I.Managers.Framework; State=I.Modules.State; S=I.Modules.Constants.STATES
local fp={ [30]={character='J',account='acctJ',license='license:J',name='Jobs',job={name='police',label='Police',grade=3,gradeName='sergeant',onDuty=true}} }
fa=validAdapter('qbox','qbx_core'); function fa.GetPlayer(src) return fp[src] end; function fa.IsPlayerLoaded(src) return fp[src]~=nil end
function fa.GetCharacterIdentifier(src) return fp[src] and fp[src].character or nil end; function fa.GetAccountIdentifier(src) return fp[src].account,nil end; function fa.GetLicense(src) return fp[src].license,nil end; function fa.GetCharacterName(src) return fp[src].name,nil end
function fa.GetJob(src) local j=fp[src].job; return {name=j.name,label=j.label,grade=j.grade,gradeName=j.gradeName,onDuty=j.onDuty},nil end
I.Adapters.Framework={qbox=fa}; env.resourceStates.qbx_core='started'; Config.Framework='qbox'; Framework.RegisterBuiltinAdapters(); State.Set(S.DATABASE); State.Set(S.MIGRATING); State.Set(S.FRAMEWORK); Framework.InitializeSelected(); State.Set(S.PLATFORM); I.Modules.Lifecycle.AttachAdapter(fa); I.Modules.Lifecycle.HandlePlayerLoaded(30); State.Set(S.READY)
local Jobs=I.Modules.Jobs; local has=Jobs.Has(30,'police'); expect('Jobs.Has uses normalized primary job',has==true)
has=Jobs.HasAny(30,{'ambulance','police'}); expect('Jobs.HasAny works on normalized jobs',has==true)
has=Jobs.MinimumGrade(30,'police',3); expect('Jobs.MinimumGrade compares numeric normalized grade',has==true)
local duty=Jobs.IsOnDuty(30); expect('Jobs.IsOnDuty uses normalized duty capability',duty==true)
local canonical=I.Modules.Player.GetIdentifier(30); local src=I.Modules.Player.GetSource(canonical); expect('Player.GetSource resolves canonical character index',src==30)
local online=I.Modules.Player.IsOnline(canonical); expect('Player.IsOnline resolves canonical character index',online==true)

-- Cache collision and standalone public capability behavior ------------------
local Cache=I.Modules.PlayerCache; local conflictSession,conflictErr=Cache.Store(31,{source=31,identifier=canonical,identity={character='X',provider='qbox'},name='Conflict',framework='qbox',loaded=true})
expect('Canonical identity collision across sources fails closed',conflictSession==nil and Errors.Is(conflictErr,'IDENTITY_CONFLICT'))
I = loadBase(false); Config.Framework='standalone'; Framework=I.Managers.Framework; State=I.Modules.State; S=I.Modules.Constants.STATES; Framework.RegisterBuiltinAdapters(); State.Set(S.DATABASE); State.Set(S.MIGRATING); State.Set(S.FRAMEWORK); Framework.InitializeSelected(); State.Set(S.PLATFORM); State.Set(S.READY)
local pid,perr=I.Modules.Player.GetIdentifier(4); expect('Standalone Player.GetIdentifier returns UNSUPPORTED_FEATURE instead of license substitution',pid==nil and Errors.Is(perr,'UNSUPPORTED_FEATURE'))

-- Internal migration DB is usable before public READY ------------------------
I = loadBase(false); local M=I.Modules.Migrations; local IDB=I.Modules.InternalDB
local oldQ,oldT=IDB.Query,IDB.Transaction; IDB.Query=function(sql) if sql:find('SELECT `migration`',1,true) then return {},nil end return {},nil end; IDB.Transaction=function() return true,nil end
ok,err=M.Register('nexm_dep',{id='001_pre_ready',statements={'CREATE TABLE x (id INT)'}},'nexm_dep'); local runOk,runErr=M.Run('nexm_dep')
expect('MigrationService executes dependent migrations through privileged internal DB without public READY gate',ok==true and runOk==true and runErr==nil)
IDB.Query,IDB.Transaction=oldQ,oldT

-- onResourceStop ownership cleanup -------------------------------------------
I = loadBase(true); dofile(root..'/server/cleanup.lua'); local R=I.Managers.Resources; local Sv=I.Managers.Services; local F=I.Managers.Features; local L=I.Modules.Lifecycle
R.Register({version='1.0.0',requiresCore='>=1.0.0-0'},'nexm_restart'); Sv.Register('restart_service',{ping=function() return true end},{version='1.0.0',apiVersion=1},'nexm_restart'); F.Register('restart.feature',true,{},'nexm_restart'); L.Subscribe('playerLoaded',function() end,'nexm_restart')
TriggerEvent('onResourceStop','nexm_restart')
expect('onResourceStop cleans resource/service/feature ownership records',R.Get('nexm_restart')==nil and Sv.Has('restart_service')==false and F.Has('restart.feature')==false)
ok=Sv.Register('restart_service',{},{version='1.0.0',apiVersion=1},'nexm_restart'); expect('Resource can register same names again after real ownership cleanup path',ok==true)

-- Client normalized local state ----------------------------------------------
installStubs(); Config=nil; NEXM_INTERNAL=nil; GetCoreObject=nil; dofile(root..'/config.lua'); dofile(root..'/shared/init.lua'); dofile(root..'/shared/constants.lua'); dofile(root..'/shared/errors.lua'); dofile(root..'/shared/validation.lua'); dofile(root..'/shared/transport.lua'); dofile(root..'/shared/semver.lua'); dofile(root..'/shared/identity.lua'); dofile(root..'/shared/safe_data.lua'); dofile(root..'/shared/locale.lua'); dofile(root..'/shared/notify_contract.lua'); dofile(root..'/client/state.lua'); dofile(root..'/client/events.lua'); dofile(root..'/client/api.lua')
env.invoking='nexm_ui'; local clientApi=GetCoreObject(); local clientLoad=0; clientApi.Events.OnPlayerLoaded(function() clientLoad=clientLoad+1 end)
TriggerEvent('nexm_core:client:playerState',{identifier='qbox:character:CL',name='Client',job={name='police',label='Police',grade=1,gradeName='officer',onDuty=true},framework='qbox',loaded=true})
expect('Client normalized state is populated only from Core normalized update',clientApi.Player.IsLoaded()==true and clientLoad==1)
local localSnap=clientApi.Player.GetLocal(); localSnap.job.name='hacked'; expect('Client GetLocal returns sanitized copy, not mutable internal state',clientApi.Player.GetLocal().job.name=='police')
TriggerEvent('nexm_core:client:frameworkUnavailable'); expect('Framework degradation clears convenience-only client state',clientApi.Player.IsLoaded()==false)



local function runFinalRegression()
-- FINAL Phase-3 contract/regression expansion --------------------------------
-- Capability schema is canonical, explicit and fail-closed.
I = loadBase(false); Contract=I.Modules.FrameworkContract; Errors=I.Modules.Errors
local schema=Contract.CapabilitySchema()
expect('Final capability schema exposes explicit player duty field',schema.player and schema.player.duty=='boolean')
local missingCap=validAdapter('qbox','qbx_core'); missingCap.metadata.capabilities.jobs.multiple=nil
ok,err=Contract.Validate(missingCap); expect('Missing mandatory capability declaration is INVALID_FRAMEWORK_ADAPTER',ok==false and Errors.Is(err,'INVALID_FRAMEWORK_ADAPTER'))
local dutyWithoutJob=validAdapter('qbox','qbx_core'); dutyWithoutJob.metadata.capabilities.player.job=false; dutyWithoutJob.metadata.capabilities.player.duty=true
ok,err=Contract.Validate(dutyWithoutJob); expect('Duty capability cannot be true when normalized job capability is false',ok==false and Errors.Is(err,'INVALID_FRAMEWORK_ADAPTER'))
local multiWithoutJob=validAdapter('qbox','qbx_core'); multiWithoutJob.metadata.capabilities.player.job=false; multiWithoutJob.metadata.capabilities.player.duty=false; multiWithoutJob.metadata.capabilities.jobs.multiple=true
ok,err=Contract.Validate(multiWithoutJob); expect('Multi-job capability requires normalized primary job capability',ok==false and Errors.Is(err,'INVALID_FRAMEWORK_ADAPTER'))
local dutyMissingImpl=validAdapter('qbox','qbx_core'); dutyMissingImpl.SubscribeDutyChanged=nil
ok,err=Contract.Validate(dutyMissingImpl); expect('Adapter claiming duty support cannot omit duty lifecycle implementation',ok==false and Errors.Is(err,'INVALID_FRAMEWORK_ADAPTER'))
local optionalCap=validAdapter('qbox','qbx_core'); optionalCap.metadata.capabilities.player.optionalFuture=true
ok,err=Contract.Validate(optionalCap); expect('Unknown optional boolean capability is accepted',ok==true)
local invalidOptional=validAdapter('qbox','qbx_core'); invalidOptional.metadata.capabilities.player.optionalFuture='yes'
ok,err=Contract.Validate(invalidOptional); expect('Unknown optional capability still requires boolean/table contract type',ok==false and Errors.Is(err,'INVALID_FRAMEWORK_ADAPTER'))
local liar=validAdapter('qbox','qbx_core'); function liar.GetJob() return {name='police',label='Police',grade=1,gradeName='officer',onDuty=nil},nil end
local liarSnap,liarErr=I.Modules.Player.BuildSnapshot(1,liar); expect('Runtime lying duty adapter fails closed when no boolean duty state is returned',liarSnap==nil and Errors.Is(liarErr,'ADAPTER_ERROR'))
local noDuty=validAdapter('custom','custom_framework'); noDuty.metadata.capabilities.player.duty=false; function noDuty.GetJob() return {name='police',label='Police',grade=1,gradeName='officer',onDuty=true},nil end
local noDutySnap=I.Modules.Player.BuildSnapshot(1,noDuty); expect('Unsupported duty is normalized to nil in Player.job.onDuty',noDutySnap and noDutySnap.job and noDutySnap.job.onDuty==nil)

-- Duty API tri-state semantics ------------------------------------------------
I = loadBase(false); Framework=I.Managers.Framework; State=I.Modules.State; S=I.Modules.Constants.STATES; Errors=I.Modules.Errors
local dutyPlayers={ [60]={character='D60',account='acct60',license='license:60',name='Duty Player',job={name='police',label='Police',grade=1,gradeName='officer',onDuty=true}} }
fa=validAdapter('qbox','qbx_core'); function fa.GetPlayer(src) return dutyPlayers[src] end; function fa.IsPlayerLoaded(src) return dutyPlayers[src]~=nil end
function fa.GetCharacterIdentifier(src) local p=dutyPlayers[src]; return p and p.character or nil end; function fa.GetAccountIdentifier(src) local p=dutyPlayers[src]; return p and p.account or nil end; function fa.GetLicense(src) local p=dutyPlayers[src]; return p and p.license or nil end; function fa.GetCharacterName(src) local p=dutyPlayers[src]; return p and p.name or nil end
function fa.GetJob(src) local p=dutyPlayers[src]; if not p then return nil,Errors.Create('PLAYER_NOT_FOUND','missing') end; local j=p.job; return {name=j.name,label=j.label,grade=j.grade,gradeName=j.gradeName,onDuty=j.onDuty},nil end
I.Adapters.Framework={qbox=fa}; env.resourceStates.qbx_core='started'; Config.Framework='qbox'; Framework.RegisterBuiltinAdapters(); State.Set(S.DATABASE); State.Set(S.MIGRATING); State.Set(S.FRAMEWORK); Framework.InitializeSelected(); State.Set(S.PLATFORM); I.Modules.Lifecycle.AttachAdapter(fa); I.Modules.Lifecycle.HandlePlayerLoaded(60); State.Set(S.READY)
local dutyVal,dutyErr=I.Modules.Jobs.IsOnDuty(60); expect('Jobs.IsOnDuty supported on-duty returns true,nil',dutyVal==true and dutyErr==nil)
dutyPlayers[60].job.onDuty=false; I.Modules.Lifecycle.HandleDutyChanged(60); dutyVal,dutyErr=I.Modules.Jobs.IsOnDuty(60); expect('Jobs.IsOnDuty supported off-duty returns false,nil',dutyVal==false and dutyErr==nil)
dutyVal,dutyErr=I.Modules.Jobs.IsOnDuty(999); expect('Jobs.IsOnDuty missing player returns nil,PLAYER_NOT_FOUND',dutyVal==nil and Errors.Is(dutyErr,'PLAYER_NOT_FOUND'))
State.SetComponent('framework',I.Modules.Constants.HEALTH.UNAVAILABLE); dutyVal,dutyErr=I.Modules.Jobs.IsOnDuty(60); expect('Jobs.IsOnDuty framework unavailable returns nil,FRAMEWORK_UNAVAILABLE',dutyVal==nil and Errors.Is(dutyErr,'FRAMEWORK_UNAVAILABLE'))

I = loadBase(false); Framework=I.Managers.Framework; State=I.Modules.State; S=I.Modules.Constants.STATES; Errors=I.Modules.Errors
local unsupportedPlayer={character='U',account='acctU',license='license:U',name='Unsupported',job={name='police',label='Police',grade=0,gradeName='cadet',onDuty=true}}
fa=validAdapter('custom','custom_framework'); fa.metadata.capabilities.player.duty=false; function fa.GetPlayer(src) return src==61 and unsupportedPlayer or nil end; function fa.IsPlayerLoaded(src) return src==61 end
function fa.GetCharacterIdentifier() return 'U',nil end; function fa.GetAccountIdentifier() return 'acctU',nil end; function fa.GetLicense() return 'license:U',nil end; function fa.GetCharacterName() return 'Unsupported',nil end
function fa.GetJob() return {name='police',label='Police',grade=0,gradeName='cadet',onDuty=true},nil end
I.Adapters.Framework={custom=fa}; env.resourceStates.custom_framework='started'; Config.Framework='standalone'
-- Initialize fake adapter directly into manager via a supported qbox slot to keep public framework contract unchanged.
fa.metadata.name='qbox'; fa.metadata.resource='qbx_core'; I.Adapters.Framework={qbox=fa}; env.resourceStates.qbx_core='started'; Config.Framework='qbox'; Framework.RegisterBuiltinAdapters(); State.Set(S.DATABASE); State.Set(S.MIGRATING); State.Set(S.FRAMEWORK); Framework.InitializeSelected(); State.Set(S.PLATFORM); I.Modules.Lifecycle.AttachAdapter(fa); I.Modules.Lifecycle.HandlePlayerLoaded(61); State.Set(S.READY)
dutyVal,dutyErr=I.Modules.Jobs.IsOnDuty(61); expect('Jobs.IsOnDuty unsupported duty returns nil,UNSUPPORTED_FEATURE',dutyVal==nil and Errors.Is(dutyErr,'UNSUPPORTED_FEATURE'))
local unsupportedSnap=I.Modules.Player.Get(61); expect('Cached normalized Player.job.onDuty remains nil when duty unsupported',unsupportedSnap and unsupportedSnap.job.onDuty==nil)

-- QBCore authoritative duty/job lifecycle ------------------------------------
I = loadBase(false); Framework=I.Managers.Framework; State=I.Modules.State; S=I.Modules.Constants.STATES; Errors=I.Modules.Errors
local qbPlayers={
 [41]={PlayerData={citizenid='QB41',license='license:qb41',charinfo={firstname='On',lastname='Duty'},job={name='police',label='Police',grade={level=1,name='officer'},onduty=true}}},
 [42]={PlayerData={citizenid='QB42',license='license:qb42',charinfo={firstname='Off',lastname='Duty'},job={name='ambulance',label='EMS',grade={level=2,name='doctor'},onduty=false}}}
}
env.resourceStates['qb-core']='started'; env.resourcePaths['qb-core']='/resources/qb-core'; env.playerIdentifiers[41]={license='license:qb41'}; env.playerIdentifiers[42]={license='license:qb42'}
env.exportResources['qb-core']={GetCoreObject=function() return {Functions={GetPlayer=function(src) return qbPlayers[src] end}} end}
Config.Framework='qbcore'; Framework.RegisterBuiltinAdapters(); State.Set(S.DATABASE); State.Set(S.MIGRATING); State.Set(S.FRAMEWORK); Framework.InitializeSelected(); State.Set(S.PLATFORM); local L=I.Modules.Lifecycle; L.InitializeGlobal(); L.AttachAdapter(Framework.GetSelected())
local qbJobEvents,qbDutyEvents=0,0; L.Subscribe('jobChanged',function() qbJobEvents=qbJobEvents+1 end,'qb_test'); L.Subscribe('dutyChanged',function() qbDutyEvents=qbDutyEvents+1 end,'qb_test')
source=41; TriggerEvent('QBCore:Server:OnPlayerLoaded'); source=42; TriggerEvent('QBCore:Server:OnPlayerLoaded'); source=0
expect('QBCore player load preserves on-duty true',I.Modules.Player.Get(41).job.onDuty==true)
expect('QBCore player load preserves off-duty false',I.Modules.Player.Get(42).job.onDuty==false)
qbPlayers[41].PlayerData.job.onduty=false; TriggerEvent('QBCore:Server:SetDuty',41,false); expect('QBCore duty true->false updates normalized cache',I.Modules.Player.Get(41).job.onDuty==false and qbDutyEvents==1)
qbPlayers[41].PlayerData.job.onduty=true; TriggerEvent('QBCore:Server:SetDuty',41,true); expect('QBCore duty false->true updates normalized cache',I.Modules.Player.Get(41).job.onDuty==true and qbDutyEvents==2)
local beforeQBJobs,beforeQBDuty=qbJobEvents,qbDutyEvents; qbPlayers[41].PlayerData.job={name='ambulance',label='EMS',grade={level=3,name='chief'},onduty=false}; TriggerEvent('QBCore:Server:OnJobUpdate',41,qbPlayers[41].PlayerData.job)
expect('QBCore job change with duty change emits one job and one duty transition',qbJobEvents==beforeQBJobs+1 and qbDutyEvents==beforeQBDuty+1 and I.Modules.Player.Get(41).job.onDuty==false)
beforeQBJobs,beforeQBDuty=qbJobEvents,qbDutyEvents; qbPlayers[41].PlayerData.job={name='mechanic',label='Mechanic',grade={level=2,name='tech'},onduty=false}; TriggerEvent('QBCore:Server:OnJobUpdate',41,qbPlayers[41].PlayerData.job)
expect('QBCore job change without duty change emits job only',qbJobEvents==beforeQBJobs+1 and qbDutyEvents==beforeQBDuty)
beforeQBDuty=qbDutyEvents; qbPlayers[41].PlayerData.job.onduty=true; TriggerEvent('QBCore:Server:OnJobUpdate',41,qbPlayers[41].PlayerData.job); TriggerEvent('QBCore:Server:SetDuty',41,true)
expect('QBCore compatible job+duty signals deduplicate to one logical duty transition',qbDutyEvents==beforeQBDuty+1)
TriggerEvent('QBCore:Server:OnPlayerUnload',41); expect('QBCore logout after duty update removes normalized cache',I.Modules.PlayerCache.Get(41)==nil)

-- Qbox QB-compatible lifecycle must produce one logical transition ------------
I = loadBase(false); Framework=I.Managers.Framework; State=I.Modules.State; S=I.Modules.Constants.STATES
local qboxPlayers={ [51]={PlayerData={citizenid='QX51',userId=501,license='license:qx51',charinfo={firstname='Qbox',lastname='Player'},job={name='police',label='Police',grade={level=2,name='sergeant'},onduty=true},jobs={police=2,mechanic=1}}} }
env.resourceStates.qbx_core='started'; env.resourceStates['qb-core']='started'; env.resourcePaths.qbx_core='/resources/qbx_core'; env.resourcePaths['qb-core']='/resources/qbx_core'; env.playerIdentifiers[51]={license='license:qx51'}
env.exportResources.qbx_core={GetPlayer=function(src) return qboxPlayers[src] end}; Config.Framework='auto'; Framework.RegisterBuiltinAdapters(); State.Set(S.DATABASE); State.Set(S.MIGRATING); State.Set(S.FRAMEWORK); Framework.InitializeSelected(); State.Set(S.PLATFORM); L=I.Modules.Lifecycle; L.InitializeGlobal(); L.AttachAdapter(Framework.GetSelected())
local qxJobs,qxDuties=0,0; L.Subscribe('jobChanged',function() qxJobs=qxJobs+1 end,'qbox_test'); L.Subscribe('dutyChanged',function() qxDuties=qxDuties+1 end,'qbox_test')
source=51; TriggerEvent('QBCore:Server:OnPlayerLoaded'); source=0; local beforeQXDuty=qxDuties; qboxPlayers[51].PlayerData.job.onduty=false; TriggerEvent('QBCore:Server:OnJobUpdate',51,qboxPlayers[51].PlayerData.job); TriggerEvent('QBCore:Server:SetDuty',51,false)
expect('Selected Qbox adapter deduplicates QB-compatible duty signals',Framework.GetName()=='qbox' and qxDuties==beforeQXDuty+1 and I.Modules.Player.Get(51).job.onDuty==false)
local beforeQXJobs=qxJobs; beforeQXDuty=qxDuties; qboxPlayers[51].PlayerData.job={name='mechanic',label='Mechanic',grade={level=1,name='junior'},onduty=true}; TriggerEvent('QBCore:Server:OnJobUpdate',51,qboxPlayers[51].PlayerData.job); TriggerEvent('QBCore:Server:SetDuty',51,true)
expect('Qbox primary job plus duty transition emits exactly one of each logical event',qxJobs==beforeQXJobs+1 and qxDuties==beforeQXDuty+1)

-- Formal qbx_core provide 'qb-core' alias scenarios A-D -----------------------
I = loadBase(false); Framework=I.Managers.Framework; Errors=I.Modules.Errors; Framework.RegisterBuiltinAdapters(); env.resourceStates.qbx_core='started'; env.resourceStates['qb-core']='started'
env.resourcePaths.qbx_core='/resources/qbx_core'; env.resourcePaths['qb-core']='/resources/qbx_core'; selected,err=Framework.ResolveSelection('auto',{}); expect('Qbox alias A: qbx_core-only provider resolves AUTO to Qbox',selected=='qbox' and err==nil)
env.resourcePaths['qb-core']='/resources/qb-core'; selected,err=Framework.ResolveSelection('auto',{}); expect('Qbox alias B: independent qbx_core + qb-core fails closed',selected==nil and Errors.Is(err,'AMBIGUOUS_FRAMEWORK_INTEGRATION'))
selected,err=Framework.ResolveSelection('qbox',{}); expect('Qbox alias C: explicit qbox selects Qbox in dual-framework install',selected=='qbox' and err==nil)
selected,err=Framework.ResolveSelection('qbcore',{}); expect('Qbox alias D: explicit qbcore selects independent QBCore candidate',selected=='qbcore' and err==nil)
env.resourcePaths['qb-core']='/resources/qbx_core'; selected,err=Framework.ResolveSelection('qbcore',{}); expect('Qbox provided alias alone cannot satisfy explicit independent qbcore selection',selected==nil and Errors.Is(err,'FRAMEWORK_UNAVAILABLE'))

-- Aggressive adapter restart/removal + generation guard -----------------------
I = loadBase(false); env.resourceStates.qbx_core='started'; env.exportResources.qbx_core={GetPlayer=function() return nil end}; local qa=I.Adapters.Framework.qbox
local hc={load=0,unload=0,job=0,duty=0}
local function subscribeAllQbox()
 qa.SubscribePlayerLoaded(function() hc.load=hc.load+1 end); qa.SubscribePlayerUnloaded(function() hc.unload=hc.unload+1 end); qa.SubscribeJobChanged(function() hc.job=hc.job+1 end); qa.SubscribeDutyChanged(function() hc.duty=hc.duty+1 end)
end
local function fireAllQbox()
 source=70; TriggerEvent('QBCore:Server:OnPlayerLoaded'); source=0; TriggerEvent('QBCore:Server:OnJobUpdate',70,{}); TriggerEvent('QBCore:Server:SetDuty',70,true); TriggerEvent('QBCore:Server:OnPlayerUnload',70)
end
qa.Initialize(); subscribeAllQbox(); fireAllQbox(); qa.Shutdown(); qa.Initialize(); subscribeAllQbox(); fireAllQbox(); qa.Shutdown(); qa.Initialize(); subscribeAllQbox(); fireAllQbox()
expect('Qbox repeated stop/start cycles do not accumulate load handlers',hc.load==3)
expect('Qbox repeated stop/start cycles do not accumulate unload/job/duty handlers',hc.unload==3 and hc.job==3 and hc.duty==3)

I = loadBase(false); env.resourceStates.qbx_core='started'; env.exportResources.qbx_core={GetPlayer=function() return nil end}; qa=I.Adapters.Framework.qbox; local guarded=0
qa.Initialize(); qa.SubscribePlayerLoaded(function() guarded=guarded+1 end); source=71; TriggerEvent('QBCore:Server:OnPlayerLoaded'); source=0
RemoveEventHandler=function() error('synthetic removal failure') end; qa.Shutdown(); qa.Initialize(); qa.SubscribePlayerLoaded(function() guarded=guarded+1 end); source=71; TriggerEvent('QBCore:Server:OnPlayerLoaded'); source=0
expect('Generation guard neutralizes stale handler when physical removal fails',guarded==2)

-- Character-session late job/duty/async regression ----------------------------
I = loadBase(false); Framework=I.Managers.Framework; State=I.Modules.State; S=I.Modules.Constants.STATES; Errors=I.Modules.Errors
local racePlayers={ [75]={character='A',account='acctA',license='license:A',name='A',job={name='police',label='Police',grade=1,gradeName='officer',onDuty=true}} }
fa=validAdapter('qbox','qbx_core'); function fa.GetPlayer(src) return racePlayers[src] end; function fa.IsPlayerLoaded(src) return racePlayers[src]~=nil end
function fa.GetCharacterIdentifier(src) return racePlayers[src] and racePlayers[src].character or nil end; function fa.GetAccountIdentifier(src) return racePlayers[src].account,nil end; function fa.GetLicense(src) return racePlayers[src].license,nil end; function fa.GetCharacterName(src) return racePlayers[src].name,nil end
function fa.GetJob(src) local j=racePlayers[src].job; return {name=j.name,label=j.label,grade=j.grade,gradeName=j.gradeName,onDuty=j.onDuty},nil end
I.Adapters.Framework={qbox=fa}; env.resourceStates.qbx_core='started'; Config.Framework='qbox'; Framework.RegisterBuiltinAdapters(); State.Set(S.DATABASE); State.Set(S.MIGRATING); State.Set(S.FRAMEWORK); Framework.InitializeSelected(); State.Set(S.PLATFORM); L=I.Modules.Lifecycle; L.AttachAdapter(fa); L.HandlePlayerLoaded(75); State.Set(S.READY)
local raceCache=I.Modules.PlayerCache; local sessionOld=raceCache.GetSession(75); L.HandlePlayerUnloaded(75,'logout'); racePlayers[75]={character='B',account='acctB',license='license:B',name='B',job={name='ambulance',label='EMS',grade=2,gradeName='doctor',onDuty=false}}; L.HandlePlayerLoaded(75); local sessionNew=raceCache.GetSession(75)
local staleJobOk,staleJobErr=raceCache.UpdateJob(75,{name='lateA',label='Late A',grade=9,gradeName='bad',onDuty=true},sessionOld); expect('Late character-A job result is rejected after character-B session loads',staleJobOk==false and Errors.Is(staleJobErr,'STALE_CHARACTER_SESSION') and raceCache.Get(75).job.name=='ambulance')
local staleDutyOk,staleDutyErr=raceCache.UpdateJob(75,{name='ambulance',label='EMS',grade=2,gradeName='doctor',onDuty=true},sessionOld); expect('Late character-A duty result is rejected after character-B session loads',staleDutyOk==false and Errors.Is(staleDutyErr,'STALE_CHARACTER_SESSION') and raceCache.Get(75).job.onDuty==false)
expect('Old asynchronous lifecycle session token is no longer current',sessionNew>sessionOld and L.IsCurrentSession(75,sessionOld)==false and L.IsCurrentSession(75,sessionNew)==true)

-- Source reuse must leave no source-scoped character state --------------------
I = loadBase(false); Framework=I.Managers.Framework; State=I.Modules.State; S=I.Modules.Constants.STATES
local reuse={ [15]={character='A15',account='acctA15',license='license:A15',name='A15',job={name='police',label='Police',grade=1,gradeName='officer',onDuty=true}} }
fa=validAdapter('qbox','qbx_core'); function fa.GetPlayer(src) return reuse[src] end; function fa.IsPlayerLoaded(src) return reuse[src]~=nil end; function fa.GetCharacterIdentifier(src) return reuse[src] and reuse[src].character or nil end; function fa.GetAccountIdentifier(src) return reuse[src].account,nil end; function fa.GetLicense(src) return reuse[src].license,nil end; function fa.GetCharacterName(src) return reuse[src].name,nil end; function fa.GetJob(src) local j=reuse[src].job; return {name=j.name,label=j.label,grade=j.grade,gradeName=j.gradeName,onDuty=j.onDuty},nil end
I.Adapters.Framework={qbox=fa}; env.resourceStates.qbx_core='started'; Config.Framework='qbox'; Framework.RegisterBuiltinAdapters(); State.Set(S.DATABASE); State.Set(S.MIGRATING); State.Set(S.FRAMEWORK); Framework.InitializeSelected(); State.Set(S.PLATFORM); L=I.Modules.Lifecycle; L.AttachAdapter(fa); L.HandlePlayerLoaded(15); local reuseSessionA=I.Modules.PlayerCache.GetSession(15); L.HandlePlayerUnloaded(15,'disconnect')
expect('Source reuse cleanup removes old cache/session/index before source is reused',I.Modules.PlayerCache.Get(15)==nil and I.Modules.PlayerCache.GetSession(15)==nil and I.Modules.PlayerCache.IsOnline('qbox:character:A15')==false)
reuse[15]={character='B15',account='acctB15',license='license:B15',name='B15',job={name='mechanic',label='Mechanic',grade=2,gradeName='tech',onDuty=false}}; L.HandlePlayerLoaded(15); local reuseB=I.Modules.Player.Get(15)
expect('Reused source receives only new character identity/job/duty/session',reuseB.identifier=='qbox:character:B15' and reuseB.job.name=='mechanic' and reuseB.job.onDuty==false and I.Modules.PlayerCache.GetSession(15)>reuseSessionA)

-- Deep server snapshot immutability -------------------------------------------
local mutated=I.Modules.Player.Get(15); mutated.job.grade=999; mutated.job.onDuty=true; mutated.identity.character='FAKE'; mutated.name='MUTATED'; local authoritative=I.Modules.Player.Get(15)
expect('Server Player snapshot deep mutation cannot alter job/identity/name cache',authoritative.job.grade==2 and authoritative.job.onDuty==false and authoritative.identity.character=='B15' and authoritative.name=='B15')

-- Deep service read-only regression ------------------------------------------
I = loadBase(false); local DeepServices=I.Managers.Services; local deepImpl={nested={settings={flags={enabled=true}}},ping=function() return 'pong' end}; DeepServices.Register('deep',deepImpl,{version='1.0.0',apiVersion=1},'nexm_deep'); local deepView=DeepServices.Get('deep')
local deepMutate=pcall(function() deepView.nested.settings.flags.enabled=false end); expect('Service deep snapshot mutation cannot alter authoritative state',deepMutate==true and deepImpl.nested.settings.flags.enabled==true and DeepServices.Get('deep').nested.settings.flags.enabled==true and DeepServices.Get('deep').ping()=='pong')

-- Ownership cleanup includes pending readiness + lifecycle and re-registration -
I = loadBase(true); dofile(root..'/server/cleanup.lua'); local RR=I.Managers.Resources; local RS=I.Managers.Services; local RF=I.Managers.Features; local RReady=I.Modules.Readiness; local RL=I.Modules.Lifecycle; local readyFired=0
RR.Register({version='1.0.0',requiresCore='>=1.0.0-0'},'nexm_owned'); RS.Register('owned_service',{}, {version='1.0.0',apiVersion=1},'nexm_owned'); RF.Register('owned.feature',true,{},'nexm_owned'); RReady.Subscribe(function() readyFired=readyFired+1 end,'nexm_owned'); RL.Subscribe('playerLoaded',function() end,'nexm_owned'); TriggerEvent('onResourceStop','nexm_owned')
expect('Resource stop removes service/feature/resource registrations and pending owner subscriptions',RR.Get('nexm_owned')==nil and RS.Has('owned_service')==false and RF.Has('owned.feature')==false and RReady.CleanupOwner('nexm_owned')==0 and RL.CleanupOwner('nexm_owned')==0)
local rst=I.Modules.State; local rss=I.Modules.Constants.STATES; rst.Set(rss.DATABASE); rst.Set(rss.MIGRATING); rst.Set(rss.FRAMEWORK); rst.Set(rss.PLATFORM); rst.Set(rss.READY); RReady.MarkReady(); expect('Cleaned pending ready subscriber never executes after owner resource stops',readyFired==0)
local r1=RS.Register('owned_service',{}, {version='1.0.0',apiVersion=1},'nexm_owned'); local r2=RF.Register('owned.feature',true,{},'nexm_owned'); local r3=RReady.Subscribe(function() end,'nexm_owned'); local r4=RL.Subscribe('playerLoaded',function() end,'nexm_owned'); expect('Same resource can re-register owned names/subscriptions after restart cleanup',r1==true and r2==true and r3==true and r4==true)
local foreignOk,foreignErr=RS.Register('owned_service',{}, {version='1.0.0',apiVersion=1},'nexm_foreign'); expect('Foreign resource still cannot overwrite active re-registered service',foreignOk==false and I.Modules.Errors.Is(foreignErr,'REGISTRATION_CONFLICT'))

-- Framework degradation/recovery remains sticky even if another framework appears
I = loadBase(false); Framework=I.Managers.Framework; State=I.Modules.State; S=I.Modules.Constants.STATES; Errors=I.Modules.Errors
local dgPlayers={ [80]={character='DG',account='acctDG',license='license:DG',name='Degrade',job={name='police',label='Police',grade=1,gradeName='officer',onDuty=true}} }; local dgCallbacks={}; local dgInit,dgShutdown=0,0
local qboxFake=validAdapter('qbox','qbx_core'); function qboxFake.Initialize() dgInit=dgInit+1; return true,nil end; function qboxFake.Shutdown() dgShutdown=dgShutdown+1; dgCallbacks={}; return true,nil end; function qboxFake.GetPlayer(src) return dgPlayers[src] end; function qboxFake.IsPlayerLoaded(src) return dgPlayers[src]~=nil end; function qboxFake.GetCharacterIdentifier(src) return dgPlayers[src] and dgPlayers[src].character or nil end; function qboxFake.GetAccountIdentifier(src) return dgPlayers[src].account,nil end; function qboxFake.GetLicense(src) return dgPlayers[src].license,nil end; function qboxFake.GetCharacterName(src) return dgPlayers[src].name,nil end; function qboxFake.GetJob(src) local j=dgPlayers[src].job; return {name=j.name,label=j.label,grade=j.grade,gradeName=j.gradeName,onDuty=j.onDuty},nil end; function qboxFake.SubscribePlayerLoaded(cb) dgCallbacks.load=cb; return true,nil end; function qboxFake.SubscribePlayerUnloaded(cb) dgCallbacks.unload=cb; return true,nil end; function qboxFake.SubscribeJobChanged(cb) dgCallbacks.job=cb; return true,nil end; function qboxFake.SubscribeDutyChanged(cb) dgCallbacks.duty=cb; return true,nil end
local qbOther=validAdapter('qbcore','qb-core'); I.Adapters.Framework={qbox=qboxFake,qbcore=qbOther}; env.resourceStates.qbx_core='started'; env.resourceStates['qb-core']='missing'; Config.Framework='qbox'; Framework.RegisterBuiltinAdapters(); State.Set(S.DATABASE); State.Set(S.MIGRATING); State.Set(S.FRAMEWORK); Framework.InitializeSelected(); State.Set(S.PLATFORM); L=I.Modules.Lifecycle; L.InitializeGlobal(); L.AttachAdapter(qboxFake); L.HandlePlayerLoaded(80); State.Set(S.READY); I.Modules.Diagnostics.Initialize(); Framework.InstallResourceMonitoring(); local dgSession=I.Modules.PlayerCache.GetSession(80)
env.resourceStates.qbx_core='stopped'; env.resourceStates['qb-core']='started'; TriggerEvent('onResourceStop','qbx_core'); local _,dgPlayerErr=I.Modules.Player.Get(80); local _,dgJobErr=I.Modules.Jobs.Get(80); expect('Framework degradation invalidates cache and Player/Jobs fail with FRAMEWORK_UNAVAILABLE',I.Modules.PlayerCache.Count()==0 and Errors.Is(dgPlayerErr,'FRAMEWORK_UNAVAILABLE') and Errors.Is(dgJobErr,'FRAMEWORK_UNAVAILABLE'))
local diagOk=pcall(env.commands['nexm:status'],0,{}); expect('Diagnostics remain operational while framework is degraded',diagOk==true and State.Get()==S.DEGRADED and Framework.GetName()=='qbox')
expect('Framework degradation never hot-switches to newly available QBCore',Framework.GetName()=='qbox')
env.resourceStates.qbx_core='started'; env.players={80}; TriggerEvent('onResourceStart','qbx_core'); expect('Same framework recovery rebuilds cache with fresh session and HEALTHY state',Framework.GetName()=='qbox' and State.Get()==S.READY and I.Modules.PlayerCache.Get(80)~=nil and I.Modules.PlayerCache.GetSession(80)>dgSession and I.Modules.State.GetComponent('framework').state==I.Modules.Constants.HEALTH.HEALTHY)
local recoveryJobs=0; L.Subscribe('jobChanged',function() recoveryJobs=recoveryJobs+1 end,'recovery_test'); dgPlayers[80].job.name='ambulance'; dgPlayers[80].job.label='EMS'; dgCallbacks.job(80); expect('Recovered adapter lifecycle handlers emit one normalized job transition',recoveryJobs==1)

-- Existing players on Core restart reconstruct both indexes without load emit --
I = loadBase(false); Framework=I.Managers.Framework; State=I.Modules.State; S=I.Modules.Constants.STATES
local recPlayers={ [81]={character='R81',account='a81',license='l81',name='R81',job={name='police',label='Police',grade=1,gradeName='one',onDuty=true}}, [82]={character='R82',account='a82',license='l82',name='R82',job={name='ambulance',label='EMS',grade=2,gradeName='two',onDuty=false}} }
fa=validAdapter('qbox','qbx_core'); function fa.GetPlayer(src) return recPlayers[src] end; function fa.IsPlayerLoaded(src) return recPlayers[src]~=nil end; function fa.GetCharacterIdentifier(src) return recPlayers[src] and recPlayers[src].character or nil end; function fa.GetAccountIdentifier(src) return recPlayers[src].account,nil end; function fa.GetLicense(src) return recPlayers[src].license,nil end; function fa.GetCharacterName(src) return recPlayers[src].name,nil end; function fa.GetJob(src) local j=recPlayers[src].job; return {name=j.name,label=j.label,grade=j.grade,gradeName=j.gradeName,onDuty=j.onDuty},nil end
I.Adapters.Framework={qbox=fa}; env.resourceStates.qbx_core='started'; env.players={81,82}; Config.Framework='qbox'; Framework.RegisterBuiltinAdapters(); State.Set(S.DATABASE); State.Set(S.MIGRATING); State.Set(S.FRAMEWORK); Framework.InitializeSelected(); State.Set(S.PLATFORM); L=I.Modules.Lifecycle; L.AttachAdapter(fa); local recLoads=0; L.Subscribe('playerLoaded',function() recLoads=recLoads+1 end,'rec_test'); local recOk,recCount=L.ReconstructPlayers()
expect('Core restart reconstruction discovers all already-loaded characters',recOk==true and recCount==2 and I.Modules.PlayerCache.Count()==2)
expect('Core restart reconstruction populates source and canonical indexes consistently',I.Modules.PlayerCache.GetSource('qbox:character:R81')==81 and I.Modules.PlayerCache.GetSource('qbox:character:R82')==82 and I.Modules.PlayerCache.Get(81).identifier=='qbox:character:R81')
expect('Core restart reconstruction assigns fresh sessions without normal playerLoaded semantics',type(I.Modules.PlayerCache.GetSession(81))=='number' and type(I.Modules.PlayerCache.GetSession(82))=='number' and recLoads==0)

-- Player-cache index atomicity + duplicate identity conflict -------------------
I = loadBase(false); local PC=I.Modules.PlayerCache; Errors=I.Modules.Errors
local sa=PC.Store(1,{source=1,identifier='qbox:character:A',identity={character='A',provider='qbox'},name='A',job={name='police',grade=1,onDuty=true},framework='qbox',loaded=true}); local sb=PC.Store(2,{source=2,identifier='qbox:character:B',identity={character='B',provider='qbox'},name='B',job={name='ems',grade=1,onDuty=false},framework='qbox',loaded=true})
expect('Player cache indexes are consistent after independent loads',sa~=nil and sb~=nil and PC.GetSource('qbox:character:A')==1 and PC.GetSource('qbox:character:B')==2)
local conflict,conflictE=PC.Store(1,{source=1,identifier='qbox:character:B',identity={character='B',provider='qbox'},name='bad',framework='qbox',loaded=true}); expect('Duplicate canonical character on second source returns IDENTITY_CONFLICT',conflict==nil and Errors.Is(conflictE,'IDENTITY_CONFLICT'))
expect('Rejected identity conflict is atomic and preserves both previous indexes',PC.GetSource('qbox:character:A')==1 and PC.GetSource('qbox:character:B')==2 and PC.Get(1).identifier=='qbox:character:A')
PC.Remove(1); expect('Player unload removes both source and canonical index',PC.Get(1)==nil and PC.GetSource('qbox:character:A')==nil)
PC.ClearAll(); expect('Framework degradation/clear removes all source and canonical indexes',PC.Count()==0 and PC.GetSource('qbox:character:B')==nil)

-- Canonical identifiers remain opaque when native IDs contain additional colons
I = loadBase(false); local opaque,opaqueErr=I.Modules.Identity.CanonicalCharacter('esx','char1:license:abc:def'); expect('Canonical ESX identifier preserves native colon-rich identifier opaquely',opaque=='esx:character:char1:license:abc:def' and opaqueErr==nil)

-- Public Player/Jobs source validation ----------------------------------------
I = loadBase(false); Framework=I.Managers.Framework; State=I.Modules.State; S=I.Modules.Constants.STATES; Errors=I.Modules.Errors
local inputPlayers={ [90]={character='IN90',account='acct90',license='license:90',name='Input',job={name='police',label='Police',grade=1,gradeName='officer',onDuty=true}} }
fa=validAdapter('qbox','qbx_core'); function fa.GetPlayer(src) return inputPlayers[src] end; function fa.IsPlayerLoaded(src) return inputPlayers[src]~=nil end; function fa.GetCharacterIdentifier(src) return inputPlayers[src] and inputPlayers[src].character or nil end; function fa.GetAccountIdentifier(src) return inputPlayers[src].account,nil end; function fa.GetLicense(src) return inputPlayers[src].license,nil end; function fa.GetCharacterName(src) return inputPlayers[src].name,nil end; function fa.GetJob(src) local j=inputPlayers[src].job; return {name=j.name,label=j.label,grade=j.grade,gradeName=j.gradeName,onDuty=j.onDuty},nil end
I.Adapters.Framework={qbox=fa}; env.resourceStates.qbx_core='started'; Config.Framework='qbox'; Framework.RegisterBuiltinAdapters(); State.Set(S.DATABASE); State.Set(S.MIGRATING); State.Set(S.FRAMEWORK); Framework.InitializeSelected(); State.Set(S.PLATFORM); I.Modules.Lifecycle.AttachAdapter(fa); I.Modules.Lifecycle.HandlePlayerLoaded(90); State.Set(S.READY)
local validInteger,validIntegerErr=I.Modules.Player.Get(90); expect('Player source accepts loaded integer number',validInteger~=nil and validIntegerErr==nil)
local validIntegralFloat,validIntegralFloatErr=I.Modules.Player.Get(90.0); expect('Player source accepts integral Lua number 90.0',validIntegralFloat~=nil and validIntegralFloatErr==nil)
local strictSourceCases={
 {label='numeric string',value='90'}, {label='leading-zero numeric string',value='090'}, {label='fraction',value=90.5},
 {label='zero',value=0}, {label='negative',value=-1}, {label='NaN',value=0/0}, {label='Infinity',value=math.huge}
}
for _,case in ipairs(strictSourceCases) do
 local result,e=I.Modules.Player.Get(case.value)
 expect('Player.Get rejects '..case.label..' source',result==nil and Errors.Is(e,'INVALID_ARGUMENT'),type(e)=='table' and e.code or tostring(e))
 local exists,ee=I.Modules.Player.Exists(case.value)
 expect('Player.Exists rejects '..case.label..' source',exists==false and Errors.Is(ee,'INVALID_ARGUMENT'),type(ee)=='table' and ee.code or tostring(ee))
end
local missingPlayer,missingPlayerErr=I.Modules.Player.Get(999); expect('Valid but nonexistent source returns PLAYER_NOT_FOUND',missingPlayer==nil and Errors.Is(missingPlayerErr,'PLAYER_NOT_FOUND'))
for _,api in ipairs({
 {'GetIdentifier',I.Modules.Player.GetIdentifier}, {'GetCharacterIdentifier',I.Modules.Player.GetCharacterIdentifier}, {'GetAccountIdentifier',I.Modules.Player.GetAccountIdentifier},
 {'GetLicense',I.Modules.Player.GetLicense}, {'GetCharacterName',I.Modules.Player.GetCharacterName}, {'GetJob',I.Modules.Player.GetJob}, {'GetJobGrade',I.Modules.Player.GetJobGrade}
}) do local value,e=api[2]('90'); expect('Player.'..api[1]..' rejects numeric-string source',value==nil and Errors.Is(e,'INVALID_ARGUMENT'),type(e)=='table' and e.code or tostring(e)) end
local badJob,badJobErr=I.Modules.Jobs.Get('90'); expect('Jobs.Get rejects string source instead of coercing it',badJob==nil and Errors.Is(badJobErr,'INVALID_ARGUMENT'))
local badHas,badHasErr=I.Modules.Jobs.Has('90','police'); expect('Jobs.Has rejects string source instead of coercing it',badHas==false and Errors.Is(badHasErr,'INVALID_ARGUMENT'))
local badMin,badMinErr=I.Modules.Jobs.MinimumGrade('90','police',0); expect('Jobs.MinimumGrade rejects string source instead of coercing it',badMin==false and Errors.Is(badMinErr,'INVALID_ARGUMENT'))

-- Production module syntax/load coverage under the available Lua harness ------
local productionFiles={
 'config.lua','shared/init.lua','shared/constants.lua','shared/errors.lua','shared/validation.lua','shared/transport.lua','shared/semver.lua','shared/identity.lua',
 'server/state.lua','server/logger.lua','server/ownership.lua','server/database.lua','server/migrations.lua','server/migrations/core.lua','server/registry_base.lua',
 'server/managers/resources.lua','server/managers/services.lua','server/managers/features.lua','server/managers/integrations.lua','server/readiness.lua','server/framework_contract.lua',
 'adapters/framework/esx.lua','adapters/framework/qbcore.lua','adapters/framework/qbox.lua','adapters/framework/standalone.lua','server/managers/framework.lua','server/player_cache.lua','server/player.lua','server/jobs.lua','server/lifecycle.lua','server/diagnostics.lua','server/api.lua','server/cleanup.lua','server/bootstrap.lua',
 'client/state.lua','client/events.lua','client/api.lua'
}
local compileOk=true
for _,file in ipairs(productionFiles) do local fn=loadfile(root..'/'..file); if not fn then compileOk=false; break end end
expect('All Phase-2/3 production Lua modules compile under the test harness',compileOk)

end
runFinalRegression()

print(('PHASE3 TESTS: %d, FAILED: %d'):format(total,failed))
if failed>0 then os.exit(1) end
