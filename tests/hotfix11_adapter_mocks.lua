-- Actual adapter mock tests for hotfix.11 usable-item registration bridges.
local total, failed = 0, 0
local function expect(name, condition)
    total=total+1
    if condition then print('[PASS] '..name) else failed=failed+1; print('[FAIL] '..name) end
end
local Codes=setmetatable({
    FRAMEWORK_UNAVAILABLE='FRAMEWORK_UNAVAILABLE', FRAMEWORK_INITIALIZATION_FAILED='FRAMEWORK_INITIALIZATION_FAILED',
    UNSUPPORTED_FEATURE='UNSUPPORTED_FEATURE', INTEGRATION_ERROR='INTEGRATION_ERROR', INVENTORY_UNAVAILABLE='INVENTORY_UNAVAILABLE',
    ADAPTER_ERROR='ADAPTER_ERROR', INVALID_ITEM='INVALID_ITEM'
},{__index=function(_,k) return k end})
local Errors={Create=function(code,message,context) return {code=code,message=message,context=context or {}} end}

GetResourceState=function() return 'started' end
GetResourceMetadata=function() return 'test-version' end
AddEventHandler=function() return 1 end
RemoveEventHandler=function() end
IsPlayerAceAllowed=function() return false end

local exportedFunctions={}
local resources={}
exports=setmetatable({}, {
    __index=function(_,k) return resources[k] end,
    __call=function(_,name,fn) exportedFunctions[name]=fn end
})

local function reset(kind)
    NEXM_INTERNAL={Modules={Errors=Errors,Constants={ERROR_CODES=Codes}},Adapters={Framework={},Inventory={}}}
    exportedFunctions={}
end

-- ESX
reset()
local esxCallback
local esxUsables={}
resources['es_extended']={getSharedObject=function() return {
    RegisterUsableItem=function(item,cb) esxUsables[item]=true; esxCallback=cb end,
    GetUsableItems=function() return esxUsables end,
    GetPlayerFromId=function() return nil end
} end}
dofile('adapters/framework/esx.lua')
local esx=NEXM_INTERNAL.Adapters.Framework.esx
local ok=esx.Initialize(); expect('ESX adapter initializes',ok==true)
local got
local rok,rerr=esx.RegisterUsableItem('bench',function(src,ctx,gen) got={src=src,ctx=ctx,gen=gen}; return true end,11)
expect('ESX registers through official wrapper',rok==true and rerr==nil and type(esxCallback)=='function')
esxCallback(51,{slot=2,metadata={kind='a'}})
expect('ESX normalized callback context',got and got.src==51 and got.gen==11 and got.ctx.name=='bench' and got.ctx.slot==2 and got.ctx.metadata.kind=='a' and got.ctx.provider=='esx' and got.ctx.amount==1)
esxUsables.external_item=true
local collision,collisionErr=esx.RegisterUsableItem('external_item',function() end,99)
expect('ESX external usable collision rejected',collision==false and collisionErr and collisionErr.code==Codes.ALREADY_REGISTERED)

-- QBCore
reset()
local qbCallback
local qbUsables={}
local qbCore={Functions={
    GetPlayer=function() return nil end,
    CanUseItem=function(item) return qbUsables[item] end,
    CreateUseableItem=function(item,cb) qbUsables[item]={func=cb,resource='nexm_core'}; qbCallback=cb end
}}
resources['qb-core']={GetCoreObject=function() return qbCore end}
dofile('adapters/framework/qbcore.lua')
local qb=NEXM_INTERNAL.Adapters.Framework.qbcore
ok=qb.Initialize(); expect('QBCore adapter initializes',ok==true)
got=nil; rok,rerr=qb.RegisterUsableItem('bench',function(src,ctx,gen) got={src=src,ctx=ctx,gen=gen}; return true end,12)
expect('QBCore registers through CreateUseableItem',rok==true and rerr==nil and type(qbCallback)=='function')
qbCallback(52,{slot=3,info={kind='b'}})
expect('QBCore normalized callback context',got and got.src==52 and got.gen==12 and got.ctx.name=='bench' and got.ctx.slot==3 and got.ctx.metadata.kind=='b' and got.ctx.provider=='qbcore' and got.ctx.amount==1)
qbUsables.external_item={func=function() end,resource='other_resource'}
collision,collisionErr=qb.RegisterUsableItem('external_item',function() end,99)
expect('QBCore external usable collision rejected',collision==false and collisionErr and collisionErr.code==Codes.ALREADY_REGISTERED)

-- Qbox
reset()
local qboxCallback
local qboxUsables={}
resources['qbx_core']={
    GetPlayer=function() return nil end,
    CanUseItem=function(_,item) return qboxUsables[item] end,
    CreateUseableItem=function(_,item,cb) qboxUsables[item]=cb; qboxCallback=cb end
}
dofile('adapters/framework/qbox.lua')
local qbox=NEXM_INTERNAL.Adapters.Framework.qbox
ok=qbox.Initialize(); expect('Qbox adapter initializes',ok==true)
got=nil; rok,rerr=qbox.RegisterUsableItem('bench',function(src,ctx,gen) got={src=src,ctx=ctx,gen=gen}; return true end,13)
expect('Qbox registers through qbx_core export',rok==true and rerr==nil and type(qboxCallback)=='function')
qboxCallback(53,{slot=4,metadata={kind='c'}})
expect('Qbox normalized callback context',got and got.src==53 and got.gen==13 and got.ctx.name=='bench' and got.ctx.slot==4 and got.ctx.metadata.kind=='c' and got.ctx.provider=='qbox' and got.ctx.amount==1)
qboxUsables.external_item=function() end
collision,collisionErr=qbox.RegisterUsableItem('external_item',function() end,99)
expect('Qbox external usable collision rejected',collision==false and collisionErr and collisionErr.code==Codes.ALREADY_REGISTERED)

-- ox_inventory static server.export bridge
reset()
local oxDefinition={name='bench',consume=0,server={export='nexm_core.UseRegisteredItem'}}
resources['ox_inventory']={
    Items=function(_,name) if name=='bench' then return oxDefinition end end,
    GetItemCount=function() return 1 end, AddItem=function() return true end, RemoveItem=function() return true end,
    CanCarryItem=function() return true end, GetInventoryItems=function() return {} end
}
local dispatched
NEXM_INTERNAL.Modules.UsableItems={DispatchProviderUse=function(name,src,ctx,gen,provider) dispatched={name=name,src=src,ctx=ctx,gen=gen,provider=provider}; return true,nil end}
GetInvokingResource=function() return 'ox_inventory' end
dofile('adapters/inventory/ox_inventory.lua')
local ox=NEXM_INTERNAL.Adapters.Inventory.ox_inventory
ok=ox.Initialize(); expect('ox_inventory adapter initializes',ok==true)
rok,rerr=ox.RegisterUsableItem('bench')
expect('ox definition accepts exact Core bridge',rok==true and rerr==nil and type(exportedFunctions.UseRegisteredItem)=='function')
local inv={id=54,player={ped=1},items={[5]={name='bench',count=1,metadata={kind='d'}}}}
local ret=exportedFunctions.UseRegisteredItem('usingItem',{name='bench'},inv,5,{})
expect('ox bridge dispatches authoritative normalized context',ret==nil and dispatched and dispatched.src==54 and dispatched.name=='bench' and dispatched.ctx.slot==5 and dispatched.ctx.metadata.kind=='d' and dispatched.ctx.provider=='ox_inventory')
expect('ox bridge rejects wrong invoking resource',(function() GetInvokingResource=function() return 'evil_resource' end; return exportedFunctions.UseRegisteredItem('usingItem',{name='bench'},inv,5,{})==false end)())
GetInvokingResource=function() return 'ox_inventory' end
oxDefinition.consume=1
local bad,badErr=ox.RegisterUsableItem('bench')
expect('ox bridge rejects automatic consumption config',bad==false and badErr and badErr.code==Codes.INTEGRATION_ERROR)
oxDefinition.consume=0; oxDefinition.server.export='other_resource.use'
bad,badErr=ox.RegisterUsableItem('bench')
expect('ox bridge rejects wrong server export',bad==false and badErr and badErr.code==Codes.INTEGRATION_ERROR)

print(('RESULT tests=%d pass=%d fail=%d'):format(total,total-failed,failed))
os.exit(failed==0 and 0 or 1)
