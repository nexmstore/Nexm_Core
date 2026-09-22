local Errors=NEXM_INTERNAL.Modules.Errors
local Codes=NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local adapter={metadata={name='qs-inventory',resource='qs-inventory',version=nil,critical=true,capabilities={metadata=true,metadataFilter=true,canCarry=true,getItems=true}}}
local initialized=false
local qs
local function unavailable() return Errors.Create(Codes.INVENTORY_UNAVAILABLE,'qs-inventory is unavailable',{integration='qs-inventory'}) end
local function deepEqualSubset(actual,expected)
    if type(expected)~='table' then return actual==expected end
    if type(actual)~='table' then return false end
    for k,v in pairs(expected) do if type(v)=='table' then if not deepEqualSubset(actual[k],v) then return false end elseif actual[k]~=v then return false end end
    return true
end
function adapter.IsAvailable() return GetResourceState and GetResourceState('qs-inventory')=='started' end
function adapter.Initialize() if not adapter.IsAvailable() then return false,unavailable() end qs=exports['qs-inventory']; if not qs then return false,Errors.Create(Codes.ADAPTER_ERROR,'qs-inventory exports unavailable') end initialized=true; adapter.metadata.version=GetResourceMetadata and GetResourceMetadata('qs-inventory','version',0) or 'documented-api'; return true,nil end
function adapter.Shutdown() initialized=false; qs=nil; return true,nil end
function adapter.GetState() return initialized and 'HEALTHY' or 'UNAVAILABLE' end
local function ready() if not initialized or not qs then return false,unavailable() end return true,nil end
function adapter.GetItems(source) local ok,err=ready(); if not ok then return nil,err end local success,result=pcall(function() return qs:GetInventory(source) end); if not success then return nil,Errors.Create(Codes.ADAPTER_ERROR,'qs-inventory GetInventory failed') end local out={}; for slot,v in pairs(result or {}) do if v and v.name then out[#out+1]={name=v.name,count=tonumber(v.amount or v.count) or 0,slot=v.slot or slot,metadata=v.info or v.metadata} end end return out,nil end
function adapter.GetItemCount(source,item,metadata)
    local items,err=adapter.GetItems(source); if not items then return nil,err end
    local count=0; for _,entry in pairs(items) do if entry and entry.name==item and (metadata==nil or deepEqualSubset(entry.metadata or {},metadata)) then count=count+(tonumber(entry.count) or 0) end end
    return count,nil
end
function adapter.HasItem(source,item,amount,metadata) local c,e=adapter.GetItemCount(source,item,metadata); if c==nil then return false,e end return c>=amount,nil end
function adapter.AddItem(source,item,amount,metadata) local ok,err=ready(); if not ok then return false,err end local success,result=pcall(function() return qs:AddItem(source,item,amount,nil,metadata) end); if not success then return false,Errors.Create(Codes.ADAPTER_ERROR,'qs-inventory AddItem failed',{item=item}) end return result==true,result==true and nil or 'add_failed' end
function adapter.RemoveItem(source,item,amount,metadata) local ok,err=ready(); if not ok then return false,err end local count,countErr=adapter.GetItemCount(source,item,metadata); if count==nil then return false,countErr end; if count<amount then return false,'not_enough_items' end local success,result=pcall(function() return qs:RemoveItem(source,item,amount,nil,metadata) end); if not success then return false,Errors.Create(Codes.ADAPTER_ERROR,'qs-inventory RemoveItem failed',{item=item}) end return result==true,result==true and nil or 'remove_failed' end
function adapter.CanCarry(source,item,amount,metadata) local ok,err=ready(); if not ok then return false,err end local success,result=pcall(function() return qs:CanCarryItem(source,item,amount) end); if not success then return false,Errors.Create(Codes.ADAPTER_ERROR,'qs-inventory CanCarryItem failed',{item=item}) end return result==true,nil end
NEXM_INTERNAL.Adapters.Inventory.qs_inventory=adapter
