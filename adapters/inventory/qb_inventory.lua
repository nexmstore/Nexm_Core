local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local adapter = {
    metadata = {
        name = 'qb-inventory', resource = 'qb-inventory', version = nil, critical = true,
        capabilities = { metadata = true, metadataFilter = false, canCarry = true, getItems = true }
    }
}
local initialized=false
local qb
local function unavailable() return Errors.Create(Codes.INVENTORY_UNAVAILABLE,'qb-inventory is unavailable',{integration='qb-inventory'}) end
local function unsupportedFilter() return Errors.Create(Codes.UNSUPPORTED_FEATURE,'qb-inventory adapter does not guarantee metadata-filtered query/removal',{feature='inventory.metadataFilter'}) end
function adapter.IsAvailable() return GetResourceState and GetResourceState('qb-inventory')=='started' end
function adapter.Initialize()
    if not adapter.IsAvailable() then return false,unavailable() end
    qb=exports['qb-inventory']; if not qb then return false,Errors.Create(Codes.ADAPTER_ERROR,'qb-inventory exports are unavailable') end
    initialized=true; adapter.metadata.version=GetResourceMetadata and GetResourceMetadata('qb-inventory','version',0) or adapter.metadata.version
    return true,nil
end
function adapter.Shutdown() initialized=false; qb=nil; return true,nil end
function adapter.GetState() return initialized and 'HEALTHY' or 'UNAVAILABLE' end
local function ready() if not initialized or not qb then return false,unavailable() end return true,nil end
function adapter.GetItemCount(source,item,metadata)
    if metadata~=nil then return nil,unsupportedFilter() end
    local ok,err=ready(); if not ok then return nil,err end
    local success,value=pcall(function() return qb:GetItemCount(source,item) end)
    if not success then return nil,Errors.Create(Codes.ADAPTER_ERROR,'qb-inventory GetItemCount failed',{item=item}) end
    return tonumber(value) or 0,nil
end
function adapter.HasItem(source,item,amount,metadata)
    if metadata~=nil then return false,unsupportedFilter() end
    local count,err=adapter.GetItemCount(source,item,nil); if count==nil then return false,err end
    return count>=amount,nil
end
function adapter.AddItem(source,item,amount,metadata)
    local ok,err=ready(); if not ok then return false,err end
    local success,result=pcall(function() return qb:AddItem(source,item,amount,false,metadata or false,'nexm_core') end)
    if not success then return false,Errors.Create(Codes.ADAPTER_ERROR,'qb-inventory AddItem failed',{item=item}) end
    return result==true, result==true and nil or 'add_failed'
end
function adapter.RemoveItem(source,item,amount,metadata)
    if metadata~=nil then return false,unsupportedFilter() end
    local ok,err=ready(); if not ok then return false,err end
    local success,result=pcall(function() return qb:RemoveItem(source,item,amount,false,'nexm_core') end)
    if not success then return false,Errors.Create(Codes.ADAPTER_ERROR,'qb-inventory RemoveItem failed',{item=item}) end
    return result==true, result==true and nil or 'not_enough_items'
end
function adapter.CanCarry(source,item,amount,metadata)
    local ok,err=ready(); if not ok then return false,err end
    local success,result,reason=pcall(function() return qb:CanAddItem(source,item,amount) end)
    if not success then return false,Errors.Create(Codes.ADAPTER_ERROR,'qb-inventory CanAddItem failed',{item=item}) end
    if result==true then return true,nil end
    if reason=='weight' or reason=='slots' then return false,nil end
    if reason==nil then return false,Errors.Create(Codes.INVALID_ITEM,'qb-inventory could not resolve the item definition',{item=item}) end
    return false,Errors.Create(Codes.INTEGRATION_ERROR,'qb-inventory CanAddItem returned an unknown failure',{item=item,response=tostring(reason)})
end
function adapter.GetItems(source)
    local ok,err=ready(); if not ok then return nil,err end
    local success,p=pcall(function() return exports['qb-core']:GetPlayer(source) end)
    if not success or not p then return nil,Errors.Create(Codes.PLAYER_NOT_FOUND,'Player was not found by qb-inventory',{source=source}) end
    local out={}; for slot,v in pairs((p.PlayerData and p.PlayerData.items) or {}) do if v and v.name then out[#out+1]={name=v.name,count=tonumber(v.amount or v.count) or 0,slot=v.slot or slot,metadata=v.info or v.metadata} end end
    return out,nil
end
NEXM_INTERNAL.Adapters.Inventory.qb_inventory = adapter
