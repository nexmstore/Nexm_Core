-- Offline regression harness for NEXM Core hotfix.11 usable-item registry.
local total, failed = 0, 0
local function expect(name, condition)
    total = total + 1
    if condition then
        print(('[PASS] %s'):format(name))
    else
        failed = failed + 1
        print(('[FAIL] %s'):format(name))
    end
end

Config = { Debug = false, Security = { maxItemNameLength = 128 } }

local Codes = {
    INVALID_ITEM='INVALID_ITEM', INVALID_HANDLER='INVALID_HANDLER', ALREADY_REGISTERED='ALREADY_REGISTERED',
    INVALID_ARGUMENT='INVALID_ARGUMENT', REGISTRATION_NOT_FOUND='REGISTRATION_NOT_FOUND',
    INVENTORY_UNAVAILABLE='INVENTORY_UNAVAILABLE', FRAMEWORK_UNAVAILABLE='FRAMEWORK_UNAVAILABLE',
    UNSUPPORTED_FEATURE='UNSUPPORTED_FEATURE', INTEGRATION_ERROR='INTEGRATION_ERROR'
}
local Errors = {}
function Errors.Create(code, message, context) return {code=code,message=message,context=context or {}} end
function Errors.Is(value, code) return type(value)=='table' and value.code and (not code or value.code==code) end

local Validation = {}
function Validation.String(value, o)
    if type(value)~='string' then return false, Errors.Create(Codes.INVALID_ARGUMENT,'bad string') end
    if o and o.nonEmpty and value=='' then return false, Errors.Create(Codes.INVALID_ARGUMENT,'empty') end
    if o and o.max and #value>o.max then return false, Errors.Create(Codes.INVALID_ARGUMENT,'long') end
    return true,nil,value
end
function Validation.Source(value)
    if type(value)~='number' or value <= 0 or value % 1 ~= 0 then return false, Errors.Create(Codes.INVALID_ARGUMENT,'bad source') end
    return true,nil,value
end
local function serializable(v, seen, depth)
    if v==nil then return true end
    local t=type(v)
    if t=='string' or t=='number' or t=='boolean' then return true end
    if t~='table' then return false end
    depth=(depth or 0)+1; if depth>4 then return false end
    seen=seen or {}; if seen[v] then return false end; seen[v]=true
    local n=0
    for k,x in pairs(v) do n=n+1; if n>64 or not serializable(k,seen,depth) or not serializable(x,seen,depth) then return false end end
    seen[v]=nil; return true
end
function Validation.SerializableTable(value)
    if type(value)~='table' or not serializable(value) then return false, Errors.Create(Codes.INVALID_ARGUMENT,'bad options') end
    return true,nil,value
end

local Callable = { Is=function(v) return type(v)=='function' end }
local Logger = { Infrastructure=function() end, Debug=function() end }

local inventoryName='qb-inventory'
local frameworkName='qbcore'
local registeredCallbacks={}
local frameworkAdapter = {
    metadata={capabilities={framework={usableItems=true}}},
    RegisterUsableItem=function(item, dispatcher, generation)
        registeredCallbacks[item] = function(source, context)
            return dispatcher(item, source, context, generation, frameworkName)
        end
        return true,nil
    end
}
local removeCalls=0
local inventoryAdapter = {
    metadata={capabilities={usableItems=false}},
    RemoveItem=function() removeCalls=removeCalls+1; return true,nil end
}
local InventoryManager={
    GetName=function() return inventoryName end,
    GetSelected=function() return inventoryAdapter end,
    RequireHealthy=function() return inventoryAdapter,nil end,
}
local FrameworkManager={
    GetName=function() return frameworkName end,
    IsHealthy=function() return true end,
    RequireHealthy=function() return frameworkAdapter,nil end,
}

NEXM_INTERNAL={
    Modules={Errors=Errors,Validation=Validation,Logger=Logger,Constants={ERROR_CODES=Codes},Callable=Callable},
    Managers={Inventory=InventoryManager,Framework=FrameworkManager}
}
AddEventHandler=function() end

dofile('server/usable_items.lua')
local U=NEXM_INTERNAL.Modules.UsableItems

local calls=0
local lastSource,lastContext
local function handler(source, context)
    calls=calls+1; lastSource=source; lastContext=context
end

local ok,err=U.Register('example_bench',handler,{purpose='placement'},'resource_a')
expect('valid item registers',ok==true and err==nil)
local cb=registeredCallbacks.example_bench
expect('framework callback bound',type(cb)=='function')
local used,useErr=cb(42,{name='example_bench',amount=99,slot=7,metadata={quality=5},provider='qbcore'})
expect('handler invoked',used==true and useErr==nil and calls==1)
expect('source forwarded',lastSource==42)
expect('context normalized',lastContext and lastContext.name=='example_bench' and lastContext.amount==1 and lastContext.slot==7 and lastContext.metadata.quality==5 and lastContext.provider=='qbcore')
expect('usable registration does not consume item',removeCalls==0)

local dup,dupErr=U.Register('example_bench',handler,nil,'resource_a')
expect('same-owner duplicate rejected deterministically',dup==false and Errors.Is(dupErr,Codes.ALREADY_REGISTERED) and dupErr.context.sameOwner==true)
local collision,colErr=U.Register('example_bench',handler,nil,'resource_b')
expect('cross-resource collision rejected',collision==false and Errors.Is(colErr,Codes.ALREADY_REGISTERED) and colErr.context.sameOwner==false)

local removed=U.CleanupOwner('resource_a')
expect('resource stop cleanup removes owner handler',removed==1 and U.GetRegistration('example_bench')==nil)
local stale,staleErr=cb(42,{name='example_bench',slot=7,metadata={quality=5},provider='qbcore'})
expect('stale provider callback cannot invoke old handler',stale==false and Errors.Is(staleErr,Codes.REGISTRATION_NOT_FOUND) and calls==1)

local ok2,err2=U.Register('example_bench',handler,nil,'resource_b')
local cb2=registeredCallbacks.example_bench
expect('item can be re-registered after cleanup',ok2==true and err2==nil and type(cb2)=='function')
local oldAgain=cb(42,{name='example_bench',provider='qbcore'})
expect('old generation cannot invoke newer owner handler',oldAgain==false and calls==1)
local newUse=cb2(43,{name='example_bench',slot=3,metadata={},provider='qbcore'})
expect('new generation handler works',newUse==true and calls==2 and lastSource==43)
U.CleanupOwner('resource_b')

local badHandler,badHandlerErr=U.Register('bad_handler','not a function',nil,'resource_a')
expect('invalid handler canonical error',badHandler==false and Errors.Is(badHandlerErr,Codes.INVALID_HANDLER))
local badItem,badItemErr=U.Register('',handler,nil,'resource_a')
expect('invalid item canonical error',badItem==false and Errors.Is(badItemErr,Codes.INVALID_ITEM))

inventoryName='qs-inventory'; frameworkName='qbcore'
local unsupported,unsupportedErr=U.Register('unsupported_item',handler,nil,'resource_a')
expect('unsupported provider fails closed',unsupported==false and Errors.Is(unsupportedErr,Codes.UNSUPPORTED_FEATURE) and U.GetRegistration('unsupported_item')==nil)

print(('RESULT tests=%d pass=%d fail=%d'):format(total,total-failed,failed))
os.exit(failed==0 and 0 or 1)
