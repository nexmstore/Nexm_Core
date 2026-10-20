local root = arg[1] or '.'
local total, failed = 0, 0
local function expect(name, condition, detail)
    total = total + 1
    if condition then print('[PASS] '..name) else failed = failed + 1; print('[FAIL] '..name..(detail and (' :: '..tostring(detail)) or '')) end
end

local env = {}
local function installStubs()
    env = {
        resourceStates = { oxmysql = 'started' }, resourcePaths = {}, versions = {}, playerIdentifiers = {}, players = {},
        events = {}, netEvents = {}, clientEvents = {}, serverEvents = {}, commands = {}, invoking = nil, exportResources = {},
        nextHandler = 0, removedHandlers = 0, aces = {}, timer = 1000, timeouts = {}, stopCalls = {}, awaitHook = nil
    }
    json = { encode = function() return '{}' end, decode = function() return {} end }
    function GetCurrentResourceName() return 'nexm_core' end
    function GetInvokingResource() return env.invoking end
    function GetResourceState(name) return env.resourceStates[name] or 'missing' end
    function GetResourcePath(name) return env.resourcePaths[name] or ('/resources/'..name) end
    function GetResourceMetadata(name, key) if key == 'version' then return env.versions[name] end return nil end
    function GetPlayers() local o = {}; for _, s in ipairs(env.players) do o[#o+1] = tostring(s) end; return o end
    function GetPlayerIdentifierByType(src, typ) local t = env.playerIdentifiers[tonumber(src)] or {}; return t[typ] end
    function GetPlayerName(src) return 'Player'..tostring(src) end
    function GetGameTimer() return env.timer end
    function IsPlayerAceAllowed(src, perm) return env.aces[tonumber(src)] and env.aces[tonumber(src)][perm] == true or false end
    function RegisterCommand(name, cb) env.commands[name] = cb end
    function StopResource(name) env.stopCalls[#env.stopCalls+1] = name end
    function AddEventHandler(name, cb)
        env.nextHandler = env.nextHandler + 1
        env.events[name] = env.events[name] or {}
        env.events[name][env.nextHandler] = cb
        return env.nextHandler
    end
    function RemoveEventHandler(tok)
        for _, g in pairs(env.events) do if g[tok] then g[tok] = nil; env.removedHandlers = env.removedHandlers + 1; return end end
    end
    function RegisterNetEvent(name, cb) env.netEvents[name] = true; if cb then return AddEventHandler(name, cb) end end
    function TriggerEvent(name, ...)
        local g = env.events[name] or {}; local ids = {}; for id in pairs(g) do ids[#ids+1] = id end; table.sort(ids)
        for _, id in ipairs(ids) do if g[id] then g[id](...) end end
    end
    function TriggerClientEvent(name, target, ...)
        env.clientEvents[#env.clientEvents+1] = { name = name, target = target, args = {...} }
    end
    function TriggerServerEvent(name, ...) env.serverEvents[#env.serverEvents+1] = { name = name, args = {...} } end
    function CreateThread(fn) fn() end
    function Wait() end
    function SetTimeout(ms, cb) env.timeouts[#env.timeouts+1] = { ms = ms, callback = cb } end
    source = 0

    local registeredExports = {}
    exports = setmetatable({}, {
        __call = function(_, name, fn) registeredExports[name] = fn end,
        __index = function(_, resource)
            return setmetatable({}, {
                __index = function(_, method)
                    return function(_self, ...)
                        local r = env.exportResources[resource]; local f = r and r[method]
                        if not f then error(('missing export %s:%s'):format(resource, method)) end
                        return f(...)
                    end
                end
            })
        end
    })
    env.registeredExports = registeredExports

    MySQL = {
        query = { await = function(sql) if sql and sql:find('SELECT `migration`', 1, true) then return {} end return {} end },
        single = { await = function() return nil end }, scalar = { await = function() return 1 end },
        insert = { await = function() return 1 end }, update = { await = function() return 1 end },
        transaction = { await = function() return true end }
    }

    promise = {}
    function promise.new()
        local p = { resolved = false, value = nil }
        function p:resolve(value) self.resolved = true; self.value = value end
        return p
    end
    Citizen = {}
    function Citizen.Await(p)
        if not p.resolved and env.awaitHook then local hook = env.awaitHook; env.awaitHook = nil; hook() end
        return p.value
    end
end

local function loadAll(includeApi, includeCleanup)
    installStubs(); Config = nil; NEXM_INTERNAL = nil; GetCoreObject = nil; NEXM_CUSTOM_INVENTORY_ADAPTER = nil
    dofile(root..'/config.lua')
    dofile(root..'/shared/init.lua'); dofile(root..'/shared/constants.lua'); dofile(root..'/shared/errors.lua'); dofile(root..'/shared/validation.lua'); dofile(root..'/shared/transport.lua'); dofile(root..'/shared/semver.lua'); dofile(root..'/shared/identity.lua'); dofile(root..'/shared/network_validation.lua'); dofile(root..'/shared/safe_data.lua'); dofile(root..'/shared/locale.lua'); dofile(root..'/shared/notify_contract.lua')
    dofile(root..'/server/state.lua'); dofile(root..'/server/logger.lua'); dofile(root..'/server/ownership.lua'); dofile(root..'/server/database.lua'); dofile(root..'/server/migrations.lua'); dofile(root..'/server/migrations/core.lua')
    dofile(root..'/server/registry_base.lua'); dofile(root..'/server/managers/resources.lua'); dofile(root..'/server/managers/services.lua'); dofile(root..'/server/managers/features.lua'); dofile(root..'/server/managers/integrations.lua'); dofile(root..'/server/readiness.lua')
    dofile(root..'/server/framework_contract.lua'); dofile(root..'/adapters/framework/esx.lua'); dofile(root..'/adapters/framework/qbcore.lua'); dofile(root..'/adapters/framework/qbox.lua'); dofile(root..'/adapters/framework/standalone.lua'); dofile(root..'/server/managers/framework.lua')
    dofile(root..'/server/player_cache.lua'); dofile(root..'/server/player.lua'); dofile(root..'/server/jobs.lua'); dofile(root..'/server/lifecycle.lua')
    dofile(root..'/server/session_guard.lua'); dofile(root..'/server/money.lua'); dofile(root..'/server/inventory_contract.lua'); dofile(root..'/custom/inventory.lua')
    dofile(root..'/adapters/inventory/ox_inventory.lua'); dofile(root..'/adapters/inventory/qb_inventory.lua'); dofile(root..'/adapters/inventory/esx.lua'); dofile(root..'/adapters/inventory/qs_inventory.lua'); dofile(root..'/server/managers/inventory.lua'); dofile(root..'/server/inventory.lua')
    dofile(root..'/custom/audit.lua'); dofile(root..'/server/audit.lua')
    dofile(root..'/server/rate_limit.lua'); dofile(root..'/server/event_bus.lua'); dofile(root..'/server/permissions.lua'); dofile(root..'/server/callbacks.lua'); dofile(root..'/server/managers/notify.lua'); dofile(root..'/server/notify.lua'); dofile(root..'/server/components.lua'); dofile(root..'/server/diagnostics.lua')
    if includeApi then dofile(root..'/server/api.lua') end
    if includeCleanup then dofile(root..'/server/cleanup.lua') end
    return NEXM_INTERNAL
end

local function setReady(I)
    local S, St = I.Modules.State, I.Modules.Constants.STATES
    if S.Get() == St.BOOTING then S.Set(St.DATABASE); S.Set(St.MIGRATING); S.Set(St.FRAMEWORK); S.Set(St.PLATFORM); S.Set(St.READY) end
end

local function fakeFramework(I, store)
    store = store or {}; local cb = {}
    local adapter = { metadata = { name='qbox', resource='qbx_core', version='test', capabilities={
        player={identity={character=true,account=true,license=true},job=true,duty=true}, jobs={multiple=false}, money={cash=true,bank=true}, framework={permissions=true}
    } } }
    function adapter.IsAvailable() return env.resourceStates.qbx_core == 'started' end
    function adapter.Initialize() return true,nil end; function adapter.Shutdown() return true,nil end; function adapter.GetState() return 'HEALTHY' end
    function adapter.GetPlayer(s) return store[s] and { PlayerData = store[s] } or nil end
    function adapter.IsPlayerLoaded(s) return store[s] ~= nil end
    function adapter.GetCharacterIdentifier(s) return store[s] and store[s].char or nil, store[s] and nil or I.Modules.Errors.Create('PLAYER_NOT_FOUND','missing') end
    function adapter.GetAccountIdentifier(s) return store[s] and ('acct:'..store[s].char) or nil, store[s] and nil or I.Modules.Errors.Create('PLAYER_NOT_FOUND','missing') end
    function adapter.GetLicense(s) return store[s] and ('license:'..store[s].char) or nil, store[s] and nil or I.Modules.Errors.Create('PLAYER_NOT_FOUND','missing') end
    function adapter.GetCharacterName(s) return store[s] and store[s].name or nil, store[s] and nil or I.Modules.Errors.Create('PLAYER_NOT_FOUND','missing') end
    function adapter.GetJob(s)
        local p = store[s]; if not p then return nil, I.Modules.Errors.Create('PLAYER_NOT_FOUND','missing') end
        local j = p.job or {name='police',label='Police',grade=3,gradeName='sergeant',onDuty=true}
        return {name=j.name,label=j.label,grade=j.grade,gradeName=j.gradeName,onDuty=j.onDuty},nil
    end
    function adapter.GetMoney(s,a) return store[s] and store[s].money and store[s].money[a] or nil,nil end
    function adapter.AddMoney(s,a,n) if not store[s] then return false end; store[s].money[a]=store[s].money[a]+n; return true,nil end
    function adapter.RemoveMoney(s,a,n) if not store[s] or store[s].money[a]<n then return false end; store[s].money[a]=store[s].money[a]-n; return true,nil end
    function adapter.HasFrameworkPermission(s,p) return env.aces[s] and env.aces[s][p] == true or false,nil end
    function adapter.SubscribePlayerLoaded(f) cb.load=f; return true,nil end; function adapter.SubscribePlayerUnloaded(f) cb.unload=f; return true,nil end
    function adapter.SubscribeJobChanged(f) cb.job=f; return true,nil end; function adapter.SubscribeDutyChanged(f) cb.duty=f; return true,nil end
    adapter._callbacks=cb; return adapter
end

local function initializeFramework(I, extraStore)
    local store = extraStore or {
        [20]={char='A',name='Alice',money={cash=1000,bank=5000},job={name='police',label='Police',grade=3,gradeName='sergeant',onDuty=true}},
        [21]={char='B',name='Bob',money={cash=1000,bank=5000},job={name='unemployed',label='Unemployed',grade=0,gradeName='none',onDuty=false}}
    }
    env.resourceStates.qbx_core='started'; Config.Framework='qbox'; I.Adapters.Framework.qbox=fakeFramework(I,store)
    local ok,err=I.Managers.Framework.RegisterBuiltinAdapters(); if not ok then return nil,err end
    ok,err=I.Managers.Framework.InitializeSelected(); if not ok then return nil,err end
    for src,p in pairs(store) do
        I.Modules.PlayerCache.Store(src,{source=src,identifier='qbox:character:'..p.char,identity={character=p.char,account='acct:'..p.char,license='license:'..p.char},name=p.name,job={name=p.job.name,label=p.job.label,grade=p.job.grade,gradeName=p.job.gradeName,onDuty=p.job.onDuty},framework='qbox',loaded=true})
    end
    return store,nil
end

local function lastResponse()
    for i=#env.clientEvents,1,-1 do local e=env.clientEvents[i]; if e.name=='nexm_core:rpc:response' then return e end end
end
local function responseCode()
    local e=lastResponse(); return e and e.args[3] and e.args[3].code or nil
end

-- Final framework permission capability consistency -------------------------
do
    local I=loadAll(false,false); local C,E=I.Modules.FrameworkContract,I.Modules.Errors
    local a=fakeFramework(I,{[1]={char='A',name='A',money={cash=1,bank=1},job={name='police',label='Police',grade=1,gradeName='o',onDuty=true}}})
    local ok,err=C.Validate(a); expect('Framework permissions=true requires and accepts HasFrameworkPermission',ok==true,err and err.code)
    a.HasFrameworkPermission=nil; ok,err=C.Validate(a); expect('Permission-capability liar is INVALID_FRAMEWORK_ADAPTER',ok==false and E.Is(err,'INVALID_FRAMEWORK_ADAPTER'))
    a.metadata.capabilities.framework.permissions=false; ok,err=C.Validate(a); expect('permissions=false may omit framework permission method',ok==true,err and err.code)
    expect('Official ESX adapter exposes HasFrameworkPermission',type(I.Adapters.Framework.esx.HasFrameworkPermission)=='function')
    expect('Official QBCore adapter exposes HasFrameworkPermission',type(I.Adapters.Framework.qbcore.HasFrameworkPermission)=='function')
    expect('Official Qbox adapter exposes HasFrameworkPermission',type(I.Adapters.Framework.qbox.HasFrameworkPermission)=='function')
end

-- Core READY vs optional inventory ------------------------------------------
do
    local I=loadAll(false,false); Config.Framework='standalone'; Config.Inventory='none'; dofile(root..'/server/bootstrap.lua')
    expect('Inventory none allows Core READY',I.Modules.State.IsReady()==true)
    expect('Inventory none component is DISABLED',I.Modules.State.GetComponent('inventory').state=='DISABLED')
    local ok,err=I.Modules.Inventory.HasItem(20,'x',1,nil); expect('Inventory disabled returns INVENTORY_DISABLED',ok==false and I.Modules.Errors.Is(err,'INVENTORY_DISABLED'))
end
do
    local I=loadAll(false,false); Config.Framework='standalone'; Config.Inventory='auto'; dofile(root..'/server/bootstrap.lua')
    expect('Auto with no inventory allows Core READY',I.Modules.State.IsReady()==true)
    expect('Auto with no inventory records UNAVAILABLE component',I.Modules.State.GetComponent('inventory').state=='UNAVAILABLE')
end
do
    local I=loadAll(false,false); env.resourceStates.ox_inventory='started'; env.resourceStates['qb-inventory']='started'; Config.Framework='standalone'; Config.Inventory='auto'; dofile(root..'/server/bootstrap.lua')
    expect('Ambiguous optional inventory does not globally block Core READY',I.Modules.State.IsReady()==true)
    expect('Ambiguous inventory remains unavailable instead of silent selection',I.Modules.State.GetComponent('inventory').state=='UNAVAILABLE' and I.Managers.Inventory.GetName()==nil)
end

-- Resource requirements / component capability model -----------------------
do
    local I=loadAll(false,false); initializeFramework(I); setReady(I); Config.Inventory='none'; I.Managers.Inventory.InitializeSelected()
    local R,E=I.Managers.Resources,I.Modules.Errors
    local ok,err=R.Register({name='nexm_justice',version='1.0.0',requiresCore='>=1.0.0-0',requirements={framework=true}},'nexm_justice')
    expect('Resource with no inventory dependency registers while inventory disabled',ok==true,err and err.code)
    ok,err=R.Register({name='nexm_contraband',version='1.0.0',requiresCore='>=1.0.0-0',requirements={framework=true,integrations={inventory={required=true}}}},'nexm_contraband')
    expect('Resource requiring disabled inventory fails dependency check',ok==false and E.Is(err,'DEPENDENCY_UNAVAILABLE'))
    ok,err=R.Register({name='nexm_cashapp',version='1.0.0',requiresCore='>=1.0.0-0',requirements={framework=true,frameworkCapabilities={'money.cash'}}},'nexm_cashapp')
    expect('Resource framework capability requirement succeeds when true',ok==true,err and err.code)
    ok,err=R.Register({name='nexm_fakecap',version='1.0.0',requiresCore='>=1.0.0-0',requirements={frameworkCapabilities={'money.crypto'}}},'nexm_fakecap')
    expect('Unavailable framework capability fails CAPABILITY_UNAVAILABLE',ok==false and E.Is(err,'CAPABILITY_UNAVAILABLE'))
end

do
    local I=loadAll(false,false); initializeFramework(I); setReady(I); I.Managers.Framework.InstallResourceMonitoring()
    local ok,err=I.Managers.Resources.Register({name='nexm_framework_dep',version='1.0.0',requiresCore='>=1.0.0-0',requirements={framework=true}},'nexm_framework_dep')
    expect('Framework-dependent resource initially ACTIVE',ok==true and I.Managers.Resources.Get('nexm_framework_dep').state=='ACTIVE')
    env.resourceStates.qbx_core='missing'; TriggerEvent('onResourceStop','qbx_core')
    expect('Framework-dependent resource becomes DEGRADED on framework loss',I.Managers.Resources.Get('nexm_framework_dep').state=='DEGRADED')
    env.resourceStates.qbx_core='started'; env.players={20,21}; TriggerEvent('onResourceStart','qbx_core')
    expect('Framework-dependent resource returns ACTIVE after same framework recovery',I.Managers.Resources.Get('nexm_framework_dep').state=='ACTIVE')
end

do
    local I=loadAll(false,false); initializeFramework(I); setReady(I)
    env.resourceStates['qb-inventory']='started'; env.exportResources['qb-inventory']={GetItemCount=function()return 0 end,CanAddItem=function()return true end,AddItem=function()return true end,RemoveItem=function()return true end}; env.exportResources['qb-core']={GetPlayer=function() return {PlayerData={items={}}} end}
    Config.Inventory='qb-inventory'; local ok,err=I.Managers.Inventory.InitializeSelected(); expect('qb-inventory selected for requirement test',ok==true,err and err.code)
    ok,err=I.Managers.Resources.Register({name='nexm_meta',version='1.0.0',requiresCore='>=1.0.0-0',requirements={integrations={inventory={required=true,capabilities={'metadata'}}}}},'nexm_meta')
    expect('qb-inventory satisfies metadata create capability',ok==true,err and err.code)
    ok,err=I.Managers.Resources.Register({name='nexm_metafilter',version='1.0.0',requiresCore='>=1.0.0-0',requirements={integrations={inventory={required=true,capabilities={'metadataFilter'}}}}},'nexm_metafilter')
    expect('qb-inventory metadataFilter requirement fails closed',ok==false and I.Modules.Errors.Is(err,'CAPABILITY_UNAVAILABLE'))
end

do
    local I=loadAll(false,false); initializeFramework(I); setReady(I)
    env.resourceStates.ox_inventory='started'; env.exportResources.ox_inventory={GetItemCount=function()return 0 end,CanCarryItem=function()return true end,AddItem=function()return true end,RemoveItem=function()return true end,GetInventoryItems=function()return {} end}
    Config.Inventory='ox_inventory'; local ok,err=I.Managers.Inventory.InitializeSelected(); expect('ox_inventory selected for requirement test',ok==true,err and err.code)
    I.Managers.Inventory.InstallResourceMonitoring()
    ok,err=I.Managers.Resources.Register({name='nexm_contraband',version='1.0.0',requiresCore='>=1.0.0-0',requirements={integrations={inventory={required=true,capabilities={'metadataFilter'}}}}},'nexm_contraband')
    expect('ox_inventory metadataFilter requirement succeeds',ok==true,err and err.code)
    env.resourceStates.ox_inventory='missing'; TriggerEvent('onResourceStop','ox_inventory')
    expect('Inventory stop does not change Core READY',I.Modules.State.IsReady()==true)
    local record=I.Managers.Resources.Get('nexm_contraband'); expect('Dependent resource becomes DEGRADED when inventory disappears',record and record.state=='DEGRADED')
    expect('Core never auto-stops degraded dependent resource',#env.stopCalls==0)
    env.resourceStates.ox_inventory='started'; TriggerEvent('onResourceStart','ox_inventory')
    record=I.Managers.Resources.Get('nexm_contraband'); expect('Same inventory recovery reactivates dependent resource status',record and record.state=='ACTIVE')
end

-- Internal event bus ---------------------------------------------------------
do
    local I=loadAll(false,false); local B,E=I.Modules.EventBus,I.Modules.Errors; local seenA,seenB,seenC={}, {}, {}
    local ok,err=B.On('justice:violation',function(payload) seenA[#seenA+1]=payload.nested.amount; payload.nested.amount=999 end,'nexm_justice'); expect('Event listener A registers',ok==true)
    ok,err=B.On('justice:violation',function(payload) seenB[#seenB+1]=payload.nested.amount; error('listener boom') end,'nexm_evidence'); expect('Cross-resource listener B registers',ok==true)
    ok,err=B.On('justice:violation',function(payload) seenC[#seenC+1]=payload.nested.amount end,'nexm_analytics'); expect('Listener C registers after throwing listener',ok==true)
    ok,err=B.Emit('justice:violation',{nested={amount=5}}); expect('Internal event emits despite one listener throwing',ok==true and #seenC==1)
    expect('Event payload mutation is isolated per listener',seenA[1]==5 and seenB[1]==5 and seenC[1]==5)
    expect('Internal domain event is not registered as a network event',env.netEvents['justice:violation']~=true)
    local removed=B.CleanupOwner('nexm_evidence'); expect('Event listeners clean by resource owner',removed==1)
    ok,err=B.Emit('justice:violation',{nested={amount=7}}); expect('Remaining listeners continue after owner cleanup',ok==true and seenC[#seenC]==7)
    ok,err=B.On('changed',function()end,'x'); expect('Vague event name without domain prefix rejected',ok==false and E.Is(err,'INVALID_EVENT_NAME'))
    local cyc={};cyc.self=cyc; ok,err=B.Emit('justice:violation',cyc); expect('Cyclic internal event payload rejected safely',ok==false and E.Is(err,'INVALID_PAYLOAD'))
    ok,err=B.On('justice:violation',function()end,'nexm_evidence'); expect('Same stopped resource can re-register event listener',ok==true)
end

-- Permission policy matrix ---------------------------------------------------
do
    local I=loadAll(false,false); local store=initializeFramework(I); setReady(I); local P,E=I.Modules.Permissions,I.Modules.Errors
    env.aces[20]={['nexm.justice.manage']=true,admin=true}; env.aces[21]={}
    local ok,err=P.Define('aceonly',{mode='any',ace={'nexm.justice.manage'}},'nexm_justice'); expect('ACE permission definition registers',ok==true)
    local allowed; allowed,err=P.Has(20,'aceonly','nexm_justice'); expect('ACE allowed',allowed==true and err==nil)
    allowed,err=P.Has(21,'aceonly','nexm_justice'); expect('ACE absent is ordinary denial',allowed==false and err==nil)
    P.Define('jobmanage',{jobs={police={minimumGrade=3,requireDuty=true}}},'nexm_justice')
    allowed,err=P.Has(20,'jobmanage','nexm_justice'); expect('Job permission matching grade and duty allowed',allowed==true and err==nil)
    store[20].job.grade=2; I.Modules.PlayerCache.UpdateJob(20,{name='police',label='Police',grade=2,gradeName='officer',onDuty=true},I.Modules.PlayerCache.GetSession(20)); allowed,err=P.Has(20,'jobmanage','nexm_justice'); expect('Job grade below minimum denied',allowed==false and err==nil)
    allowed,err=P.Has(21,'jobmanage','nexm_justice'); expect('Wrong normalized job denied',allowed==false and err==nil)
    store[20].job.grade=4; I.Modules.PlayerCache.UpdateJob(20,{name='police',label='Police',grade=4,gradeName='lieutenant',onDuty=true},I.Modules.PlayerCache.GetSession(20)); allowed,err=P.Has(20,'jobmanage','nexm_justice'); expect('Job grade above minimum allowed',allowed==true and err==nil)
    store[20].job.grade=3; I.Modules.PlayerCache.UpdateJob(20,{name='police',label='Police',grade=3,gradeName='sergeant',onDuty=false},I.Modules.PlayerCache.GetSession(20)); allowed,err=P.Has(20,'jobmanage','nexm_justice'); expect('Required duty off denied',allowed==false and err==nil)
    I.Modules.PlayerCache.UpdateJob(20,{name='police',label='Police',grade=3,gradeName='sergeant',onDuty=true},I.Modules.PlayerCache.GetSession(20)); allowed,err=P.Has(20,'jobmanage','nexm_justice'); expect('Duty true restores job permission',allowed==true and err==nil)
    I.Managers.Framework.GetSelected().metadata.capabilities.player.duty=false; I.Modules.PlayerCache.UpdateJob(20,{name='police',label='Police',grade=3,gradeName='sergeant',onDuty=nil},I.Modules.PlayerCache.GetSession(20)); allowed,err=P.Has(20,'jobmanage','nexm_justice'); expect('Unsupported duty fails closed as denial',allowed==false and err==nil)
    I.Managers.Framework.GetSelected().metadata.capabilities.player.duty=true; I.Modules.PlayerCache.UpdateJob(20,{name='police',label='Police',grade=3,gradeName='sergeant',onDuty=true},I.Modules.PlayerCache.GetSession(20))
    P.Define('frameworkadmin',{framework={'admin'}},'nexm_justice'); allowed,err=P.Has(20,'frameworkadmin','nexm_justice'); expect('Framework permission provider uses authoritative adapter',allowed==true and err==nil)
    allowed,err=P.Has(21,'frameworkadmin','nexm_justice'); expect('Framework permission denial is ordinary false',allowed==false and err==nil)
    P.Define('customtrue',{custom=function()return true end},'nexm_justice'); allowed,err=P.Has(20,'customtrue','nexm_justice'); expect('Custom permission resolver true grants',allowed==true and err==nil)
    P.Define('customfalse',{custom=function()return false end},'nexm_justice'); allowed,err=P.Has(20,'customfalse','nexm_justice'); expect('Custom resolver false denies normally',allowed==false and err==nil)
    P.Define('customthrow',{custom=function()error('secret stack')end},'nexm_justice'); allowed,err=P.Has(20,'customthrow','nexm_justice'); expect('Thrown custom resolver denies with structured error',allowed==false and E.Is(err,'PERMISSION_RESOLVER_ERROR'))
    allowed,err=P.Has(20,'missing','nexm_justice'); expect('Unknown permission fails closed',allowed==false and E.Is(err,'PERMISSION_NOT_DEFINED'))
    P.Define('allpolicy',{mode='all',ace={'nexm.justice.manage'},jobs={police={minimumGrade=3,requireDuty=false}}},'nexm_justice'); allowed,err=P.Has(20,'allpolicy','nexm_justice'); expect('Permission mode=all grants when every provider grants',allowed==true and err==nil)
    env.aces[20]['nexm.justice.manage']=false; allowed,err=P.Has(20,'allpolicy','nexm_justice'); expect('Permission mode=all denies when one provider denies',allowed==false and err==nil); env.aces[20]['nexm.justice.manage']=true
    ok,err=P.Define('aceonly',{ace={'x'}},'nexm_justice'); expect('Same owner duplicate permission definition rejected',ok==false and E.Is(err,'REGISTRATION_EXISTS'))
    ok,err=P.Define('aceonly',{ace={'other'}},'nexm_evidence'); expect('Same local permission name can coexist under different owner namespace',ok==true)
    local removed=P.CleanupOwner('nexm_justice'); expect('Permission definitions cleanup by owner',removed>=1)
    allowed,err=P.Has(20,'aceonly','nexm_justice'); expect('Cleaned permission no longer authorizes',allowed==false and E.Is(err,'PERMISSION_NOT_DEFINED'))
    ok,err=P.Define('aceonly',{ace={'nexm.justice.manage'}},'nexm_justice'); expect('Permission can re-register after same resource restart',ok==true)
end

-- Framework degradation during permission check -----------------------------
do
    local I=loadAll(false,false); initializeFramework(I); setReady(I); local P=I.Modules.Permissions; P.Define('job',{jobs={police={minimumGrade=1}}},'nexm_test')
    I.Managers.Framework.InstallResourceMonitoring(); env.resourceStates.qbx_core='missing'; TriggerEvent('onResourceStop','qbx_core')
    local allowed,err=P.Has(20,'job','nexm_test'); expect('Job permission fails closed when framework disappears',allowed==false and I.Modules.Errors.Is(err,'FRAMEWORK_UNAVAILABLE'))
    env.resourceStates.qbx_core='started'; env.players={20,21}; TriggerEvent('onResourceStart','qbx_core')
    allowed,err=P.Has(20,'job','nexm_test'); expect('Permission uses rebuilt framework/cache after recovery',allowed==true and err==nil)
end

-- Rate limit matrix ----------------------------------------------------------
do
    local I=loadAll(false,false); initializeFramework(I); local R,E=I.Modules.RateLimit,I.Modules.Errors
    env.timer=1000; local ok,err=R.Check(20,'createCase',{limit=2,window=10},'nexm_justice'); expect('Rate limit below limit allowed #1',ok==true)
    ok,err=R.Check(20,'createCase',{limit=2,window=10},'nexm_justice'); expect('Rate limit at configured limit allowed #2',ok==true)
    ok,err=R.Check(20,'createCase',{limit=2,window=10},'nexm_justice'); expect('Rate limit above limit rejected',ok==false and E.Is(err,'RATE_LIMITED'))
    env.timer=12000; ok,err=R.Check(20,'createCase',{limit=2,window=10},'nexm_justice'); expect('Rate-limit window expires lazily',ok==true)
    ok,err=R.Check(20,'other',{limit=1,window=10},'nexm_justice'); expect('Different rate key has independent bucket',ok==true)
    ok,err=R.Check(20,'other',{limit=1,window=10},'nexm_evidence'); expect('Different resource owner key does not collide',ok==true)
    ok,err=R.Check(21,'other',{limit=1,window=10},'nexm_justice'); expect('Different source has independent bucket',ok==true)
    local before=R.CountBuckets(); source=20; TriggerEvent('playerDropped','bye'); source=0; expect('playerDropped cleans all rate buckets for source',R.CountBuckets()<before)
    ok,err=R.Check(20,'createCase',{limit=1,window=10},'nexm_justice'); expect('Reused source does not inherit old disconnect punishment',ok==true)
    local s=I.Modules.PlayerCache.GetSession(20); ok,err=R.Check(20,'sessionKey',{limit=1,window=10},'nexm_justice'); expect('Session-scoped bucket first call allowed',ok==true)
    I.Modules.PlayerCache.Remove(20); I.Modules.PlayerCache.Store(20,{source=20,identifier='qbox:character:NEW',identity={character='NEW',account='a',license='l'},name='New',job={name='police',label='Police',grade=1,gradeName='o',onDuty=true},framework='qbox',loaded=true})
    ok,err=R.Check(20,'sessionKey',{limit=1,window=10},'nexm_justice'); expect('Character switch resets session-scoped rate bucket',ok==true)
    R.CleanupSource(20); ok=R.CheckInternal(20,'@rpc-global',{limit=1,window=10,sessionScoped=false}); I.Modules.PlayerCache.Remove(20); I.Modules.PlayerCache.Store(20,{source=20,identifier='qbox:character:N2',identity={character='N2',account='a',license='l'},name='New2',job={name='police',label='Police',grade=1,gradeName='o',onDuty=true},framework='qbox',loaded=true}); ok,err=R.CheckInternal(20,'@rpc-global',{limit=1,window=10,sessionScoped=false}); expect('Global source limiter intentionally persists across character switch',ok==false and E.Is(err,'RATE_LIMITED'))
    R.CleanupSource(20); env.timer=4294967290; local t1=R._NowMs(); env.timer=5; local t2=R._NowMs(); expect('Monotonic rate clock handles 32-bit runtime timer wrap',t2>t1)
end

-- RPC basic routing, permissions and ownership -------------------------------
do
    local I=loadAll(true,false); initializeFramework(I); setReady(I); local C,P,E=I.Modules.Callbacks,I.Modules.Permissions,I.Modules.Errors
    P.Define('view',{jobs={police={minimumGrade=1}}},'nexm_justice')
    local justiceCalls,evidenceCalls=0,0
    local ok,err=C.Register('getProfile',function(src,payload,ctx) justiceCalls=justiceCalls+1; return {owner=ctx.ownerResource,id=payload.id,character=ctx.characterIdentifier} end,{permission='view',requireCharacter=true},'nexm_justice'); expect('Justice callback registers',ok==true,err and err.code)
    ok,err=C.Register('getProfile',function() evidenceCalls=evidenceCalls+1; return {evidence=true} end,{},'nexm_evidence'); expect('Same callback local name can coexist under different owner',ok==true)
    C.HandleRequest(20,'n:1:1','nexm_justice','getProfile',{id=7}); local r=lastResponse(); expect('RPC routes ergonomic callback to owner-qualified server registration',r and r.args[2]==true and r.args[3].owner=='nexm_justice' and justiceCalls==1)
    C.HandleRequest(20,'n:1:2','nexm_evidence','getProfile',{}); r=lastResponse(); expect('Different owner callback route does not collide',r and r.args[2]==true and r.args[3].evidence==true and evidenceCalls==1)
    local beforeCalls=justiceCalls; C.HandleRequest(21,'n:1:3','nexm_justice','getProfile',{permission=true,ownerResource='nexm_justice',job={name='police',grade=99},citizenid='FAKE'}); r=lastResponse(); expect('Client-supplied owner/job/permission/identity cannot bypass server permission',r and r.args[2]==false and r.args[3].code=='PERMISSION_DENIED' and justiceCalls==beforeCalls)
    env.clientEvents={}; source=21; TriggerEvent('nexm_core:rpc:request','raw:1','nexm_justice','getProfile',{permission=true,characterSessionId=999,characterIdentifier='FAKE'}); source=0; r=lastResponse(); expect('Manual raw RPC network event with claimed owner still cannot bypass authorization',r and r.args[2]==false and r.args[3].code=='PERMISSION_DENIED' and justiceCalls==beforeCalls)
    I.Modules.RateLimit.CleanupSource(20); env.clientEvents={}; C.HandleRequest(20,'unknown:1','nexm_justice','notThere',{}); expect('Unknown callback returns RPC_CALLBACK_NOT_FOUND without registry disclosure',responseCode()=='RPC_CALLBACK_NOT_FOUND')
    ok,err=C.Register('bad:name',function()end,{},'nexm_justice'); expect('Public callback names reject internal separators/control namespace',ok==false and E.Is(err,'INVALID_CALLBACK_NAME'))
    local contextSeen=nil; C.Register('context',function(src,payload,ctx) contextSeen={source=ctx.source,owner=ctx.ownerResource,char=ctx.characterIdentifier,session=ctx.characterSessionId,current=ctx:IsCurrentSession()}; return true end,{requireCharacter=true},'nexm_justice'); C.HandleRequest(20,'n:1:4','nexm_justice','context',{source=999,characterSessionId=999}); expect('RPC context identity/session is generated server-side',contextSeen and contextSeen.source==20 and contextSeen.owner=='nexm_justice' and contextSeen.char=='qbox:character:A' and contextSeen.current==true)
end

-- Duplicate request / spam / unknown callback global limiting ----------------
do
    local I=loadAll(false,false); initializeFramework(I); local C,E=I.Modules.Callbacks,I.Modules.Errors; Config.Security.RPCGlobalLimit={limit=1000,window=10}
    local calls=0
    C.Register('dupe',function(src,payload) calls=calls+1; if calls==1 then C.HandleRequest(src,payload.id,'nexm_test','dupe',{id=payload.id}) end; return {ok=true} end,{},'nexm_test')
    C.HandleRequest(20,'same-id','nexm_test','dupe',{id='same-id'}); expect('Duplicate active request id does not execute handler twice',calls==1)
    local sawDuplicate=false; for _,e in ipairs(env.clientEvents) do if e.name=='nexm_core:rpc:response' and e.args[1]=='same-id' and e.args[2]==false and e.args[3].code=='RPC_DUPLICATE_REQUEST' then sawDuplicate=true end end; expect('Duplicate active request returns RPC_DUPLICATE_REQUEST',sawDuplicate)
    expect('Server active request map cleans after completed request',C.CountActive()==0)

    local limitedCalls=0; C.Register('limited',function() limitedCalls=limitedCalls+1; return true end,{rateLimit={limit=5,window=10}},'nexm_test')
    for i=1,120 do C.HandleRequest(20,'spam:'..i,'nexm_test','limited',{}) end
    expect('100+ same-callback spam is capped by endpoint rate limit',limitedCalls==5)
    expect('RPC spam does not leak active request entries',C.CountActive()==0)

    I.Modules.RateLimit.CleanupSource(21); Config.Security.RPCGlobalLimit={limit=10,window=10}; env.clientEvents={}
    for i=1,100 do C.HandleRequest(21,'rot:'..i,'nexm_fake','fake'..i,{}) end
    local rateErrors=0; for _,e in ipairs(env.clientEvents) do if e.name=='nexm_core:rpc:response' and e.args[2]==false and e.args[3] and e.args[3].code=='RATE_LIMITED' then rateErrors=rateErrors+1 end end
    expect('Callback-name rotation spam hits global source RPC limiter',rateErrors>=80)
    expect('Unknown callback spam leaves no active pending map growth',C.CountActive()==0)
end

-- Malformed request payload / malformed responses ---------------------------
do
    local I=loadAll(false,false); initializeFramework(I); local C,E,R=I.Modules.Callbacks,I.Modules.Errors,I.Modules.RateLimit; Config.Security.RPCGlobalLimit={limit=1000,window=10}
    C.Register('echo',function(_,p)return p end,{},'nexm_test')
    local cases={
        {'huge string',string.rep('a',Config.Network.request.maxStringLength+1)},
        {'NaN',0/0}, {'infinity',math.huge}, {'function',function()end}, {'thread',coroutine.create(function()end)}
    }
    local deep={}; local n=deep; for i=1,Config.Network.request.maxDepth+2 do n.x={}; n=n.x end; cases[#cases+1]={'deep table',deep}
    local many={}; for i=1,Config.Network.request.maxEntries+2 do many[i]=i end; cases[#cases+1]={'huge entry count',many}
    local cyc={};cyc.self=cyc; cases[#cases+1]={'cycle',cyc}
    for i,c in ipairs(cases) do R.CleanupSource(20); env.clientEvents={}; C.HandleRequest(20,'bad:'..i,'nexm_test','echo',c[2]); expect('Malformed request rejected: '..c[1],responseCode()=='INVALID_PAYLOAD',responseCode()) end
    R.CleanupSource(20); env.clientEvents={}; C.HandleRequest(20,'bad request id with space','nexm_test','echo',{}); expect('Malformed request id rejected',responseCode()=='INVALID_REQUEST_ID',responseCode())
    R.CleanupSource(20); env.clientEvents={}; C.HandleRequest(20,'okid','bad owner!','echo',{}); expect('Malformed routing owner rejected',responseCode()=='INVALID_PAYLOAD',responseCode())
    R.CleanupSource(20); env.clientEvents={}; C.HandleRequest(20,'okid2','nexm_test','bad:name',{}); expect('Malformed callback name rejected',responseCode()=='INVALID_CALLBACK_NAME',responseCode())

    local responseCases={
        {'function',function()return function()end end},
        {'thread',function()return coroutine.create(function()end) end},
        {'raw object',function()return {PlayerData={citizenid='A'},Functions={Save=function()end}} end}
    }
    local rd={}; local rn=rd; for i=1,Config.Network.response.maxDepth+2 do rn.x={};rn=rn.x end; responseCases[#responseCases+1]={'deep',function()return rd end}
    local rc={};rc.self=rc; responseCases[#responseCases+1]={'cycle',function()return rc end}
    for i,c in ipairs(responseCases) do C.Register('resp'..i,c[2],{},'nexm_test'); R.CleanupSource(20); env.clientEvents={}; C.HandleRequest(20,'resp:'..i,'nexm_test','resp'..i,{}); expect('Malformed RPC response blocked: '..c[1],responseCode()=='RPC_INVALID_RESPONSE',responseCode()) end
    C.Register('throws',function()error('/server/private/path.lua:42 secret')end,{},'nexm_test'); R.CleanupSource(20);env.clientEvents={};C.HandleRequest(20,'throw:1','nexm_test','throws',{}); local e=lastResponse(); expect('Thrown callback returns sanitized RPC handler error',e and e.args[3].code=='RPC_HANDLER_ERROR' and not tostring(e.args[3].message):find('private/path',1,true))
    expect('Malformed responses do not move Core out of healthy state machine',I.Modules.State.Get()=='BOOTING')
end

-- Callback validator, permission integration and stale session --------------
do
    local I=loadAll(false,false); local store=initializeFramework(I); local C,P,R=I.Modules.Callbacks,I.Modules.Permissions,I.Modules.RateLimit; Config.Security.RPCGlobalLimit={limit=1000,window=10}
    P.Define('manage',{jobs={police={minimumGrade=3,requireDuty=true}}},'nexm_justice')
    local calls=0
    C.Register('secure',function()calls=calls+1;return {secret='A-data'}end,{permission='manage',requireCharacter=true,validate=function(p)return type(p)=='table' and p.valid==true end},'nexm_justice')
    C.HandleRequest(20,'sec:1','nexm_justice','secure',{valid=false}); expect('Callback-specific validator runs before handler',responseCode()=='INVALID_PAYLOAD' and calls==0)
    R.CleanupSource(21); env.clientEvents={}; C.HandleRequest(21,'sec:2','nexm_justice','secure',{valid=true,permission=true,job={name='police',grade=99}}); expect('Callback permission option resolves same callback owner policy server-side',responseCode()=='PERMISSION_DENIED' and calls==0)
    R.CleanupSource(20); env.clientEvents={}
    C.Register('stale',function(src)
        local old=I.Modules.PlayerCache.Get(src); I.Modules.PlayerCache.Remove(src); store[src]={char='B2',name='B2',money={cash=1,bank=1},job={name='police',label='Police',grade=3,gradeName='s',onDuty=true}}; I.Modules.PlayerCache.Store(src,{source=src,identifier='qbox:character:B2',identity={character='B2',account='b',license='b'},name='B2',job=store[src].job,framework='qbox',loaded=true}); return {secret=old.identifier}
    end,{requireCharacter=true},'nexm_test')
    C.HandleRequest(20,'stale:1','nexm_test','stale',{}); local resp=lastResponse(); expect('Character switch during RPC returns STALE_CHARACTER_SESSION instead of A data',resp and resp.args[2]==false and resp.args[3].code=='STALE_CHARACTER_SESSION')
    expect('Stale RPC response never contains old character-sensitive payload',resp and type(resp.args[3])=='table' and resp.args[3].secret==nil)
end

-- Callback owner resource restart / generation protection -------------------
do
    local I=loadAll(false,false); initializeFramework(I); local C,R=I.Modules.Callbacks,I.Modules.RateLimit; Config.Security.RPCGlobalLimit={limit=1000,window=10}; local calls=0
    C.Register('restart',function()calls=calls+1;return 'v1'end,{},'nexm_justice'); C.HandleRequest(20,'rr:1','nexm_justice','restart',{}); expect('Callback works before owner stop',lastResponse().args[2]==true and calls==1)
    C.CleanupOwner('nexm_justice'); R.CleanupSource(20); env.clientEvents={}; C.HandleRequest(20,'rr:2','nexm_justice','restart',{}); expect('Stopped owner callback becomes unavailable',responseCode()=='RPC_CALLBACK_NOT_FOUND')
    local ok,err=C.Register('restart',function()calls=calls+1;return 'v2'end,{},'nexm_justice'); expect('Same owner can register callback again after restart',ok==true,err and err.code)
    R.CleanupSource(20); env.clientEvents={}; C.HandleRequest(20,'rr:3','nexm_justice','restart',{}); expect('Re-registered callback executes exactly one current generation',lastResponse().args[2]==true and lastResponse().args[3]=='v2' and calls==2)
    C.Register('generation',function() C.CleanupOwner('nexm_owner'); return {shouldNotSend=true} end,{},'nexm_owner'); R.CleanupSource(20);env.clientEvents={};C.HandleRequest(20,'rr:4','nexm_owner','generation',{}); expect('Owner generation change during handler discards successful result',responseCode()=='RPC_CALLBACK_UNAVAILABLE')
end

-- Client Await timeout / late response / requesting-resource cleanup ---------
do
    local I=loadAll(false,false); dofile(root..'/client/callbacks.lua'); local CC=I.Modules.ClientCallbacks
    env.awaitHook=function() local t=env.timeouts[#env.timeouts]; t.callback() end
    local value,err=CC.Await('nexm_justice','getProfile',{}, {timeout=250}); expect('Client Await times out with RPC_TIMEOUT',value==nil and err and err.code=='RPC_TIMEOUT')
    expect('Timed-out client pending request is removed',CC.CountPending()==0)
    local sent=env.serverEvents[#env.serverEvents]; local lateId=sent and sent.args[1]; if lateId then TriggerEvent('nexm_core:rpc:response',lateId,true,{late=true}) end; expect('Late response after timeout does not resurrect pending request',CC.CountPending()==0)
    value,err=CC.Await('nexm_justice','getProfile',{}, {timeout=999999}); expect('Client timeout override outside safe bounds rejected',value==nil and err and err.code=='INVALID_ARGUMENT')
    env.awaitHook=function() local t=env.timeouts[#env.timeouts]; t.callback() end; CC.Await('nexm_justice','getProfile',{}, {timeout=250}); local idA=env.serverEvents[#env.serverEvents].args[1]
    env.awaitHook=function() local t=env.timeouts[#env.timeouts]; t.callback() end; CC.Await('nexm_justice','getProfile',{}, {timeout=250}); local idB=env.serverEvents[#env.serverEvents].args[1]
    expect('Client generates distinct bounded request IDs',idA~=idB and #idA<=Config.Callback.maxRequestIdLength and #idB<=Config.Callback.maxRequestIdLength)
    env.awaitHook=function() TriggerEvent('onClientResourceStop','nexm_justice') end
    value,err=CC.Await('nexm_justice','getProfile',{}, {timeout=500}); expect('Client resource stop cleans owned pending RPC promise',value==nil and err and err.code=='RPC_CALLBACK_UNAVAILABLE' and CC.CountPending()==0)
end

-- Unified resource-owner cleanup for Phase 5 registrations ------------------
do
    local I=loadAll(true,true); initializeFramework(I); setReady(I); env.invoking='nexm_test'; local api=GetCoreObject(); local P,C,B,R=I.Modules.Permissions,I.Modules.Callbacks,I.Modules.EventBus,I.Modules.RateLimit
    api.Resources.Register({name='nexm_test',version='1.0.0',requiresCore='>=1.0.0-0',requirements={framework=true}})
    api.Services.Register('testservice',{Ping=function()return true end},{version='1.0.0',apiVersion='1.0.0'})
    api.Features.Register('testfeature',true,{})
    api.Permissions.Define('manage',{ace={'nexm.test.manage'}})
    api.Callback.Register('ping',function()return true end,{})
    api.Events.On('test:changed',function()end)
    api.RateLimit.Check(20,'bucket',{limit=2,window=10})
    local before={callbacks=C.CountRegistered(),permissions=P.Count(),listeners=B.CountListeners(),buckets=R.CountBuckets()}
    TriggerEvent('onResourceStop','nexm_test')
    expect('Resource stop cleans Phase 5 callback registrations',C.CountRegistered()<before.callbacks)
    expect('Resource stop cleans permission definitions',P.Count()<before.permissions)
    expect('Resource stop cleans internal event listeners',B.CountListeners()<before.listeners)
    expect('Resource stop cleans resource-owned rate-limit buckets',R.CountBuckets()<before.buckets)
    env.invoking='nexm_test'; api=GetCoreObject(); local ok,err=api.Callback.Register('ping',function()return true end,{}); expect('Same resource can re-register callback after cleanup',ok==true,err and err.code)
    ok,err=api.Permissions.Define('manage',{ace={'nexm.test.manage'}}); expect('Same resource can re-register permission after cleanup',ok==true,err and err.code)
end

-- Public API security boundaries --------------------------------------------
do
    local server=assert(io.open(root..'/server/api.lua')):read('*a'); local client=assert(io.open(root..'/client/api.lua')):read('*a'); local bus=assert(io.open(root..'/server/event_bus.lua')):read('*a')
    expect('Client facade exposes Callback Await',client:find('Callback',1,true)~=nil and client:find('Await',1,true)~=nil)
    expect('Client facade does not expose Permissions',client:find('Permissions',1,true)==nil)
    expect('Client facade does not expose RateLimit',client:find('RateLimit',1,true)==nil)
    expect('Client facade still does not expose Money',client:find('Money',1,true)==nil)
    expect('Client facade still does not expose Inventory',client:find('Inventory',1,true)==nil)
    expect('Internal event bus source does not RegisterNetEvent',bus:find('RegisterNetEvent',1,true)==nil)
    expect('Internal event bus source does not TriggerClientEvent',bus:find('TriggerClientEvent',1,true)==nil)
    local combined=''; for _,path in ipairs({root..'/server/api.lua',root..'/server/callbacks.lua',root..'/server/permissions.lua'}) do local f=assert(io.open(path));combined=combined..f:read('*a');f:close() end
    expect('Phase 5 does not add generic client money mutation endpoint',combined:find('nexm:money:add',1,true)==nil)
    expect('Phase 5 does not add generic client inventory mutation endpoint',combined:find('nexm:inventory:addItem',1,true)==nil)
    expect('Core never calls StopResource as dependency enforcement',server:find('StopResource',1,true)==nil)
end

-- Compile safety -------------------------------------------------------------
do
    local p=io.popen("find '"..root.."' -path '"..root.."/tests' -prune -o -name '*.lua' -print")
    local okAll=true; for file in p:lines() do local fn,err=loadfile(file); if not fn then okAll=false; print('[COMPILE ERROR] '..file..' :: '..tostring(err)) end end; p:close()
    expect('All Phase 2/3/4/5 production Lua files compile in harness',okAll)
end

print(('PHASE5 TESTS: %d, FAILED: %d'):format(total,failed))
if failed>0 then os.exit(1) end
