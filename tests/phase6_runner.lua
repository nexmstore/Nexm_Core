local root = arg[1] or '.'
local realPrint = print
local total, failed = 0, 0
local function expect(name, condition, detail)
    total = total + 1
    if condition then print('[PASS] '..name) else failed=failed+1; print('[FAIL] '..name..(detail and (' :: '..tostring(detail)) or '')) end
end

local env={}
local function encode(v, seen)
    local t=type(v)
    if t=='nil' then return 'null' elseif t=='boolean' or t=='number' then return tostring(v) elseif t=='string' then return string.format('%q',v) end
    if t~='table' then error('unsupported '..t) end
    seen=seen or {}; if seen[v] then error('cycle') end; seen[v]=true
    local parts={}; for k,val in pairs(v) do parts[#parts+1]=string.format('%q',tostring(k))..':'..encode(val,seen) end
    seen[v]=nil; return '{'..table.concat(parts,',')..'}'
end
local function installStubs()
    env={resourceStates={oxmysql='started'},resourcePaths={},versions={},events={},netEvents={},clientEvents={},serverEvents={},commands={},invoking=nil,exportResources={},timeouts={},httpRequests={},httpStatus=204,aces={},timer=1000,prints={},dbQueryFail=false,dbInsertFail=false,players={},playerIdentifiers={}}
    json={encode=function(v) return encode(v) end,decode=function() return {} end}
    local nativePrint=realPrint; print=function(...) local a={...}; local s={}; for i=1,#a do s[i]=tostring(a[i]) end; env.prints[#env.prints+1]=table.concat(s,' '); nativePrint(...) end
    function GetCurrentResourceName() return 'nexm_core' end
    function GetInvokingResource() return env.invoking end
    function GetResourceState(n) return env.resourceStates[n] or 'missing' end
    function GetResourcePath(n) return env.resourcePaths[n] or ('/resources/'..n) end
    function GetResourceMetadata(n,k) if k=='version' then return env.versions[n] end return nil end
    function GetPlayers() local o={}; for _,s in ipairs(env.players) do o[#o+1]=tostring(s) end; return o end
    function GetPlayerIdentifierByType(src,typ) local t=env.playerIdentifiers[tonumber(src)] or {}; return t[typ] end
    function GetPlayerName(src) if env.missingPlayers and env.missingPlayers[src] then return nil end return 'Player'..tostring(src) end
    function GetGameTimer() return env.timer end
    function IsPlayerAceAllowed(src,p) return env.aces[tonumber(src)] and env.aces[tonumber(src)][p]==true or false end
    function RegisterCommand(n,cb) env.commands[n]=cb end
    function AddEventHandler(n,cb) env.events[n]=env.events[n] or {}; local id=(env.nextHandler or 0)+1; env.nextHandler=id; env.events[n][id]=cb; return id end
    function RemoveEventHandler(id) for _,g in pairs(env.events) do g[id]=nil end end
    function RegisterNetEvent(n,cb) env.netEvents[n]=true; if cb then return AddEventHandler(n,cb) end end
    function TriggerEvent(n,...) local g=env.events[n] or {}; local ids={}; for id in pairs(g) do ids[#ids+1]=id end; table.sort(ids); for _,id in ipairs(ids) do if g[id] then g[id](...) end end end
    function TriggerClientEvent(n,target,...) env.clientEvents[#env.clientEvents+1]={name=n,target=target,args={...}} end
    function TriggerServerEvent(n,...) env.serverEvents[#env.serverEvents+1]={name=n,args={...}} end
    function SetTimeout(ms,cb) env.timeouts[#env.timeouts+1]={ms=ms,callback=cb} end
    function CreateThread(fn) fn() end
    function Wait() end
    function PerformHttpRequest(url,cb,method,body,headers) env.httpRequests[#env.httpRequests+1]={url=url,method=method,body=body,headers=headers}; cb(env.httpStatus,'',{}) end
    source=0
    local registeredExports={}
    exports=setmetatable({}, {__call=function(_,n,fn) registeredExports[n]=fn end,__index=function(_,resource) return setmetatable({}, {__index=function(_,method) return function(_self,...)
        local r=env.exportResources[resource]; local f=r and r[method]; if not f then error(('missing export %s:%s'):format(resource,method)) end; return f(...)
    end end}) end}); env.registeredExports=registeredExports
    MySQL={
      query={await=function(sql) if env.dbQueryFail then error('db query fail') end; if sql and sql:find('SELECT `migration`',1,true) then return {} end; return {} end},
      single={await=function() return nil end},scalar={await=function() return 1 end},
      insert={await=function() if env.dbInsertFail then error('db insert fail') end; return 1 end}, update={await=function() return 1 end},transaction={await=function() return true end}
    }
    promise={}; function promise.new() local p={resolved=false}; function p:resolve(v) self.resolved=true;self.value=v end; return p end
    Citizen={}; function Citizen.Await(p) return p.value end
end
local function runTimeouts(max)
    max=max or 100; local n=0
    while #env.timeouts>0 and n<max do n=n+1; local t=table.remove(env.timeouts,1); t.callback() end
    return n
end
local function loadServer(includeApi, includeCleanup)
    installStubs(); Config=nil; NEXM_INTERNAL=nil; GetCoreObject=nil; NEXM_CUSTOM_INVENTORY_ADAPTER=nil; NEXM_CUSTOM_NOTIFY_ADAPTER=nil; NEXM_CUSTOM_AUDIT_BACKEND=nil
    dofile(root..'/config.lua')
    for _,f in ipairs({'shared/init.lua','shared/constants.lua','shared/errors.lua','shared/validation.lua','shared/transport.lua','shared/semver.lua','shared/identity.lua','shared/network_validation.lua','shared/safe_data.lua','shared/locale.lua','shared/notify_contract.lua'}) do dofile(root..'/'..f) end
    for _,f in ipairs({'server/state.lua','server/logger.lua','server/ownership.lua','server/database.lua','server/migrations.lua','server/migrations/core.lua','server/registry_base.lua','server/managers/resources.lua','server/managers/services.lua','server/managers/features.lua','server/managers/integrations.lua','server/readiness.lua','server/framework_contract.lua','adapters/framework/esx.lua','adapters/framework/qbcore.lua','adapters/framework/qbox.lua','adapters/framework/standalone.lua','server/managers/framework.lua','server/player_cache.lua','server/player.lua','server/jobs.lua','server/lifecycle.lua','server/session_guard.lua','server/money.lua','server/inventory_contract.lua','custom/inventory.lua','adapters/inventory/ox_inventory.lua','adapters/inventory/qb_inventory.lua','adapters/inventory/esx.lua','adapters/inventory/qs_inventory.lua','server/managers/inventory.lua','server/inventory.lua','custom/audit.lua','server/audit.lua','server/rate_limit.lua','server/event_bus.lua','server/permissions.lua','server/callbacks.lua','server/managers/notify.lua','server/notify.lua','server/components.lua','server/diagnostics.lua'}) do dofile(root..'/'..f) end
    if includeApi then dofile(root..'/server/api.lua') end
    if includeCleanup then dofile(root..'/server/cleanup.lua') end
    return NEXM_INTERNAL
end
local function setReady(I)
    local S,C=I.Modules.State,I.Modules.Constants.STATES
    if S.Get()==C.BOOTING then S.Set(C.DATABASE);S.Set(C.MIGRATING);S.Set(C.FRAMEWORK);S.Set(C.PLATFORM);S.Set(C.READY) end
end
local function fakeFramework(I, store)
    local cb={}; local a={metadata={name='qbox',resource='qbx_core',version='1.24.0',capabilities={player={identity={character=true,account=true,license=true},job=true,duty=true},jobs={multiple=true},money={cash=true,bank=true},framework={permissions=true}}}}
    function a.IsAvailable() return env.resourceStates.qbx_core=='started' end; function a.Initialize() return true,nil end; function a.Shutdown() return true,nil end; function a.GetState() return 'HEALTHY' end
    function a.GetPlayer(s) return store[s] and {PlayerData=store[s]} or nil end; function a.IsPlayerLoaded(s) return store[s]~=nil end
    function a.GetCharacterIdentifier(s) return store[s] and store[s].char or nil,nil end; function a.GetAccountIdentifier(s) return store[s] and ('acct:'..store[s].char) or nil,nil end; function a.GetLicense(s) return store[s] and ('license:'..store[s].char) or nil,nil end; function a.GetCharacterName(s) return store[s] and store[s].name or nil,nil end
    function a.GetJob(s) local p=store[s]; return p and p.job or nil,nil end; function a.GetMoney(s,k) return store[s] and store[s].money[k] or nil,nil end; function a.AddMoney() return true,nil end; function a.RemoveMoney() return true,nil end; function a.HasFrameworkPermission(s,p) return env.aces[s] and env.aces[s][p] or false,nil end
    function a.SubscribePlayerLoaded(f) cb.load=f; return true,nil end; function a.SubscribePlayerUnloaded(f) cb.unload=f; return true,nil end; function a.SubscribeJobChanged(f) cb.job=f; return true,nil end; function a.SubscribeDutyChanged(f) cb.duty=f; return true,nil end; a._callbacks=cb; return a
end
local function initPlayer(I, src)
    src=src or 20; local store={[src]={char='CHAR'..src,name='Alice',money={cash=1000,bank=5000},job={name='police',label='Police',grade=3,gradeName='sergeant',onDuty=true}}}
    env.resourceStates.qbx_core='started'; Config.Framework='qbox'; I.Adapters.Framework.qbox=fakeFramework(I,store); I.Managers.Framework.RegisterBuiltinAdapters(); local ok,err=I.Managers.Framework.InitializeSelected(); expect('Phase6 fake framework initializes',ok==true,err and err.code)
    I.Modules.PlayerCache.Store(src,{source=src,identifier='qbox:character:'..store[src].char,identity={character=store[src].char,account='acct',license='license'},name=store[src].name,job=store[src].job,framework='qbox',loaded=true})
    return store
end

-- Notify contract ----------------------------------------------------------------
do
 local I=loadServer(false,false); local C,E=I.Modules.NotifyContract,I.Modules.Errors
 local good={metadata={name='x',resource='x',version='1.0.0',capabilities={},critical=false}}
 for _,m in ipairs({'IsAvailable','Initialize','Shutdown','GetState','Send'}) do good[m]=function() return true end end
 local ok,err=C.ValidateAdapter(good); expect('Notify contract accepts complete adapter',ok==true,err and err.code)
 good.metadata.critical=true; ok,err=C.ValidateAdapter(good); expect('Notify adapter critical=true rejected',ok==false and E.Is(err,'INVALID_NOTIFY_ADAPTER')); good.metadata.critical=false
 good.Send=nil; ok,err=C.ValidateAdapter(good); expect('Notify adapter missing Send rejected',ok==false and E.Is(err,'INVALID_NOTIFY_ADAPTER'))
 local p; p,err=C.ValidatePayload('hello','info',5000,{}); expect('Notify payload valid',p and p.type=='info' and p.duration==5000)
 p,err=C.ValidatePayload('','info',5000,{}); expect('Notify empty message rejected',p==nil and E.Is(err,'INVALID_ARGUMENT'))
 p,err=C.ValidatePayload('hello','danger',5000,{}); expect('Notify invalid type rejected',p==nil and E.Is(err,'INVALID_ARGUMENT'))
 p,err=C.ValidatePayload('hello','info',499,{}); expect('Notify too-short duration rejected',p==nil and E.Is(err,'INVALID_ARGUMENT'))
 p,err=C.ValidatePayload('hello','info',60001,{}); expect('Notify too-long duration rejected',p==nil and E.Is(err,'INVALID_ARGUMENT'))
 p,err=C.ValidatePayload(string.rep('x',2049),'info',5000,{}); expect('Notify huge message rejected',p==nil and E.Is(err,'INVALID_ARGUMENT'))
 local opts={adapter={icon='x'}}; p=C.ValidatePayload('hello','success',nil,opts); opts.adapter.icon='mutated'; expect('Notify options deep-copied',p.options.adapter.icon=='x')
end

-- Server notify selection / optional behavior ------------------------------------
do
 local I=loadServer(false,false); Config.Notify='none'; local ok,err=I.Managers.Notify.InitializeSelected(); expect('Notify none returns disabled',ok==false and I.Modules.Errors.Is(err,'NOTIFY_DISABLED')); expect('Notify component DISABLED',I.Modules.State.GetComponent('notify').state=='DISABLED')
 setReady(I); ok,err=I.Modules.Notify.Send(20,'hello','info',5000); expect('Notify Send disabled returns NOTIFY_DISABLED',ok==false and I.Modules.Errors.Is(err,'NOTIFY_DISABLED'))
end
do
 local I=loadServer(false,false); Config.Notify='auto'; Config.NotifyFallback=true; local ok,err=I.Managers.Notify.InitializeSelected(); expect('Notify auto none is unavailable not fatal',ok==false and I.Modules.Errors.Is(err,'NOTIFY_UNAVAILABLE')); expect('Notify auto none component UNAVAILABLE',I.Modules.State.GetComponent('notify').state=='UNAVAILABLE')
end
do
 local I=loadServer(false,false); Config.Notify='auto'; Config.NotifyFallback=true; env.resourceStates.ox_lib='started'; env.versions.ox_lib='3.39.0'; local ok,name=I.Managers.Notify.InitializeSelected(); expect('Notify auto selects ox_lib first',ok==true and name=='ox_lib')
 env.resourceStates.qbx_core='started'; I.Adapters.Framework.qbox=fakeFramework(I,{}); I.Managers.Framework.RegisterBuiltinAdapters(); I.Managers.Framework.InitializeSelected(); env.resourceStates.ox_lib='stopped'; ok,name=I.Managers.Notify.Refresh('test_stop'); expect('Notify fallback enabled moves temporarily to framework',ok==true and name=='qbox'); expect('Notify fallback marked healthy',I.Modules.State.GetComponent('notify').state=='HEALTHY')
 env.resourceStates.ox_lib='started'; ok,name=I.Managers.Notify.Refresh('test_recover'); expect('Notify resumes sticky primary after recovery',ok==true and name=='ox_lib')
end
do
 local I=loadServer(false,false); Config.Notify='auto'; Config.NotifyFallback=false; env.resourceStates.ox_lib='started'; env.versions.ox_lib='3.39.0'; local ok,name=I.Managers.Notify.InitializeSelected(); expect('Notify no-fallback initially selects ox_lib',ok==true and name=='ox_lib')
 env.resourceStates.qbx_core='started'; I.Adapters.Framework.qbox=fakeFramework(I,{}); I.Managers.Framework.RegisterBuiltinAdapters(); I.Managers.Framework.InitializeSelected(); env.resourceStates.ox_lib='stopped'; ok,name=I.Managers.Notify.Refresh('stop'); expect('Notify fallback disabled goes unavailable instead of switching',ok==false and I.Modules.Errors.Is(name,'NOTIFY_UNAVAILABLE')); expect('Notify fallback disabled component UNAVAILABLE',I.Modules.State.GetComponent('notify').state=='UNAVAILABLE')
end
do
 local I=loadServer(false,false); Config.Notify='ox_lib'; env.resourceStates.ox_lib='started'; env.versions.ox_lib='3.39.0'; I.Managers.Notify.InitializeSelected(); setReady(I); local ok,err=I.Modules.Notify.Send(20,'Server message','warning',1500,{title='NEXM'}); expect('Server normalized notify dispatch succeeds',ok==true and err==nil); local e=env.clientEvents[#env.clientEvents]; expect('Server notify uses one normalized client event',e and e.name=='nexm_core:client:notify' and e.target==20 and e.args[2]=='warning')
 local sourceText=assert(io.open(root..'/server/notify.lua')):read('*a'); expect('No generic client-to-server notify net event exists',not sourceText:find('RegisterNetEvent',1,true))
end

-- Notify absence never gates Core READY ------------------------------------------
do
 local I=loadServer(false,false); Config.Framework='standalone'; Config.Inventory='none'; Config.Notify='none'; dofile(root..'/server/bootstrap.lua'); expect('Core READY with Notify=none',I.Modules.State.IsReady()==true); expect('Bootstrapped Notify=none stays DISABLED',I.Modules.State.GetComponent('notify').state=='DISABLED')
end
do
 local I=loadServer(false,false); Config.Framework='standalone'; Config.Inventory='none'; Config.Notify='auto'; Config.NotifyFallback=true; dofile(root..'/server/bootstrap.lua'); expect('Core READY with auto and no notify provider',I.Modules.State.IsReady()==true); expect('Bootstrapped auto/no-notify is UNAVAILABLE',I.Modules.State.GetComponent('notify').state=='UNAVAILABLE')
end

-- Client notify adapters -----------------------------------------------------------
local function loadClientNotify()
 installStubs(); Config=nil;NEXM_INTERNAL=nil;NEXM_CUSTOM_NOTIFY_ADAPTER=nil; dofile(root..'/config.lua')
 for _,f in ipairs({'shared/init.lua','shared/constants.lua','shared/errors.lua','shared/validation.lua','shared/transport.lua','shared/semver.lua','shared/identity.lua','shared/network_validation.lua','shared/safe_data.lua','shared/locale.lua','shared/notify_contract.lua','custom/notify.lua','adapters/notify/ox_lib.lua','adapters/notify/esx.lua','adapters/notify/qbcore.lua','adapters/notify/qbox.lua','client/managers/notify.lua','client/notify.lua','client/state.lua','client/events.lua','client/callbacks.lua','client/api.lua'}) do dofile(root..'/'..f) end
 return NEXM_INTERNAL
end
do
 local I=loadClientNotify(); env.resourceStates.ox_lib='started'; local got; env.exportResources.ox_lib={notify=function(data) got=data end}; Config.Notify='ox_lib'; local ok,err=I.Managers.ClientNotify.Send('ox','success',2000,{title='T'}); expect('ox_lib client notify adapter sends',ok==true and got and got.description=='ox' and got.type=='success')
end
do
 local I=loadClientNotify(); env.resourceStates.es_extended='started';env.resourceStates.esx_notify='started';local got={};env.exportResources.es_extended={getSharedObject=function() return {ShowNotification=function(...) got={...} end} end};Config.Notify='esx';local ok=I.Managers.ClientNotify.Send('esx','warning',3000,{});expect('ESX client notify adapter sends',ok==true and got[1]=='esx' and got[2]=='warning')
end
do
 local I=loadClientNotify();env.resourceStates['qb-core']='started';local got={};env.exportResources['qb-core']={GetCoreObject=function() return {Functions={Notify=function(...) got={...} end}} end};Config.Notify='qbcore';local ok=I.Managers.ClientNotify.Send('qb','info',3000,{});expect('QBCore client notify maps info to primary',ok==true and got[2]=='primary')
end
do
 local I=loadClientNotify();env.resourceStates.qbx_core='started';local got={};env.exportResources.qbx_core={Notify=function(...) got={...} end};Config.Notify='qbox';local ok=I.Managers.ClientNotify.Send('qbox','info',3000,{});expect('Qbox client notify maps info to inform',ok==true and got[2]=='inform')
end
do
 local I=loadClientNotify();Config.Notify='custom';Config.NotifyCustomEnabled=true;NEXM_CUSTOM_NOTIFY_ADAPTER.metadata.implemented=true;local calls=0;NEXM_CUSTOM_NOTIFY_ADAPTER.Send=function() calls=calls+1;return true,nil end;local ok=I.Managers.ClientNotify.Send('custom','info',1000,{});expect('Custom notify uses same validated contract',ok==true and calls==1)
end

do
 local I=loadClientNotify(); env.invoking='client_product'; local N=GetCoreObject(); local ok=N.Locale.Register('en',{welcome='Welcome, {name}'}); local text=N.Locale.Get('welcome',{name='Client'}); expect('Client locale registration through facade works',ok==true); expect('Client locale lookup/interpolation works',text=='Welcome, Client')
end

-- Locale ownership / fallback / interpolation ------------------------------------
do
 local I=loadServer(false,false); local L,E=I.Modules.Locale,I.Modules.Errors; Config.Locale='lt'; Config.LocaleFallback='en'
 local input={hello='Hello, {name}',condition={warning='Warning {name}'}}; local ok,err=L.Register('en',input,'resA');expect('Locale en registers',ok==true); input.hello='MUTATED';input.condition.warning='MUTATED'; local v=L.Get('hello',{name='John'},'resA');expect('Locale registration input is immutable',v=='Hello, John'); v=L.Get('condition.warning',{name='Jane'},'resA');expect('Nested locale input flattened and immutable',v=='Warning Jane')
 ok=L.Register('lt',{hello='Labas, {name}'},'resA');expect('Locale lt registers',ok==true);v=L.Get('hello',{name='Jonas'},'resA');expect('Requested locale lookup works',v=='Labas, Jonas');v=L.Get('condition.warning',{name='Jonas'},'resA');expect('Missing lt falls back to en',v=='Warning Jonas');v=L.Get('missing_key',nil,'resA');expect('Missing all locales returns key itself',v=='missing_key')
 v=L.Get('hello',{},'resA');expect('Missing interpolation variable remains placeholder',v=='Labas, {name}');v=L.Get('hello',{name={x=1}},'resA');expect('Unsupported interpolation type is safe placeholder',v=='Labas, <unsupported>')
 local _,e=L.Get('',nil,'resA');expect('Invalid locale key rejected',E.Is(e,'INVALID_ARGUMENT'))
 ok,err=L.Register('en',{hello='dup'},'resA');expect('Same owner duplicate locale key rejected',ok==false and E.Is(err,'REGISTRATION_EXISTS'))
 ok,err=L.Register('en',{hello='Other'},'resB');expect('Different resource same locale key isolated',ok==true);v=L.Get('hello',{name='X'},'resB');expect('Resource-bound locale namespace isolated',v=='Other')
 local removed=L.CleanupOwner('resA');expect('Locale owner cleanup removes entries',removed>=2);v=L.Get('hello',nil,'resA');expect('Locale cleanup makes key unavailable',v=='hello');ok=L.Register('en',{hello='Again'},'resA');expect('Locale owner can re-register after restart',ok==true)
 local cyc={};cyc.self=cyc;ok,err=L.Register('en',cyc,'resC');expect('Cyclic locale table rejected',ok==false and E.Is(err,'INVALID_ARGUMENT'))
end

-- Audit normalization / failure isolation ----------------------------------------
do
 local I=loadServer(false,false); setReady(I); Config.Audit.Backends={console=false,database=false,discord=false,custom=false}; I.Modules.Audit.Initialize(); local ok,err=I.Modules.Audit.Log({action='system_started',data={a=1}},'resA');expect('Audit accepts system actor entry',ok==true and err==nil);expect('Audit no-backend does not queue',I.Modules.Audit.GetQueueDepth()==0)
 ok,err=I.Modules.Audit.Log({action='bad action'},'resA');expect('Audit invalid action rejected',ok==false and I.Modules.Errors.Is(err,'INVALID_ARGUMENT'));local cyc={};cyc.self=cyc;ok,err=I.Modules.Audit.Log({action='cycle',data=cyc},'resA');expect('Audit cyclic metadata rejected',ok==false and I.Modules.Errors.Is(err,'INVALID_ARGUMENT'));ok,err=I.Modules.Audit.Log({action='func',data={f=function()end}},'resA');expect('Audit function metadata rejected',ok==false and I.Modules.Errors.Is(err,'INVALID_ARGUMENT'))
end
do
 local I=loadServer(false,false); initPlayer(I,20); setReady(I); Config.Audit.Backends={console=false,database=false,discord=false,custom=true}; local captured; NEXM_CUSTOM_AUDIT_BACKEND.Send=function(entry) captured=entry;return true end;I.Modules.Audit.Initialize();local ok=I.Modules.Audit.Log({action='player_action',actor=20,subject='SUBJ',data={x=1}},'resA');runTimeouts();expect('Audit player actor accepted',ok==true);expect('Audit actor identity resolved authoritatively',captured and captured.actorCharacter=='CHAR20' and captured.actorName=='Alice');expect('Audit owner auto context preserved',captured and captured.ownerResource=='resA')
end
do
 local I=loadServer(false,false); setReady(I); Config.Audit.Backends={console=false,database=true,discord=false,custom=false}; env.dbInsertFail=true; I.Modules.Audit.Initialize(); local gameplay=true; local ok=I.Modules.Audit.Log({action='money_removed',data={amount=10}},'resA'); expect('Audit enqueue succeeds before backend execution',ok==true and gameplay==true);runTimeouts(20);local m=I.Modules.Audit.GetMetrics();expect('Audit DB failure retries then exhausts without failing gameplay',m.retries>=1 and m.failures>=1 and gameplay==true)
end
do
 local I=loadServer(false,false); setReady(I); Config.Audit.Backends={console=false,database=false,discord=true,custom=false};Config.Audit.DiscordWebhook='https://example.invalid/webhook';Config.Audit.DiscordIncludeIdentifiers=false;env.httpStatus=500;I.Modules.Audit.Initialize();local ok=I.Modules.Audit.Log({action='discord_action',subject='secret-character-id',data={x=1}},'resA');runTimeouts(20);local m=I.Modules.Audit.GetMetrics();expect('Discord audit failure uses bounded retry exhaustion',ok==true and m.retries>=1 and m.failures>=1);expect('Discord webhook request was attempted',#env.httpRequests>=1);expect('Default Discord payload omits subject identifier',not env.httpRequests[1].body:find('secret%-character%-id'))
end
do
 local I=loadServer(false,false);setReady(I);Config.Audit.Backends={console=false,database=false,discord=false,custom=true};Config.Audit.Queue.maxSize=2;Config.Audit.Queue.dropPolicy='oldest';NEXM_CUSTOM_AUDIT_BACKEND.Send=function() return true end;I.Modules.Audit.Initialize();I.Modules.Audit.Log({action='a'},'r');I.Modules.Audit.Log({action='b'},'r');I.Modules.Audit.Log({action='c'},'r');local m=I.Modules.Audit.GetMetrics();expect('Audit queue has bounded max size',I.Modules.Audit.GetQueueDepth()==2);expect('Audit queue full increments dropped metric',m.dropped==1);runTimeouts();expect('Audit bounded queue worker drains entries',I.Modules.Audit.GetQueueDepth()==0)
end
do
 local I=loadServer(false,false);Config.Audit.Enabled=false;I.Modules.Audit.Initialize();local ok,err=I.Modules.Audit.Log({action='x'},'r');expect('Explicitly disabled audit returns AUDIT_DISABLED',ok==false and I.Modules.Errors.Is(err,'AUDIT_DISABLED'));expect('Audit component DISABLED',I.Modules.State.GetComponent('audit').state=='DISABLED')
end

do
 local I=loadServer(false,false); setReady(I); Config.Audit.Backends={console=false,database=true,discord=false,custom=false}; env.dbQueryFail=true; local ok,err=I.Modules.Audit.Initialize(); expect('Audit DB schema failure does not fail Audit.Initialize',ok==true); expect('Audit DB schema failure marks component DEGRADED',I.Modules.State.GetComponent('audit').state=='DEGRADED')
end

-- Logger safety / suppression -----------------------------------------------------
do
 local I=loadServer(false,false);local L=I.Modules.Logger;Config.Logging.level='info';expect('Logger debug disabled at info level',L.IsEnabled('debug')==false);expect('Logger info enabled at info level',L.IsEnabled('info')==true);local cyc={};cyc.self=cyc;local ok=pcall(function() L.Info('safe cycle',{component='test',cycle=cyc},'resA') end);expect('Logger never throws on cyclic metadata',ok==true);ok=pcall(function() L.Warn('safe function',{component='test',f=function()end},'resA') end);expect('Logger never throws on function metadata',ok==true)
 L.ResetSuppressionForTests(); local function countLog(fragment) local n=0; for _,line in ipairs(env.prints) do if line:find(fragment,1,true) then n=n+1 end end; return n end; local beforeSame=countLog('] same metadata=');L.Warn('same',{component='x'},'resA');L.Warn('same',{component='x'},'resA');local same=countLog('] same metadata=')-beforeSame;expect('Logger suppresses repeated same owner/component error',same==1,same); local beforeCross=countLog('] same metadata=');L.Warn('same',{component='x'},'resB');L.Warn('same',{component='y'},'resA');local cross=countLog('] same metadata=')-beforeCross;expect('Logger does not cross-suppress different owner/component',cross==2,cross)
end

-- Services API polish -------------------------------------------------------------
do
 local I=loadServer(false,false);local S,E=I.Managers.Services,I.Modules.Errors;local api={DoThing=function()return 1 end,nested={enabled=true}};local ok,err=S.Register('justice',api,{version='1.2.3',apiVersion=2,capabilities={search=true}},'resA');expect('Service registers with version metadata',ok==true);local svc;svc,err=S.Get('justice',{apiVersion=2});expect('Service Get matching apiVersion succeeds',svc~=nil and err==nil);local has;has,err=S.Has('justice',{apiVersion=2});expect('Service Has matching apiVersion succeeds',has==true and err==nil);svc,err=S.Get('justice',{apiVersion=1});expect('Service API version mismatch returns structured error',svc==nil and E.Is(err,'SERVICE_API_VERSION_MISMATCH'));has,err=S.Has('missing');expect('Service Has missing is normal false',has==false and err==nil);svc,err=S.Get('missing');expect('Service Get missing returns SERVICE_UNAVAILABLE',svc==nil and E.Is(err,'SERVICE_UNAVAILABLE'))
 local pub=S.Get('justice');local mutateOk=pcall(function() pub.nested.enabled=false end);local methodMutateOk=pcall(function() pub.DoThing=function()return 9 end end);local again=S.Get('justice');expect('Service nested snapshot mutation is locally safe',mutateOk==true);expect('Service method snapshot mutation is locally safe',methodMutateOk==true);expect('Service deep API immutable to consumer',again.nested.enabled==true and again.DoThing()==1);local meta=S.GetMetadata('justice');meta.capabilities.search=false;expect('Service capability metadata immutable snapshot',S.GetMetadata('justice').capabilities.search==true)
 ok,err=S.Register('justice',{},{} ,'resB');expect('Foreign service collision rejected',ok==false and E.Is(err,'REGISTRATION_CONFLICT'));S.CleanupOwner('resA');svc,err=S.Get('justice');expect('Service owner stop removes service',svc==nil and E.Is(err,'SERVICE_UNAVAILABLE'));ok=S.Register('justice',{}, {apiVersion=1},'resA');expect('Service same owner can re-register after restart',ok==true)
end

-- Integrations / Components diagnostics -------------------------------------------
do
 local I=loadServer(false,false);local St=I.Modules.State;St.SetComponent('inventory','DISABLED',{reason='none'});local c=I.Modules.Components.Get('inventory');expect('Component API reports inventory disabled',c and c.state=='DISABLED');c.details.reason='mutated';expect('Component snapshot details immutable',I.Modules.Components.Get('inventory').details.reason=='none');expect('Component unknown returns nil',I.Modules.Components.Get('unknown')==nil)
 St.SetComponent('notify','UNAVAILABLE',{reason='none'});c=I.Modules.Components.Get('notify');expect('Component API reports notify unavailable',c.state=='UNAVAILABLE');expect('Integration state reflects component without selected provider',I.Managers.Integrations.GetState('notify')=='UNAVAILABLE');expect('Integration IsHealthy false when unavailable',I.Managers.Integrations.IsHealthy('notify')==false)
end

do
 local I=loadServer(false,false);setReady(I);local R=I.Managers.Resources;I.Modules.State.SetComponent('inventory','DISABLED');local ok,err=R.Register({name='res_no_inv',version='1.0.0',requiresCore='>=1.0.0-0',requirements={framework=false}},'res_no_inv');expect('Resource without inventory requirement registers while inventory disabled',ok==true);local status=R.GetRequirementStatus('res_no_inv');expect('Resource requirement diagnostics available',status and status.ok==true and type(status.checks)=='table')
end

-- Developer facade consistency / no Phase5 security regression ------------------
do
 local I=loadServer(true,false);setReady(I);env.invoking='resA';local N=GetCoreObject();expect('Server facade exposes Notify',type(N.Notify)=='table' and type(N.Notify.Send)=='function');expect('Server facade exposes Locale',type(N.Locale)=='table' and type(N.Locale.Get)=='function');expect('Server facade exposes Audit',type(N.Audit)=='table' and type(N.Audit.Log)=='function');expect('Server facade exposes Components',type(N.Components)=='table' and type(N.Components.Get)=='function');expect('Gameplay Integrations still has no Register',N.Integrations.Register==nil)
 local sourceText=assert(io.open(root..'/client/api.lua')):read('*a');expect('Client API still has no Money namespace',not sourceText:find('Money%s*='));expect('Client API still has no Inventory namespace',not sourceText:find('Inventory%s*='));expect('Client API still has no Permissions namespace',not sourceText:find('Permissions%s*='));expect('Client API has no Audit namespace',not sourceText:find('Audit%s*='))
 local eb=assert(io.open(root..'/server/event_bus.lua')):read('*a');expect('Phase6 did not network-expose internal event bus',not eb:find('RegisterNetEvent',1,true) and not eb:find('TriggerClientEvent',1,true))
end

do
 local I=loadServer(false,false); Config.Framework='standalone'; Config.Inventory='none'; Config.Notify='none'; dofile(root..'/server/bootstrap.lua'); local cmd=env.commands['nexm:status']; local ok=pcall(function() cmd(0,{'verbose'}) end); expect('nexm:status verbose is registered and safe',type(cmd)=='function' and ok==true); local all=I.Modules.Components.GetAll(); expect('Component GetAll exposes platform component snapshots',all.database and all.framework and all.inventory and all.notify and all.rpc and all.audit)
end

-- Public documentation files exist -----------------------------------------------
do
 local required={'README.md','docs/installation.md','docs/configuration.md','docs/architecture.md','docs/api-server.md','docs/api-client.md','docs/player.md','docs/jobs.md','docs/money.md','docs/inventory.md','docs/notifications.md','docs/permissions.md','docs/callbacks.md','docs/events.md','docs/localization.md','docs/logging.md','docs/audit.md','docs/services.md','docs/integrations.md','docs/migrations.md','docs/versions.md','docs/security.md','docs/troubleshooting.md','docs/creating-nexm-resource.md'}
 for _,f in ipairs(required) do local h=io.open(root..'/'..f);expect('Documentation exists: '..f,h~=nil);if h then h:close() end end
 local h=io.open(root..'/docs/creating-nexm-resource.md');if h then local s=h:read('*a');h:close();expect('Creating-resource guide uses NEXM Core object',s:find("GetCoreObject",1,true)~=nil);expect('Creating-resource example avoids direct ESX usage',not s:find("exports['es_extended']",1,true));expect('Creating-resource example avoids direct QBCore usage',not s:find("exports['qb%-core']"));expect('Creating-resource guide documents requirements',s:find('requirements',1,true)~=nil) end
end

-- Compile/load production Lua -----------------------------------------------------
do
 local files={}
 local p=io.popen("find '"..root.."' -type f -name '*.lua' ! -path '*/tests/*' | sort")
 for f in p:lines() do files[#files+1]=f end;p:close();local all=true;for _,f in ipairs(files) do local fn,err=loadfile(f);if not fn then all=false;print('[COMPILE FAIL] '..f..' :: '..tostring(err)) end end;expect('All Phase 2-6 production Lua files compile in harness',all)
end

print(('PHASE6 TESTS: %d, FAILED: %d'):format(total,failed))
os.exit(failed==0 and 0 or 1)
