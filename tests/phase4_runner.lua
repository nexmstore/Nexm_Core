local root = arg[1] or '.'
local total, failed = 0, 0
local function expect(name, condition, detail)
    total = total + 1
    if condition then print('[PASS] '..name) else failed=failed+1; print('[FAIL] '..name..(detail and (' :: '..tostring(detail)) or '')) end
end

local env={}
local function installStubs()
    env={resourceStates={oxmysql='started'},resourcePaths={},versions={},playerIdentifiers={},players={},events={},clientEvents={},commands={},invoking=nil,exportResources={},nextHandler=0,removedHandlers=0}
    json={encode=function() return '{}' end,decode=function() return {} end}
    function GetCurrentResourceName() return 'nexm_core' end
    function GetInvokingResource() return env.invoking end
    function GetResourceState(name) return env.resourceStates[name] or 'missing' end
    function GetResourcePath(name) return env.resourcePaths[name] or ('/resources/'..name) end
    function GetResourceMetadata(name,key) if key=='version' then return env.versions[name] end return nil end
    function GetPlayers() local o={}; for _,s in ipairs(env.players) do o[#o+1]=tostring(s) end return o end
    function GetPlayerIdentifierByType(src,typ) local t=env.playerIdentifiers[tonumber(src)] or {}; return t[typ] end
    function GetPlayerName(src) return 'Player'..tostring(src) end
    function RegisterCommand(name,cb) env.commands[name]=cb end
    function AddEventHandler(name,cb) env.nextHandler=env.nextHandler+1; env.events[name]=env.events[name] or {}; env.events[name][env.nextHandler]=cb; return env.nextHandler end
    function RemoveEventHandler(tok) for _,g in pairs(env.events) do if g[tok] then g[tok]=nil; env.removedHandlers=env.removedHandlers+1; return end end end
    function RegisterNetEvent(name,cb) if cb then return AddEventHandler(name,cb) end end
    function TriggerEvent(name,...) local g=env.events[name] or {}; local ids={}; for id in pairs(g) do ids[#ids+1]=id end; table.sort(ids); for _,id in ipairs(ids) do if g[id] then g[id](...) end end end
    function TriggerClientEvent(name,target,...) env.clientEvents[#env.clientEvents+1]={name=name,target=target,args={...}} end
    function TriggerServerEvent() end
    function CreateThread(fn) fn() end
    function Wait() end
    source=0
    local registeredExports={}
    exports=setmetatable({}, {__call=function(_,name,fn) registeredExports[name]=fn end, __index=function(_,resource)
        return setmetatable({}, {__index=function(_,method)
            return function(_,...)
                local r=env.exportResources[resource]; local f=r and r[method]
                if not f then error(('missing export %s:%s'):format(resource,method)) end
                return f(...)
            end
        end})
    end})
    env.registeredExports=registeredExports
    MySQL={query={await=function(sql) if sql and sql:find('SELECT `migration`',1,true) then return {} end return {} end},single={await=function() return nil end},scalar={await=function() return 1 end},insert={await=function() return 1 end},update={await=function() return 1 end},transaction={await=function() return true end}}
end

local function loadAll(includeApi)
    installStubs(); Config=nil; NEXM_INTERNAL=nil; GetCoreObject=nil; NEXM_TEST_BOOT_ORDER=nil; NEXM_CUSTOM_INVENTORY_ADAPTER=nil
    dofile(root..'/config.lua')
    dofile(root..'/shared/init.lua'); dofile(root..'/shared/constants.lua'); dofile(root..'/shared/errors.lua'); dofile(root..'/shared/validation.lua'); dofile(root..'/shared/transport.lua'); dofile(root..'/shared/semver.lua'); dofile(root..'/shared/identity.lua'); dofile(root..'/shared/safe_data.lua'); dofile(root..'/shared/locale.lua'); dofile(root..'/shared/notify_contract.lua')
    dofile(root..'/server/state.lua'); dofile(root..'/server/logger.lua'); dofile(root..'/server/ownership.lua'); dofile(root..'/server/database.lua'); dofile(root..'/server/migrations.lua'); dofile(root..'/server/migrations/core.lua')
    dofile(root..'/server/registry_base.lua'); dofile(root..'/server/managers/resources.lua'); dofile(root..'/server/managers/services.lua'); dofile(root..'/server/managers/features.lua'); dofile(root..'/server/managers/integrations.lua'); dofile(root..'/server/readiness.lua')
    dofile(root..'/server/framework_contract.lua'); dofile(root..'/adapters/framework/esx.lua'); dofile(root..'/adapters/framework/qbcore.lua'); dofile(root..'/adapters/framework/qbox.lua'); dofile(root..'/adapters/framework/standalone.lua'); dofile(root..'/server/managers/framework.lua')
    dofile(root..'/server/player_cache.lua'); dofile(root..'/server/player.lua'); dofile(root..'/server/jobs.lua'); dofile(root..'/server/lifecycle.lua')
    dofile(root..'/server/session_guard.lua'); dofile(root..'/server/money.lua'); dofile(root..'/server/inventory_contract.lua'); dofile(root..'/custom/inventory.lua')
    dofile(root..'/adapters/inventory/ox_inventory.lua'); dofile(root..'/adapters/inventory/qb_inventory.lua'); dofile(root..'/adapters/inventory/esx.lua'); dofile(root..'/adapters/inventory/qs_inventory.lua'); dofile(root..'/server/managers/inventory.lua'); dofile(root..'/server/inventory.lua')
    dofile(root..'/custom/audit.lua'); dofile(root..'/server/audit.lua'); dofile(root..'/server/managers/notify.lua'); dofile(root..'/server/notify.lua'); dofile(root..'/server/components.lua'); dofile(root..'/server/diagnostics.lua'); if includeApi then dofile(root..'/server/api.lua') end
    return NEXM_INTERNAL
end

local function fakeFramework(I, store)
    local cb={}; store=store or {}
    local a={metadata={name='qbox',resource='qbx_core',version='test',capabilities={player={identity={character=true,account=true,license=true},job=true,duty=true},jobs={multiple=false},money={cash=true,bank=true},framework={permissions=false}}}}
    function a.IsAvailable() return env.resourceStates.qbx_core=='started' end
    function a.Initialize() return true,nil end; function a.Shutdown() return true,nil end; function a.GetState() return 'HEALTHY' end
    function a.GetPlayer(s) return store[s] and {} or nil end; function a.IsPlayerLoaded(s) return store[s]~=nil end
    function a.GetCharacterIdentifier(s) return store[s] and store[s].char,nil end; function a.GetAccountIdentifier(s) return store[s] and ('acct:'..store[s].char),nil end
    function a.GetLicense(s) return store[s] and ('license:'..store[s].char),nil end; function a.GetCharacterName(s) return store[s] and store[s].name,nil end
    function a.GetJob(s) return store[s] and {name='police',label='Police',grade=1,gradeName='officer',onDuty=true},nil end
    function a.GetMoney(s,acct) return store[s] and store[s].money[acct],nil end
    function a.AddMoney(s,acct,amount) if not store[s] then return false end; store[s].money[acct]=store[s].money[acct]+amount; return true,nil end
    function a.RemoveMoney(s,acct,amount) if not store[s] or store[s].money[acct]<amount then return false end; store[s].money[acct]=store[s].money[acct]-amount; return true,nil end
    function a.SubscribePlayerLoaded(f) cb.load=f; return true,nil end; function a.SubscribePlayerUnloaded(f) cb.unload=f; return true,nil end; function a.SubscribeJobChanged(f) cb.job=f; return true,nil end; function a.SubscribeDutyChanged(f) cb.duty=f; return true,nil end
    a._callbacks=cb; return a
end
local function initFakeFramework(I, sourceId)
    sourceId=sourceId or 20
    local store={[sourceId]={char='CHAR'..sourceId,name='Test '..sourceId,money={cash=1000,bank=5000}}}
    env.resourceStates.qbx_core='started'; Config.Framework='qbox'; I.Adapters.Framework.qbox=fakeFramework(I,store); I.Managers.Framework.RegisterBuiltinAdapters(); local ok,err=I.Managers.Framework.InitializeSelected()
    expect('Fake framework initializes for Phase 4 service tests',ok==true,err and err.code)
    local ident='qbox:character:'..store[sourceId].char
    I.Modules.PlayerCache.Store(sourceId,{source=sourceId,identifier=ident,identity={character=store[sourceId].char,account='acct',license='license'},name=store[sourceId].name,job={name='police',label='Police',grade=1,gradeName='officer',onDuty=true},framework='qbox',loaded=true})
    return store
end

-- Final framework money capability contract ---------------------------------
do
 local I=loadAll(false); local C,E=I.Modules.FrameworkContract,I.Modules.Errors; local a=fakeFramework(I,{[1]={char='A',name='A',money={cash=1,bank=1}}})
 local ok,err=C.Validate(a); expect('Framework contract accepts mandatory money subtree',ok==true)
 a.metadata.capabilities.money.bank=nil; ok,err=C.Validate(a); expect('Missing money.bank is INVALID_FRAMEWORK_ADAPTER',ok==false and E.Is(err,'INVALID_FRAMEWORK_ADAPTER'))
 a.metadata.capabilities.money.bank=false; ok,err=C.Validate(a); expect('Explicit unsupported money capability false is valid',ok==true)
 a.metadata.capabilities.money.cash='yes'; ok,err=C.Validate(a); expect('Wrong money capability type rejected',ok==false and E.Is(err,'INVALID_FRAMEWORK_ADAPTER'))
 a.metadata.capabilities.money.cash=true; a.GetMoney=nil; ok,err=C.Validate(a); expect('Money-capability liar missing GetMoney rejected',ok==false and E.Is(err,'INVALID_FRAMEWORK_ADAPTER'))
end

-- Money service: validation and canonical contracts --------------------------
do
 local I=loadAll(false); local E=I.Modules.Errors; local store=initFakeFramework(I,20); local M=I.Modules.Money
 local v,err=M.Get(20,'cash'); expect('Money.Get cash',v==1000 and err==nil)
 v,err=M.Get(20,'bank'); expect('Money.Get bank',v==5000 and err==nil)
 local ok; ok,err=M.CanAfford(20,'cash',500); expect('Money.CanAfford true',ok==true and err==nil)
 ok,err=M.CanAfford(20,'cash',50000); expect('Money.CanAfford false is normal negative',ok==false and err==nil)
 ok,err=M.Add(20,'cash',250,'phase4_test'); expect('Money.Add cash succeeds',ok==true and store[20].money.cash==1250)
 ok,err=M.Add(20,'bank',500,'phase4_test'); expect('Money.Add bank succeeds',ok==true and store[20].money.bank==5500)
 ok,err=M.Remove(20,'cash',200,'phase4_test'); expect('Money.Remove cash succeeds',ok==true and store[20].money.cash==1050)
 ok,err=M.Remove(20,'bank',400,'phase4_test'); expect('Money.Remove bank succeeds',ok==true and store[20].money.bank==5100)
 ok,err=M.Remove(20,'cash',999999,'phase4_test'); expect('Money.Remove insufficient returns structured error',ok==false and E.Is(err,'INSUFFICIENT_FUNDS'))
 v,err=M.Get(20,'crypto'); expect('Money invalid canonical account rejected',v==nil and E.Is(err,'UNSUPPORTED_ACCOUNT'))
 local invalid={-1,0,'1','5000',0/0,math.huge,-math.huge,1.5,nil}
 for idx,x in pairs(invalid) do ok,err=M.Add(20,'cash',x,'test'); expect('Money invalid amount rejected #'..tostring(idx),ok==false and E.Is(err,'INVALID_AMOUNT')) end
 ok,err=M.Add(20,'cash',Config.Security.MaxMoneyTransaction+1,'test'); expect('Money amount over configured max rejected',ok==false and E.Is(err,'INVALID_AMOUNT'))
 ok,err=M.Add(20,'cash',1,nil); expect('Money mutation requires reason',ok==false and E.Is(err,'INVALID_ARGUMENT'))
 ok,err=M.Add(20,'cash',1,''); expect('Money empty reason rejected',ok==false and E.Is(err,'INVALID_ARGUMENT'))
 ok,err=M.Add(20,'cash',1,'bad\nreason'); expect('Money control-character reason rejected',ok==false and E.Is(err,'INVALID_ARGUMENT'))
 local long=string.rep('x',(Config.Security.maxTransactionReasonLength or 128)+1); ok,err=M.Add(20,'cash',1,long); expect('Money overlong reason rejected',ok==false and E.Is(err,'INVALID_ARGUMENT'))
 v,err=M.Get('20','cash'); expect('Money source numeric string is not coerced',v==nil and E.Is(err,'INVALID_ARGUMENT'))
 v,err=M.Get(nil,'cash'); expect('Money nil source rejected',v==nil and E.Is(err,'INVALID_ARGUMENT'))
 v,err=M.Get(-1,'cash'); expect('Money negative source rejected',v==nil and E.Is(err,'INVALID_ARGUMENT'))
 v,err=M.Get(0,'cash'); expect('Money zero source rejected',v==nil and E.Is(err,'INVALID_ARGUMENT'))
 v,err=M.Get(0/0,'cash'); expect('Money NaN source rejected',v==nil and E.Is(err,'INVALID_ARGUMENT'))
 v,err=M.Get(math.huge,'cash'); expect('Money infinite source rejected',v==nil and E.Is(err,'INVALID_ARGUMENT'))
 ok,err=M.Add(20,'cash',1,123); expect('Money non-string reason rejected',ok==false and E.Is(err,'INVALID_ARGUMENT'))
 v,err=M.Get(999,'cash'); expect('Money missing normalized player fails closed',v==nil and E.Is(err,'PLAYER_NOT_FOUND'))
end


do
 local I=loadAll(false); local store=initFakeFramework(I,20); local a=I.Managers.Framework.GetSelected(); a.metadata.capabilities.money.bank=false; local v,err=I.Modules.Money.Get(20,'bank'); expect('Framework explicit money.bank=false returns UNSUPPORTED_ACCOUNT',v==nil and I.Modules.Errors.Is(err,'UNSUPPORTED_ACCOUNT'))
end

-- Real framework money adapters under official current semantics -------------
do
 local I=loadAll(false); env.resourceStates.es_extended='started'; env.versions.es_extended='1.15.2'; env.playerIdentifiers[1]={license='license:e'}
 local bal={money=1000,bank=3000}; local xp={identifier='char1:e',license='license:e',job={name='police',label='Police',grade=1,grade_name='officer',onDuty=true}}
 function xp.getAccount(n) return {name=n,money=bal[n]} end; function xp.addAccountMoney(n,a) bal[n]=bal[n]+a end; function xp.removeAccountMoney(n,a) bal[n]=bal[n]-a end
 function xp.getIdentifier() return xp.identifier end; function xp.getName() return 'ESX' end; function xp.getJob() return xp.job end
 env.exportResources.es_extended={getSharedObject=function() return {GetPlayerFromId=function(s) return s==1 and xp end,IsPlayerLoaded=function(s) return s==1 end} end}
 local a=I.Adapters.Framework.esx; local ok,err=a.Initialize(); expect('ESX money adapter initializes',ok==true)
 local v=a.GetMoney(1,'cash'); expect('ESX cash maps to money account',v==1000)
 v=a.GetMoney(1,'bank'); expect('ESX bank maps to bank account',v==3000)
 ok,err=a.AddMoney(1,'cash',100,'test'); expect('ESX AddMoney verifies authoritative result',ok==true and bal.money==1100)
 ok,err=a.RemoveMoney(1,'bank',200,'test'); expect('ESX RemoveMoney verifies authoritative result',ok==true and bal.bank==2800)
 ok,err=a.RemoveMoney(1,'cash',9999,'test'); expect('ESX RemoveMoney rejects insufficient funds',ok==false and I.Modules.Errors.Is(err,'INSUFFICIENT_FUNDS'))
end
do
 local I=loadAll(false); env.resourceStates['qb-core']='started'; local bal={cash=900,bank=4000}; local p={PlayerData={citizenid='QB',license='license:qb',money=bal,charinfo={firstname='Q',lastname='B'},job={name='police',label='Police',grade={level=1,name='officer'},onduty=true}},Functions={}}
 p.Functions.GetMoney=function(n) return bal[n] end; p.Functions.AddMoney=function(n,a) bal[n]=bal[n]+a; return true end; p.Functions.RemoveMoney=function(n,a) if bal[n]<a then return false end bal[n]=bal[n]-a; return true end
 env.exportResources['qb-core']={GetCoreObject=function() return {Functions={GetPlayer=function(s) return s==2 and p end}} end}
 local a=I.Adapters.Framework.qbcore; local ok=a.Initialize(); expect('QBCore money adapter initializes',ok==true)
 local v=a.GetMoney(2,'cash'); expect('QBCore cash GetMoney',v==900)
 ok=a.AddMoney(2,'bank',100,'test'); expect('QBCore AddMoney bool + post-state verification',ok==true and bal.bank==4100)
 local err; ok,err=a.RemoveMoney(2,'cash',950,'test'); expect('QBCore insufficient removal rejected',ok==false and I.Modules.Errors.Is(err,'INSUFFICIENT_FUNDS'))
end
do
 local I=loadAll(false); env.resourceStates.qbx_core='started'; local bal={cash=700,bank=2600}; local p={PlayerData={citizenid='QX',userId=9,license='license:qx',money=bal,charinfo={firstname='Q',lastname='X'},job={name='police',label='Police',grade={level=1,name='officer'},onduty=true}}}
 env.exportResources.qbx_core={GetPlayer=function(s) return s==3 and p end,GetMoney=function(_,n) return bal[n] end,AddMoney=function(_,n,a) bal[n]=bal[n]+a; return true end,RemoveMoney=function(_,n,a) if bal[n]<a then return false end bal[n]=bal[n]-a; return true end}
 local a=I.Adapters.Framework.qbox; local ok=a.Initialize(); expect('Qbox money adapter initializes',ok==true)
 local v=a.GetMoney(3,'bank'); expect('Qbox GetMoney direct export',v==2600)
 ok=a.AddMoney(3,'cash',50,'test'); expect('Qbox AddMoney direct export verified',ok==true and bal.cash==750)
 local err; ok,err=a.RemoveMoney(3,'cash',9999,'test'); expect('Qbox insufficient removal rejected',ok==false and I.Modules.Errors.Is(err,'INSUFFICIENT_FUNDS'))
end


-- Complete real-adapter money matrix -----------------------------------------
do
 local I=loadAll(false); env.resourceStates.es_extended='started'; local bal={money=2000,bank=6000}; local xp={identifier='char:m',license='license:m',job={name='police',label='Police',grade=1,grade_name='officer',onDuty=true}}
 function xp.getAccount(n) return {name=n,money=bal[n]} end; function xp.addAccountMoney(n,a) bal[n]=bal[n]+a end; function xp.removeAccountMoney(n,a) bal[n]=bal[n]-a end; function xp.getIdentifier() return xp.identifier end; function xp.getName() return 'M' end; function xp.getJob() return xp.job end
 env.exportResources.es_extended={getSharedObject=function() return {GetPlayerFromId=function() return xp end,IsPlayerLoaded=function() return true end} end}; local a=I.Adapters.Framework.esx; a.Initialize()
 local v=a.GetMoney(1,'cash'); expect('ESX matrix Get cash',v==2000); v=a.GetMoney(1,'bank'); expect('ESX matrix Get bank',v==6000)
 local ok=a.AddMoney(1,'cash',100,'m'); expect('ESX matrix Add cash exact once',ok==true and bal.money==2100); ok=a.AddMoney(1,'bank',200,'m'); expect('ESX matrix Add bank exact once',ok==true and bal.bank==6200)
 ok=a.RemoveMoney(1,'cash',50,'m'); expect('ESX matrix Remove cash exact once',ok==true and bal.money==2050); ok=a.RemoveMoney(1,'bank',100,'m'); expect('ESX matrix Remove bank exact once',ok==true and bal.bank==6100)
end
do
 local I=loadAll(false); env.resourceStates['qb-core']='started'; local bal={cash=2000,bank=6000}; local p1={PlayerData={citizenid='QB2',license='l',money=bal,charinfo={firstname='Q',lastname='B'},job={name='police',label='Police',grade={level=1,name='officer'},onduty=true}},Functions={}}
 p1.Functions.GetMoney=function(n) return bal[n] end; p1.Functions.AddMoney=function(n,a) bal[n]=bal[n]+a; return true end; p1.Functions.RemoveMoney=function(n,a) if bal[n]<a then return false end; bal[n]=bal[n]-a; return true end
 env.exportResources['qb-core']={GetCoreObject=function() return {Functions={GetPlayer=function() return p1 end}} end}; local a=I.Adapters.Framework.qbcore; a.Initialize()
 local v=a.GetMoney(1,'cash'); expect('QBCore matrix Get cash',v==2000); v=a.GetMoney(1,'bank'); expect('QBCore matrix Get bank',v==6000)
 local ok=a.AddMoney(1,'cash',100,'m'); expect('QBCore matrix Add cash exact once',ok==true and bal.cash==2100); ok=a.AddMoney(1,'bank',200,'m'); expect('QBCore matrix Add bank exact once',ok==true and bal.bank==6200)
 ok=a.RemoveMoney(1,'cash',50,'m'); expect('QBCore matrix Remove cash exact once',ok==true and bal.cash==2050); ok=a.RemoveMoney(1,'bank',100,'m'); expect('QBCore matrix Remove bank exact once',ok==true and bal.bank==6100)
end
do
 local I=loadAll(false); env.resourceStates.qbx_core='started'; local bal={cash=2000,bank=6000}; local px={PlayerData={citizenid='QX2',userId=5,license='l',money=bal,charinfo={firstname='Q',lastname='X'},job={name='police',label='Police',grade={level=1,name='officer'},onduty=true}}}
 env.exportResources.qbx_core={GetPlayer=function() return px end,GetMoney=function(_,n) return bal[n] end,AddMoney=function(_,n,a) bal[n]=bal[n]+a; return true end,RemoveMoney=function(_,n,a) if bal[n]<a then return false end bal[n]=bal[n]-a; return true end}; local a=I.Adapters.Framework.qbox; a.Initialize()
 local v=a.GetMoney(1,'cash'); expect('Qbox matrix Get cash',v==2000); v=a.GetMoney(1,'bank'); expect('Qbox matrix Get bank',v==6000)
 local ok=a.AddMoney(1,'cash',100,'m'); expect('Qbox matrix Add cash exact once',ok==true and bal.cash==2100); ok=a.AddMoney(1,'bank',200,'m'); expect('Qbox matrix Add bank exact once',ok==true and bal.bank==6200)
 ok=a.RemoveMoney(1,'cash',50,'m'); expect('Qbox matrix Remove cash exact once',ok==true and bal.cash==2050); ok=a.RemoveMoney(1,'bank',100,'m'); expect('Qbox matrix Remove bank exact once',ok==true and bal.bank==6100)
end

-- Inventory contract and lie tests -------------------------------------------
do
 local I=loadAll(false); local C,E=I.Modules.InventoryContract,I.Modules.Errors
 local function inv(caps) local a={metadata={name='fake',resource='fake-inv',version='1.0.0',critical=true,capabilities=caps or {metadata=true,metadataFilter=true,canCarry=true,getItems=true}}}; for _,m in ipairs({'IsAvailable','Initialize','Shutdown','GetState','HasItem','GetItemCount','AddItem','RemoveItem','CanCarry','GetItems'}) do a[m]=function() return true end end; return a end
 local a=inv(); local ok,err=C.Validate(a); expect('Inventory contract accepts complete adapter',ok==true)
 a.metadata.capabilities.metadata=nil; ok,err=C.Validate(a); expect('Inventory missing mandatory capability rejected',ok==false and E.Is(err,'INVALID_INVENTORY_ADAPTER'))
 a=inv(); a.metadata.capabilities.canCarry='yes'; ok,err=C.Validate(a); expect('Inventory capability wrong type rejected',ok==false and E.Is(err,'INVALID_INVENTORY_ADAPTER'))
 a=inv(); a.metadata.critical=false; ok,err=C.Validate(a); expect('Inventory must be critical=true',ok==false and E.Is(err,'INVALID_INVENTORY_ADAPTER'))
 a=inv(); a.CanCarry=nil; ok,err=C.Validate(a); expect('Adapter claiming canCarry with missing required method rejected',ok==false and E.Is(err,'INVALID_INVENTORY_ADAPTER'))
 a=inv(); a.RemoveItem=nil; ok,err=C.Validate(a); expect('Adapter claiming metadataFilter without remove implementation rejected',ok==false and E.Is(err,'INVALID_INVENTORY_ADAPTER'))
 a=inv(); a.GetItems=nil; ok,err=C.Validate(a); expect('getItems=true requires GetItems method',ok==false and E.Is(err,'INVALID_INVENTORY_ADAPTER'))
 a=inv({metadata=false,metadataFilter=false,canCarry=false,getItems=false}); a.GetItems=nil; ok,err=C.Validate(a); expect('Explicit unsupported inventory capabilities false are valid',ok==true)
end

local function oxExports(storage, options)
 options=options or {}; storage=storage or {}
 local function eq(a,b) if a==b then return true end; if type(a)~='table' or type(b)~='table' then return false end; for k,v in pairs(a) do if not eq(v,b[k]) then return false end end; for k,v in pairs(b) do if a[k]==nil then return false end end; return true end
 local function list(s) storage[s]=storage[s] or {}; return storage[s] end
 return {
  GetItemCount=function(s,name,metadata,strict) local c=0; for _,x in ipairs(list(s)) do if x.name==name and (metadata==nil or eq(x.metadata or {},metadata)) then c=c+x.count end end return c end,
  CanCarryItem=function(s,name,count,metadata) return options.canCarry~=false end,
  AddItem=function(s,name,count,metadata) if options.addFailure then return false,options.addFailure end; if options.mutateMetadata and metadata then metadata.nested.quality=1 end; list(s)[#list(s)+1]={name=name,count=count,metadata=metadata}; return true end,
  RemoveItem=function(s,name,count,metadata,slot,ignore,strict) local left=count; for idx=#list(s),1,-1 do local x=list(s)[idx]; if x.name==name and (metadata==nil or eq(x.metadata or {},metadata)) then local n=math.min(left,x.count); x.count=x.count-n; left=left-n; if x.count==0 then table.remove(list(s),idx) end; if left==0 then break end end end; if left>0 then return false,'not_enough_items' end; return true end,
  GetInventoryItems=function(s) return list(s) end
 }
end

-- Inventory detection / critical stickiness ---------------------------------
do
 local I=loadAll(false); initFakeFramework(I,20); env.resourceStates.ox_inventory='started'; env.exportResources.ox_inventory=oxExports({}); Config.Inventory='auto'; local ok,err=I.Managers.Inventory.InitializeSelected(); expect('Inventory detection only ox_inventory selects ox_inventory',ok==true and I.Managers.Inventory.GetName()=='ox_inventory')
end
do
 local I=loadAll(false); initFakeFramework(I,20); env.resourceStates['qb-inventory']='started'; env.exportResources['qb-inventory']={GetItemCount=function() return 0 end,CanAddItem=function() return true end,AddItem=function() return true end,RemoveItem=function() return true end}; Config.Inventory='auto'; local ok=I.Managers.Inventory.InitializeSelected(); expect('Inventory detection only qb-inventory selects qb-inventory',ok==true and I.Managers.Inventory.GetName()=='qb-inventory')
end
do
 local I=loadAll(false); initFakeFramework(I,20); env.resourceStates.ox_inventory='started'; env.resourceStates['qb-inventory']='started'; env.exportResources.ox_inventory=oxExports({}); env.exportResources['qb-inventory']={}; Config.Inventory='auto'; local ok,err=I.Managers.Inventory.InitializeSelected(); expect('Multiple inventories + auto fails closed',ok==false and I.Modules.Errors.Is(err,'AMBIGUOUS_INVENTORY_INTEGRATION'))
end
do
 local I=loadAll(false); initFakeFramework(I,20); env.resourceStates.ox_inventory='started'; env.resourceStates['qb-inventory']='started'; env.exportResources.ox_inventory=oxExports({}); env.exportResources['qb-inventory']={}; Config.Inventory='ox_inventory'; local ok=I.Managers.Inventory.InitializeSelected(); expect('Multiple inventories + explicit selection chooses configured backend',ok==true and I.Managers.Inventory.GetName()=='ox_inventory')
 I.Managers.Inventory.InstallResourceMonitoring(); env.resourceStates.ox_inventory='missing'; env.resourceStates['qb-inventory']='started'; TriggerEvent('onResourceStop','ox_inventory'); local a,e=I.Managers.Inventory.RequireHealthy(); expect('Selected inventory stop becomes unavailable',a==nil and I.Modules.Errors.Is(e,'INVENTORY_UNAVAILABLE')); expect('Other backend is not hot-selected',I.Managers.Inventory.GetName()=='ox_inventory')
 env.resourceStates.ox_inventory='started'; TriggerEvent('onResourceStart','ox_inventory'); a,e=I.Managers.Inventory.RequireHealthy(); expect('Same selected inventory recovers',a~=nil and e==nil and I.Managers.Inventory.GetName()=='ox_inventory')
end

-- ox_inventory strict metadata service semantics -----------------------------
do
 local I=loadAll(false); initFakeFramework(I,20); env.resourceStates.ox_inventory='started'; local storage={[20]={{name='part',count=2,metadata={serial='A'}},{name='part',count=4,metadata={serial='B'}}}}; env.exportResources.ox_inventory=oxExports(storage); Config.Inventory='ox_inventory'; I.Managers.Inventory.InitializeSelected(); local Inv,E=I.Modules.Inventory,I.Modules.Errors
 local c,err=Inv.GetItemCount(20,'part',{serial='A'}); expect('ox metadata GetItemCount isolates variant A',c==2 and err==nil)
 local has; has,err=Inv.HasItem(20,'part',2,{serial='A'}); expect('ox metadata HasItem A',has==true and err==nil)
 has,err=Inv.HasItem(20,'part',3,{serial='A'}); expect('ox metadata HasItem does not borrow variant B',has==false and err==nil)
 local ok; ok,err=Inv.RemoveItem(20,'part',1,{serial='A'}); expect('ox strict metadata RemoveItem succeeds',ok==true)
 c=Inv.GetItemCount(20,'part',{serial='A'}); local cb=Inv.GetItemCount(20,'part',{serial='B'}); expect('ox remove A leaves B untouched',c==1 and cb==4)
 ok,err=Inv.AddItem(20,'part',1,{serial='C'}); expect('ox AddItem with metadata succeeds',ok==true)
 c=Inv.GetItemCount(20,'part',{serial='C'}); expect('ox added metadata variant is queryable',c==1)
 env.exportResources.ox_inventory.CanCarryItem=function() return false end; ok,err=Inv.CanCarry(20,'heavy',1,nil); expect('ox CanCarry false is normal negative',ok==false and err==nil)
 ok,err=Inv.AddItem(20,'heavy',1,nil); expect('AddItem respects CanCarry and returns NO_SPACE',ok==false and E.Is(err,'NO_SPACE'))
end

-- metadata input deep copy ----------------------------------------------------
do
 local I=loadAll(false); initFakeFramework(I,20); env.resourceStates.ox_inventory='started'; local storage={}; env.exportResources.ox_inventory=oxExports(storage,{mutateMetadata=true}); Config.Inventory='ox_inventory'; I.Managers.Inventory.InitializeSelected(); local meta={serial='ABC',nested={quality=100}}; local ok,err=I.Modules.Inventory.AddItem(20,'part',1,meta); expect('Inventory AddItem succeeds when backend mutates its metadata copy',ok==true); expect('Caller metadata remains deep-immutable from backend mutation',meta.nested.quality==100 and meta.serial=='ABC')
end

-- qb-inventory conservative metadata capability ------------------------------
do
 local I=loadAll(false); initFakeFramework(I,20); env.resourceStates['qb-inventory']='started'; local count=3; env.exportResources['qb-inventory']={GetItemCount=function() return count end,CanAddItem=function() return true end,AddItem=function(s,n,a,slot,info) count=count+a; return true end,RemoveItem=function(s,n,a) if count<a then return false end count=count-a; return true end}; env.exportResources['qb-core']={GetPlayer=function() return {PlayerData={items={{name='water',amount=count,info={quality=1}}}}} end}; Config.Inventory='qb-inventory'; I.Managers.Inventory.InitializeSelected(); local Inv,E=I.Modules.Inventory,I.Modules.Errors
 local c=Inv.GetItemCount(20,'water'); expect('qb-inventory name-only count works',c==3)
 local ok,err=Inv.AddItem(20,'water',1,{quality=1}); expect('qb-inventory metadata creation supported',ok==true)
 c,err=Inv.GetItemCount(20,'water',{quality=1}); expect('qb-inventory metadata-filter count rejected safely',c==nil and E.Is(err,'UNSUPPORTED_FEATURE'))
 ok,err=Inv.RemoveItem(20,'water',1,{quality=1}); expect('qb-inventory metadata-filter removal rejected safely',ok==false and E.Is(err,'UNSUPPORTED_FEATURE'))
 ok,err=Inv.RemoveItem(20,'water',1,nil); expect('qb-inventory name-only exact amount removal works',ok==true)
end

-- ESX native inventory conservative capabilities -----------------------------
do
 local I=loadAll(false); initFakeFramework(I,20); env.resourceStates.es_extended='started'; local counts={water=2}; local xp={}
 xp.getInventoryItem=function(n) return {name=n,count=counts[n] or 0} end; xp.addInventoryItem=function(n,a) counts[n]=(counts[n] or 0)+a end; xp.removeInventoryItem=function(n,a) counts[n]=(counts[n] or 0)-a end; xp.canCarryItem=function() return true end; xp.getInventory=function() return {{name='water',count=counts.water}} end
 env.exportResources.es_extended={getSharedObject=function() return {GetConfig=function(k) if k=='CustomInventory' then return false end end,GetPlayerFromId=function(s) return s==20 and xp end} end}; Config.Inventory='esx'; local ok,err=I.Managers.Inventory.InitializeSelected(); expect('ESX native inventory selected only when not using custom inventory',ok==true)
 local caps=I.Managers.Inventory.GetSelected().metadata.capabilities; expect('ESX native declares metadata=false/filter=false conservatively',caps.metadata==false and caps.metadataFilter==false)
 local Inv,E=I.Modules.Inventory,I.Modules.Errors; local c=Inv.GetItemCount(20,'water'); expect('ESX native GetItemCount',c==2); ok=Inv.AddItem(20,'water',1,nil); expect('ESX native AddItem verified',ok==true and counts.water==3); ok=Inv.RemoveItem(20,'water',1,nil); expect('ESX native RemoveItem verified',ok==true and counts.water==2); ok,err=Inv.AddItem(20,'water',1,{quality=1}); expect('ESX native metadata add refused',ok==false and E.Is(err,'UNSUPPORTED_FEATURE'))
end

-- qs-inventory documented adapter architecture -------------------------------
do
 local I=loadAll(false); env.resourceStates['qs-inventory']='started'; local items={{name='gem',amount=1,info={serial='A'}},{name='gem',amount=2,info={serial='B'}}}; env.exportResources['qs-inventory']={GetInventory=function() return items end,CanCarryItem=function() return true end,AddItem=function() return true end,RemoveItem=function() return true end}; local a=I.Adapters.Inventory.qs_inventory; local ok=a.Initialize(); expect('qs-inventory documented adapter initializes against declared exports',ok==true); local c=a.GetItemCount(1,'gem',{serial='A'}); expect('qs-inventory documented metadata filtering architecture counts subset',c==1); ok=a.CanCarry(1,'gem',1,nil); expect('qs-inventory documented CanCarryItem architecture',ok==true)
end


-- Priority and custom inventory adapter validation ---------------------------
do
 local I=loadAll(false); initFakeFramework(I,20); env.resourceStates.ox_inventory='started'; env.resourceStates['qb-inventory']='started'; env.exportResources.ox_inventory=oxExports({}); env.exportResources['qb-inventory']={}; Config.Inventory='auto'; Config.Integrations.priorities.inventory={'qb-inventory','ox_inventory'}; local ok=I.Managers.Inventory.InitializeSelected(); expect('Explicit inventory priority resolves ambiguity deterministically',ok==true and I.Managers.Inventory.GetName()=='qb-inventory')
end
do
 local I=loadAll(false); initFakeFramework(I,20); NEXM_CUSTOM_INVENTORY_ADAPTER.enabled=true; Config.Inventory='custom'; local ok,err=I.Managers.Inventory.InitializeSelected(); expect('Editable custom adapter passes the same validator when explicitly enabled',ok==true and I.Managers.Inventory.GetName()=='custom')
end
do
 local I=loadAll(false); initFakeFramework(I,20); NEXM_CUSTOM_INVENTORY_ADAPTER.enabled=true; NEXM_CUSTOM_INVENTORY_ADAPTER.metadata.capabilities.metadata=nil; Config.Inventory='custom'; local ok,err=I.Managers.Inventory.InitializeSelected(); expect('Invalid custom adapter gets no contract bypass',ok==false and I.Modules.Errors.Is(err,'INVALID_INVENTORY_ADAPTER'))
end

-- GetItems normalization across supported adapters ---------------------------
do
 local I=loadAll(false); env.resourceStates.ox_inventory='started'; env.exportResources.ox_inventory={GetInventoryItems=function() return {[4]={name='water',count=2,slot=4,metadata={q=1}}} end}; local a=I.Adapters.Inventory.ox_inventory; a.Initialize(); local items=a.GetItems(1); expect('ox GetItems normalizes name/count/slot/metadata',items[1].name=='water' and items[1].count==2 and items[1].slot==4 and items[1].metadata.q==1)
end
do
 local I=loadAll(false); env.resourceStates['qb-inventory']='started'; env.exportResources['qb-inventory']={}; env.exportResources['qb-core']={GetPlayer=function() return {PlayerData={items={[3]={name='water',amount=5,slot=3,info={q=2}}}}} end}; local a=I.Adapters.Inventory.qb_inventory; a.Initialize(); local items=a.GetItems(1); expect('qb GetItems normalizes amount/info into count/metadata',items[1].count==5 and items[1].metadata.q==2)
end
do
 local I=loadAll(false); env.resourceStates.es_extended='started'; local xp={getInventory=function() return {{name='water',count=7}} end}; env.exportResources.es_extended={getSharedObject=function() return {GetConfig=function() return false end,GetPlayerFromId=function() return xp end} end}; local a=I.Adapters.Inventory.esx; a.Initialize(); local items=a.GetItems(1); expect('ESX GetItems normalizes default inventory item count',items[1].name=='water' and items[1].count==7 and items[1].metadata==nil)
end
do
 local I=loadAll(false); env.resourceStates['qs-inventory']='started'; local raw={{name='gem',amount=2,info={serial='A'}}}; local removed=0; env.exportResources['qs-inventory']={GetInventory=function() return raw end,CanCarryItem=function() return true end,AddItem=function(_,n,a,slot,meta) raw[#raw+1]={name=n,amount=a,info=meta}; return true end,RemoveItem=function(_,n,a,slot,meta) removed=removed+a; return true end}; local a=I.Adapters.Inventory.qs_inventory; a.Initialize(); local ok=a.AddItem(1,'gem',1,{serial='C'}); expect('qs documented AddItem architecture',ok==true); ok=a.RemoveItem(1,'gem',1,{serial='A'}); expect('qs documented metadata RemoveItem architecture',ok==true and removed==1); local items=a.GetItems(1); expect('qs GetItems normalizes amount/info',items[1].count==2 and items[1].metadata.serial=='A')
end

-- Backend error mapping / exact remove safeguards ----------------------------
do
 local I=loadAll(false); initFakeFramework(I,20); env.resourceStates.ox_inventory='started'; env.exportResources.ox_inventory=oxExports({},{addFailure='invalid_item'}); Config.Inventory='ox_inventory'; I.Managers.Inventory.InitializeSelected(); local ok,err=I.Modules.Inventory.AddItem(20,'does_not_exist',1,nil); expect('Backend invalid_item normalizes to INVALID_ITEM',ok==false and I.Modules.Errors.Is(err,'INVALID_ITEM'))
end
do
 local I=loadAll(false); initFakeFramework(I,20); env.resourceStates.ox_inventory='started'; local st={[20]={{name='x',count=1,metadata={a=1}},{name='x',count=3,metadata={a=2}}}}; env.exportResources.ox_inventory=oxExports(st); Config.Inventory='ox_inventory'; I.Managers.Inventory.InitializeSelected(); local ok,err=I.Modules.Inventory.RemoveItem(20,'x',2,{a=1}); expect('Exact metadata removal never borrows other variants when insufficient',ok==false and I.Modules.Errors.Is(err,'INSUFFICIENT_ITEMS')); local c=I.Modules.Inventory.GetItemCount(20,'x',{a=2}); expect('Insufficient exact removal leaves other metadata variant untouched',c==3)
end

-- strict inventory validation -------------------------------------------------
do
 local I=loadAll(false); initFakeFramework(I,20); env.resourceStates.ox_inventory='started'; env.exportResources.ox_inventory=oxExports({}); Config.Inventory='ox_inventory'; I.Managers.Inventory.InitializeSelected(); local Inv,E=I.Modules.Inventory,I.Modules.Errors
 local ok,err=Inv.AddItem('20','x',1,nil); expect('Inventory source numeric string rejected',ok==false and E.Is(err,'INVALID_ARGUMENT'))
 ok,err=Inv.AddItem(nil,'x',1,nil); expect('Inventory nil source rejected',ok==false and E.Is(err,'INVALID_ARGUMENT'))
 ok,err=Inv.AddItem(-1,'x',1,nil); expect('Inventory negative source rejected',ok==false and E.Is(err,'INVALID_ARGUMENT'))
 ok,err=Inv.AddItem(0,'x',1,nil); expect('Inventory zero source rejected',ok==false and E.Is(err,'INVALID_ARGUMENT'))
 ok,err=Inv.AddItem(0/0,'x',1,nil); expect('Inventory NaN source rejected',ok==false and E.Is(err,'INVALID_ARGUMENT'))
 ok,err=Inv.AddItem(math.huge,'x',1,nil); expect('Inventory infinite source rejected',ok==false and E.Is(err,'INVALID_ARGUMENT'))
 ok,err=Inv.AddItem(20,'x',1,'metadata'); expect('Inventory non-table metadata rejected',ok==false and E.Is(err,'INVALID_ARGUMENT'))
 ok,err=Inv.AddItem(20,'',1,nil); expect('Inventory empty item rejected',ok==false and E.Is(err,'INVALID_ITEM'))
 ok,err=Inv.AddItem(20,'bad\nitem',1,nil); expect('Inventory control-character item rejected',ok==false and E.Is(err,'INVALID_ITEM'))
 for idx,x in pairs({-1,0,'1',0/0,math.huge,1.5}) do ok,err=Inv.AddItem(20,'x',x,nil); expect('Inventory invalid amount rejected #'..idx,ok==false and E.Is(err,'INVALID_AMOUNT')) end
 ok,err=Inv.AddItem(20,'x',Config.Security.MaxItemTransaction+1,nil); expect('Inventory over-max amount rejected',ok==false and E.Is(err,'INVALID_AMOUNT'))
 local cyc={}; cyc.self=cyc; ok,err=Inv.AddItem(20,'x',1,cyc); expect('Inventory cyclic metadata rejected',ok==false and E.Is(err,'INVALID_ARGUMENT'))
end

-- session race guards and degradation ----------------------------------------
do
 local I=loadAll(false); local store=initFakeFramework(I,20); env.resourceStates.ox_inventory='started'; env.exportResources.ox_inventory=oxExports({}); Config.Inventory='ox_inventory'; I.Managers.Inventory.InitializeSelected(); local Guard,E=I.Modules.SessionGuard,I.Modules.Errors
 local ctx=Guard.Capture(20); I.Modules.PlayerCache.Remove(20); store[20]={char='NEW',name='New',money={cash=500,bank=500}}; I.Modules.PlayerCache.Store(20,{source=20,identifier='qbox:character:NEW',identity={character='NEW',account='acct2',license='lic2'},name='New',job={name='police',label='Police',grade=1,gradeName='officer',onDuty=true},framework='qbox',loaded=true}); local ok,err=Guard.Validate(ctx); expect('Delayed character-A continuation rejected after character-B session',ok==false and E.Is(err,'STALE_CHARACTER_SESSION'))
 local mutated=false; local still=Guard.Validate(ctx); if still then mutated=true end; expect('Stale async guard prevents late Money/Inventory continuation from mutating B',mutated==false)
 I.Managers.Framework.InstallResourceMonitoring(); env.resourceStates.qbx_core='missing'; TriggerEvent('onResourceStop','qbx_core'); local v,me=I.Modules.Money.Get(20,'cash'); expect('Framework degradation makes Money fail FRAMEWORK_UNAVAILABLE',v==nil and E.Is(me,'FRAMEWORK_UNAVAILABLE')); local added,ie=I.Modules.Inventory.AddItem(20,'x',1,nil); expect('Framework degradation also fail-closes inventory mutation session safety',added==false and E.Is(ie,'FRAMEWORK_UNAVAILABLE'))
end



-- mutation workflow session-race guards -------------------------------------
do
 local I=loadAll(false); local store=initFakeFramework(I,20); local E=I.Modules.Errors; local adapter=I.Managers.Framework.GetSelected(); local removeCalled=false; local switched=false
 adapter.GetMoney=function(source,account)
   if not switched then switched=true; I.Modules.PlayerCache.Remove(20); store[20]={char='B',name='B',money={cash=777,bank=777}}; I.Modules.PlayerCache.Store(20,{source=20,identifier='qbox:character:B',identity={character='B',account='b',license='b'},name='B',job={name='police',label='Police',grade=1,gradeName='officer',onDuty=true},framework='qbox',loaded=true}) end
   return 1000,nil
 end
 adapter.RemoveMoney=function() removeCalled=true; return true,nil end
 local ok,err=I.Modules.Money.Remove(20,'cash',100,'race_test'); expect('Money.Remove detects session switch during affordability read',ok==false and E.Is(err,'STALE_CHARACTER_SESSION')); expect('Stale Money.Remove never reaches mutation adapter after session switch',removeCalled==false and store[20].money.cash==777)
end
do
 local I=loadAll(false); local store=initFakeFramework(I,20); env.resourceStates.ox_inventory='started'; local addCalled=false; local switched=false
 env.exportResources.ox_inventory={GetItemCount=function() return 0 end,CanCarryItem=function()
   if not switched then switched=true; I.Modules.PlayerCache.Remove(20); store[20]={char='B2',name='B2',money={cash=1,bank=1}}; I.Modules.PlayerCache.Store(20,{source=20,identifier='qbox:character:B2',identity={character='B2',account='b',license='b'},name='B2',job={name='police',label='Police',grade=1,gradeName='officer',onDuty=true},framework='qbox',loaded=true}) end
   return true
 end,AddItem=function() addCalled=true; return true end,RemoveItem=function() return true end,GetInventoryItems=function() return {} end}
 Config.Inventory='ox_inventory'; I.Managers.Inventory.InitializeSelected(); local ok,err=I.Modules.Inventory.AddItem(20,'x',1,nil); expect('Inventory.AddItem detects session switch during CanCarry preflight',ok==false and I.Modules.Errors.Is(err,'STALE_CHARACTER_SESSION')); expect('Stale Inventory.AddItem never reaches mutation export',addCalled==false)
end

-- framework-backed money recovery -------------------------------------------
do
 local I=loadAll(false); local store=initFakeFramework(I,20); I.Managers.Framework.InstallResourceMonitoring(); local before=I.Modules.Money.Get(20,'cash'); expect('Money available before selected framework stop',before==1000)
 env.resourceStates.qbx_core='missing'; TriggerEvent('onResourceStop','qbx_core'); local _,err=I.Modules.Money.Get(20,'cash'); expect('Money unavailable while selected framework is stopped',I.Modules.Errors.Is(err,'FRAMEWORK_UNAVAILABLE'))
 env.resourceStates.qbx_core='started'; TriggerEvent('onResourceStart','qbx_core'); expect('Same framework recovery restores money component health',I.Modules.State.GetComponent('money').state=='HEALTHY' and I.Managers.Framework.GetName()=='qbox')
end

-- client/server separation + public read-only integration --------------------
do
 local f=assert(io.open(root..'/client/api.lua','r')); local client=f:read('*a'); f:close(); expect('Client public facade does not expose Money namespace',not client:match('facade%.Money')); expect('Client public facade does not expose Inventory namespace',not client:match('facade%.Inventory'))
 local bad=false; for _,path in ipairs({root..'/server/money.lua',root..'/server/inventory.lua',root..'/server/api.lua'}) do local h=assert(io.open(path)); local s=h:read('*a'); h:close(); if s:find('nexm:money:add',1,true) or s:find('nexm:inventory:addItem',1,true) then bad=true end end; expect('No generic client-accessible money/inventory mutation event exists',not bad)
 local I=loadAll(true); initFakeFramework(I,20); env.resourceStates.ox_inventory='started'; env.exportResources.ox_inventory=oxExports({}); Config.Inventory='ox_inventory'; I.Managers.Inventory.InitializeSelected(); env.invoking='gameplay'; local api=GetCoreObject(); expect('Gameplay integration API has no Register mutation surface',api.Integrations.Register==nil); local caps=api.Integrations.GetCapabilities('inventory','ox_inventory'); expect('Gameplay integration capability API is read-only snapshot',type(caps)=='table' and caps.metadata==true)
end

-- compile/load safety for every product Lua file ------------------------------
do
 local p=io.popen("find '"..root.."' -path '"..root.."/tests' -prune -o -name '*.lua' -print")
 local okAll=true; for file in p:lines() do local fn,err=loadfile(file); if not fn then okAll=false; print('[COMPILE ERROR] '..file..' :: '..tostring(err)) end end; p:close(); expect('All Phase 2/3/4 production Lua files compile in harness',okAll)
end

print(('PHASE4 TESTS: %d, FAILED: %d'):format(total,failed))
if failed>0 then os.exit(1) end
