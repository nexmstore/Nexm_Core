local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local adapter = {
    metadata = {
        name = 'ox_inventory', resource = 'ox_inventory', version = nil, critical = true,
        capabilities = { metadata = true, metadataFilter = true, canCarry = true, getItems = true, usableItems = true }
    }
}
local initialized = false
local ox
local function unavailable() return Errors.Create(Codes.INVENTORY_UNAVAILABLE, 'ox_inventory is unavailable', { integration = 'ox_inventory' }) end
function adapter.IsAvailable() return GetResourceState and GetResourceState('ox_inventory') == 'started' end
function adapter.Initialize()
    if not adapter.IsAvailable() then return false, unavailable() end
    ox = exports['ox_inventory']
    if not ox then return false, Errors.Create(Codes.ADAPTER_ERROR, 'ox_inventory exports are unavailable') end
    initialized = true
    adapter.metadata.version = GetResourceMetadata and GetResourceMetadata('ox_inventory', 'version', 0) or adapter.metadata.version
    return true, nil
end
function adapter.Shutdown() initialized=false; ox=nil; return true,nil end
function adapter.GetState() return initialized and 'HEALTHY' or 'UNAVAILABLE' end
local function ready() if not initialized or not ox then return false, unavailable() end return true,nil end
function adapter.GetItemCount(source,item,metadata)
    local ok,err=ready(); if not ok then return nil,err end
    local success,value=pcall(function() return ox:GetItemCount(source,item,metadata,true) end)
    if not success then return nil,Errors.Create(Codes.ADAPTER_ERROR,'ox_inventory GetItemCount failed',{item=item}) end
    return tonumber(value) or 0,nil
end
function adapter.HasItem(source,item,amount,metadata)
    local count,err=adapter.GetItemCount(source,item,metadata); if count==nil then return false,err end
    return count>=amount,nil
end
function adapter.AddItem(source,item,amount,metadata)
    local ok,err=ready(); if not ok then return false,err end
    local success,result,response=pcall(function() return ox:AddItem(source,item,amount,metadata) end)
    if not success then return false,Errors.Create(Codes.ADAPTER_ERROR,'ox_inventory AddItem failed',{item=item}) end
    if result==true then return true,nil end
    return false,response or result
end
function adapter.RemoveItem(source,item,amount,metadata)
    local ok,err=ready(); if not ok then return false,err end
    local success,result,response=pcall(function() return ox:RemoveItem(source,item,amount,metadata,nil,false,true) end)
    if not success then return false,Errors.Create(Codes.ADAPTER_ERROR,'ox_inventory RemoveItem failed',{item=item}) end
    if result==true then return true,nil end
    return false,response or result
end
function adapter.CanCarry(source,item,amount,metadata)
    local ok,err=ready(); if not ok then return false,err end
    local success,result=pcall(function() return ox:CanCarryItem(source,item,amount,metadata) end)
    if not success then return false,Errors.Create(Codes.ADAPTER_ERROR,'ox_inventory CanCarryItem failed',{item=item}) end
    return result==true,nil
end
function adapter.GetItems(source)
    local ok,err=ready(); if not ok then return nil,err end
    local success,result=pcall(function() return ox:GetInventoryItems(source) end)
    if not success then return nil,Errors.Create(Codes.ADAPTER_ERROR,'ox_inventory GetInventoryItems failed') end
    local out={}; for slot,v in pairs(result or {}) do if v and v.name then out[#out+1]={name=v.name,count=tonumber(v.count or v.amount) or 0,slot=v.slot or slot,metadata=v.metadata} end end
    return out,nil
end

function adapter.RegisterUsableItem(itemName)
    local ok, err = ready(); if not ok then return false, err end
    local success, definition = pcall(function() return ox:Items(itemName) end)
    if not success then
        return false, Errors.Create(Codes.INTEGRATION_ERROR, 'ox_inventory item definition lookup failed', { item = itemName })
    end
    if type(definition) ~= 'table' then
        return false, Errors.Create(Codes.INVALID_ITEM, 'ox_inventory item is not defined', { item = itemName })
    end
    if definition.consume ~= 0 then
        return false, Errors.Create(Codes.INTEGRATION_ERROR,
            'ox_inventory usable items registered through NEXM Core must set consume = 0', {
                item = itemName, required = 'consume=0', actual = definition.consume
            })
    end
    local serverDefinition = definition.server
    local exportName = type(serverDefinition) == 'table' and serverDefinition.export or nil
    if exportName ~= 'nexm_core.UseRegisteredItem' then
        return false, Errors.Create(Codes.INTEGRATION_ERROR,
            'ox_inventory item must use the NEXM Core usable-item server export', {
                item = itemName,
                required = 'server.export=nexm_core.UseRegisteredItem',
                actual = exportName
            })
    end
    return true, nil
end

-- Stable ox_inventory server.export target. ox_inventory calls server exports from
-- its server-side item pipeline with (event, item, inventory, slot, data).
-- No client-controlled item/source is trusted here; the invoking resource and
-- authoritative ox_inventory payload are validated before dispatch.
exports('UseRegisteredItem', function(event, item, inventory, slot, data)
    if event ~= 'usingItem' then return nil end
    if GetInvokingResource and GetInvokingResource() ~= 'ox_inventory' then
        return false
    end
    if type(item) ~= 'table' or type(item.name) ~= 'string' or type(inventory) ~= 'table' or type(inventory.player) ~= 'table' then
        return false
    end
    -- ox_inventory player inventories use the authoritative server id as inventory.id.
    -- Do not accept a source value from item metadata, callback data, or the client.
    local source = tonumber(inventory.id)
    local slotNumber = tonumber(slot)
    local slotData = slotNumber and type(inventory.items) == 'table' and inventory.items[slotNumber] or nil
    if not source or type(slotData) ~= 'table' or slotData.name ~= item.name or (tonumber(slotData.count) or 0) < 1 then
        return false
    end
    local context = {
        name = item.name,
        amount = 1,
        slot = slotNumber,
        metadata = type(slotData.metadata) == 'table' and slotData.metadata or nil,
        provider = 'ox_inventory'
    }
    local registry = NEXM_INTERNAL.Modules.UsableItems
    if not registry or type(registry.DispatchProviderUse) ~= 'function' then return false end
    local ok = registry.DispatchProviderUse(item.name, source, context, nil, 'ox_inventory')
    if ok ~= true then return false end
    return nil
end)

NEXM_INTERNAL.Adapters.Inventory.ox_inventory = adapter
