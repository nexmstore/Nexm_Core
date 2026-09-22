local Errors=NEXM_INTERNAL.Modules.Errors
local Codes=NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local adapter={metadata={name='esx',resource='es_extended',version=nil,critical=true,capabilities={metadata=false,metadataFilter=false,canCarry=true,getItems=true}}}
local initialized=false
local ESX
local function unsupported(feature) return Errors.Create(Codes.UNSUPPORTED_FEATURE,'ESX native inventory does not support this NEXM capability',{feature=feature,integration='esx'}) end
local function player(source) return ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(source) or nil end
function adapter.IsAvailable()
    if not (GetResourceState and GetResourceState('es_extended')=='started') then return false end
    local ok,obj=pcall(function() return exports['es_extended']:getSharedObject() end)
    if not ok or type(obj)~='table' then return false end
    if obj.GetConfig then
        local okCfg,custom=pcall(obj.GetConfig,'CustomInventory')
        if okCfg and custom then return false end
    end
    return true
end
function adapter.Initialize()
    if not adapter.IsAvailable() then return false,Errors.Create(Codes.INVENTORY_UNAVAILABLE,'ESX native inventory is unavailable or ESX uses a custom inventory') end
    local ok,obj=pcall(function() return exports['es_extended']:getSharedObject() end); if not ok or type(obj)~='table' then return false,Errors.Create(Codes.ADAPTER_ERROR,'Failed to acquire ESX for native inventory') end
    ESX=obj; initialized=true; adapter.metadata.version=GetResourceMetadata and GetResourceMetadata('es_extended','version',0) or adapter.metadata.version; return true,nil
end
function adapter.Shutdown() initialized=false; ESX=nil; return true,nil end
function adapter.GetState() return initialized and 'HEALTHY' or 'UNAVAILABLE' end
local function get(source) if not initialized then return nil,Errors.Create(Codes.INVENTORY_UNAVAILABLE,'ESX native inventory is unavailable') end local p=player(source); if not p then return nil,Errors.Create(Codes.PLAYER_NOT_FOUND,'ESX player was not found',{source=source}) end return p,nil end
function adapter.GetItemCount(source,item,metadata)
    if metadata~=nil then return nil,unsupported('inventory.metadataFilter') end
    local p,err=get(source); if not p then return nil,err end
    local data=p.getInventoryItem and p.getInventoryItem(item) or nil
    return tonumber(data and (data.count or data.amount)) or 0,nil
end
function adapter.HasItem(source,item,amount,metadata) if metadata~=nil then return false,unsupported('inventory.metadataFilter') end local count,err=adapter.GetItemCount(source,item,nil); if count==nil then return false,err end return count>=amount,nil end
function adapter.AddItem(source,item,amount,metadata)
    if metadata~=nil then return false,unsupported('inventory.metadata') end
    local p,err=get(source); if not p then return false,err end
    if not p.addInventoryItem then return false,Errors.Create(Codes.ADAPTER_ERROR,'ESX addInventoryItem is unavailable') end
    local before=select(1,adapter.GetItemCount(source,item,nil)); local ok,result=pcall(p.addInventoryItem,item,amount)
    if not ok or result==false then return false,Errors.Create(Codes.ADAPTER_ERROR,'ESX addInventoryItem failed',{item=item}) end
    local after=select(1,adapter.GetItemCount(source,item,nil)); if after~=before+amount then return false,Errors.Create(Codes.ADAPTER_ERROR,'ESX item addition could not be verified',{item=item,before=before,after=after,amount=amount}) end
    return true,nil
end
function adapter.RemoveItem(source,item,amount,metadata)
    if metadata~=nil then return false,unsupported('inventory.metadataFilter') end
    local p,err=get(source); if not p then return false,err end
    local before=select(1,adapter.GetItemCount(source,item,nil)); if before<amount then return false,'not_enough_items' end
    if not p.removeInventoryItem then return false,Errors.Create(Codes.ADAPTER_ERROR,'ESX removeInventoryItem is unavailable') end
    local ok,result=pcall(p.removeInventoryItem,item,amount); if not ok or result==false then return false,Errors.Create(Codes.ADAPTER_ERROR,'ESX removeInventoryItem failed',{item=item}) end
    local after=select(1,adapter.GetItemCount(source,item,nil)); if after~=before-amount then return false,Errors.Create(Codes.ADAPTER_ERROR,'ESX item removal could not be verified',{item=item,before=before,after=after,amount=amount}) end
    return true,nil
end
function adapter.CanCarry(source,item,amount,metadata)
    if metadata~=nil then return false,unsupported('inventory.metadata') end
    local p,err=get(source); if not p then return false,err end
    if not p.canCarryItem then return false,unsupported('inventory.canCarry') end
    local ok,result=pcall(p.canCarryItem,item,amount); if not ok then return false,Errors.Create(Codes.ADAPTER_ERROR,'ESX canCarryItem failed',{item=item}) end
    return result==true,nil
end
function adapter.GetItems(source) local p,err=get(source); if not p then return nil,err end local ok,result=pcall(p.getInventory); if not ok then return nil,Errors.Create(Codes.ADAPTER_ERROR,'ESX getInventory failed') end local out={}; for slot,v in pairs(result or {}) do if v and v.name then out[#out+1]={name=v.name,count=tonumber(v.count or v.amount) or 0,slot=v.slot or slot,metadata=nil} end end return out,nil end
NEXM_INTERNAL.Adapters.Inventory.esx=adapter
