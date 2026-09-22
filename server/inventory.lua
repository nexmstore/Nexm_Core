local Errors=NEXM_INTERNAL.Modules.Errors
local Validation=NEXM_INTERNAL.Modules.Validation
local Logger=NEXM_INTERNAL.Modules.Logger
local Guard=NEXM_INTERNAL.Modules.SessionGuard
local Manager=NEXM_INTERNAL.Managers.Inventory
local Codes=NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Inventory={}
local infra={ [Codes.INVENTORY_UNAVAILABLE]=true,[Codes.FRAMEWORK_UNAVAILABLE]=true,[Codes.ADAPTER_ERROR]=true,[Codes.INTEGRATION_ERROR]=true }
local function copy(v,seen) if type(v)~='table' then return v end seen=seen or {}; if seen[v] then return nil end; seen[v]=true; local o={}; for k,x in pairs(v) do o[copy(k,seen)]=copy(x,seen) end; seen[v]=nil; return o end
local function log(err) if err and infra[err.code] then Logger.Infrastructure(err,'inventory','nexm_core') end end
local function validateItem(item)
    local ok,err=Validation.String(item,{name='item',nonEmpty=true,min=1,max=(Config.Security.maxItemNameLength or 128)}); if not ok then return nil,Errors.Create(Codes.INVALID_ITEM,'Invalid item name',{actualType=type(item)}) end
    if item:find('[%c]') then return nil,Errors.Create(Codes.INVALID_ITEM,'Item name contains control characters') end
    return item,nil
end
local function validateAmount(amount)
    local ok,err=Validation.Integer(amount,{name='amount',min=1,max=(Config.Security.MaxItemTransaction or 1000)}); if not ok then return nil,Errors.Create(Codes.INVALID_AMOUNT,'Invalid item amount',{actualType=type(amount),max=Config.Security.MaxItemTransaction}) end
    return amount,nil
end
local function validateMetadata(metadata)
    if metadata==nil then return nil,nil end
    local ok,err=Validation.SerializableTable(metadata,{name='metadata',required=false}); if not ok then return nil,err end
    return copy(metadata),nil
end
local function begin(source,item,amount,metadata,mode)
    local sourceOk,sourceErr=Validation.Source(source); if not sourceOk then return nil,nil,nil,nil,sourceErr end
    local i,ie=validateItem(item); if not i then return nil,nil,nil,nil,ie end
    local a,ae=validateAmount(amount); if not a then return nil,nil,nil,nil,ae end
    local m,me=validateMetadata(metadata); if me then return nil,nil,nil,nil,me end
    local adapter,invErr=Manager.RequireHealthy(); if not adapter then return nil,nil,nil,nil,invErr end
    local ctx,ce=Guard.Capture(source); if not ctx then log(ce); return nil,nil,nil,nil,ce end
    local caps=adapter.metadata.capabilities
    if metadata~=nil then
        if mode=='add' and caps.metadata~=true then return nil,nil,nil,nil,Errors.Create(Codes.UNSUPPORTED_FEATURE,'Inventory cannot create metadata items',{feature='inventory.metadata'}) end
        if (mode=='query' or mode=='remove') and caps.metadataFilter~=true then return nil,nil,nil,nil,Errors.Create(Codes.UNSUPPORTED_FEATURE,'Inventory cannot safely filter metadata variants',{feature='inventory.metadataFilter'}) end
        if mode=='carry' and caps.metadata~=true then return nil,nil,nil,nil,Errors.Create(Codes.UNSUPPORTED_FEATURE,'Inventory cannot evaluate metadata-aware item capacity',{feature='inventory.metadata'}) end
    end
    return ctx,adapter,i,a,nil,m
end
local function mapFailure(raw,operation,item)
    if Errors.Is(raw) then return raw end
    local code=tostring(raw or '')
    if code=='invalid_item' then return Errors.Create(Codes.INVALID_ITEM,'Inventory item does not exist',{item=item}) end
    if code=='inventory_full' or code=='weight' or code=='slots' or code=='add_failed' then return Errors.Create(Codes.NO_SPACE,'Inventory cannot accept the requested item',{item=item}) end
    if code=='not_enough_items' or code=='remove_failed' then return Errors.Create(Codes.INSUFFICIENT_ITEMS,'Inventory does not contain enough requested items',{item=item}) end
    if code=='invalid_inventory' then return Errors.Create(Codes.INVENTORY_UNAVAILABLE,'Player inventory is unavailable',{item=item}) end
    return Errors.Create(Codes.INTEGRATION_ERROR,'Inventory adapter operation failed',{operation=operation,item=item,response=code})
end
function Inventory.GetItemCount(source,item,metadata)
    local ctx,adapter,i,a,err,m=begin(source,item,1,metadata,'query'); if not ctx then return nil,err end
    local ok,value,adapterErr=pcall(adapter.GetItemCount,source,i,m); if not ok then local e=Errors.Create(Codes.ADAPTER_ERROR,'Inventory GetItemCount threw',{item=i}); log(e); return nil,e end
    local still,stale=Guard.Validate(ctx); if not still then return nil,stale end
    if value==nil then local e=mapFailure(adapterErr,'GetItemCount',i); log(e); return nil,e end
    if type(value)~='number' or value<0 or value%1~=0 then local e=Errors.Create(Codes.ADAPTER_ERROR,'Inventory returned invalid item count',{item=i}); log(e); return nil,e end
    return value,nil
end
function Inventory.HasItem(source,item,amount,metadata)
    local valid,ae=validateAmount(amount); if not valid then return false,ae end
    local count,err=Inventory.GetItemCount(source,item,metadata); if count==nil then return false,err end
    return count>=valid,nil
end
function Inventory.CanCarry(source,item,amount,metadata)
    local ctx,adapter,i,a,err,m=begin(source,item,amount,metadata,'carry'); if not ctx then return false,err end
    if adapter.metadata.capabilities.canCarry~=true then return false,Errors.Create(Codes.UNSUPPORTED_FEATURE,'Inventory does not support capacity checks',{feature='inventory.canCarry'}) end
    local ok,result,adapterErr=pcall(adapter.CanCarry,source,i,a,m); if not ok then local e=Errors.Create(Codes.ADAPTER_ERROR,'Inventory CanCarry threw',{item=i}); log(e); return false,e end
    local still,stale=Guard.Validate(ctx); if not still then return false,stale end
    if adapterErr then local e=mapFailure(adapterErr,'CanCarry',i); if infra[e.code] then log(e) end; return false,e end
    return result==true,nil
end
function Inventory.AddItem(source,item,amount,metadata)
    local ctx,adapter,i,a,err,m=begin(source,item,amount,metadata,'add'); if not ctx then return false,err end
    if adapter.metadata.capabilities.canCarry then local can,carryErr=Inventory.CanCarry(source,i,a,m); if carryErr then return false,carryErr end; if not can then return false,Errors.Create(Codes.NO_SPACE,'Inventory cannot carry requested item',{item=i,amount=a}) end end
    local still,stale=Guard.Validate(ctx); if not still then return false,stale end
    local ok,result,adapterErr=pcall(adapter.AddItem,source,i,a,m); if not ok then local e=Errors.Create(Codes.ADAPTER_ERROR,'Inventory AddItem threw',{item=i}); log(e); return false,e end
    still,stale=Guard.Validate(ctx); if not still then return false,stale end
    if result~=true then local e=mapFailure(adapterErr,'AddItem',i); if infra[e.code] then log(e) end; return false,e end
    return true,nil
end
function Inventory.RemoveItem(source,item,amount,metadata)
    local ctx,adapter,i,a,err,m=begin(source,item,amount,metadata,'remove'); if not ctx then return false,err end
    local count,countErr=Inventory.GetItemCount(source,i,m); if count==nil then return false,countErr end
    if count<a then return false,Errors.Create(Codes.INSUFFICIENT_ITEMS,'Inventory does not contain enough requested items',{item=i,available=count,required=a}) end
    local still,stale=Guard.Validate(ctx); if not still then return false,stale end
    local ok,result,adapterErr=pcall(adapter.RemoveItem,source,i,a,m); if not ok then local e=Errors.Create(Codes.ADAPTER_ERROR,'Inventory RemoveItem threw',{item=i}); log(e); return false,e end
    still,stale=Guard.Validate(ctx); if not still then return false,stale end
    if result~=true then local e=mapFailure(adapterErr,'RemoveItem',i); if infra[e.code] then log(e) end; return false,e end
    return true,nil
end
function Inventory.GetItems(source)
    local sourceOk,sourceErr=Validation.Source(source); if not sourceOk then return nil,sourceErr end
    local adapter,err=Manager.RequireHealthy(); if not adapter then return nil,err end
    local ctx,ce=Guard.Capture(source); if not ctx then log(ce); return nil,ce end
    if adapter.metadata.capabilities.getItems~=true or type(adapter.GetItems)~='function' then return nil,Errors.Create(Codes.UNSUPPORTED_FEATURE,'Inventory does not provide normalized item listing',{feature='inventory.getItems'}) end
    local ok,result,adapterErr=pcall(adapter.GetItems,source); if not ok then local e=Errors.Create(Codes.ADAPTER_ERROR,'Inventory GetItems threw'); log(e); return nil,e end
    local still,stale=Guard.Validate(ctx); if not still then return nil,stale end
    if result==nil then local e=mapFailure(adapterErr,'GetItems','*'); log(e); return nil,e end
    return copy(result),nil
end
NEXM_INTERNAL.Modules.Inventory=Inventory
