local Contract=NEXM_INTERNAL.Modules.InventoryContract
local Integrations=NEXM_INTERNAL.Managers.Integrations
local Errors=NEXM_INTERNAL.Modules.Errors
local Logger=NEXM_INTERNAL.Modules.Logger
local State=NEXM_INTERNAL.Modules.State
local Constants=NEXM_INTERNAL.Modules.Constants
local Codes,Health=Constants.ERROR_CODES,Constants.HEALTH
local Manager={}
local adapters={}
local selectedName,selectedAdapter=nil,nil
local monitorInstalled=false
local builtinsRegistered=false

local function notify(state)
    local Resources=NEXM_INTERNAL.Managers.Resources
    if Resources and Resources.NotifyComponentChanged then Resources.NotifyComponentChanged('inventory',state) end
end
local function registerAdapter(adapter)
    local ok,err=Contract.Validate(adapter); if not ok then return false,err end
    local available=false; local callOk,result=pcall(adapter.IsAvailable); if callOk and result==true then available=true end
    local okReg,regErr=Integrations.RegisterInternal({category='inventory',name=adapter.metadata.name,version=adapter.metadata.version or '0.0.0',capabilities=adapter.metadata.capabilities,critical=true,state=available and 'AVAILABLE' or 'UNAVAILABLE',adapter=adapter},'nexm_core')
    if not okReg then return false,regErr end
    adapters[adapter.metadata.name]=adapter
    return true,nil
end
function Manager.RegisterBuiltinAdapters()
    if builtinsRegistered then return true,nil end
    adapters={}
    for _,adapter in pairs(NEXM_INTERNAL.Adapters.Inventory or {}) do local ok,err=registerAdapter(adapter); if not ok then return false,err end end
    local custom=NEXM_CUSTOM_INVENTORY_ADAPTER
    if type(custom)=='table' and custom.enabled==true then local ok,err=registerAdapter(custom); if not ok then return false,err end end
    builtinsRegistered=true
    return true,nil
end
function Manager.GetAdapter(name) return adapters[name] end
function Manager.GetName() return selectedName end
function Manager.GetSelected() return selectedAdapter end
function Manager.IsHealthy() local c=State.GetComponent('inventory'); return selectedAdapter~=nil and c and c.state==Health.HEALTHY end
function Manager.RequireHealthy()
    local component=State.GetComponent('inventory')
    if component and component.state==Health.DISABLED then return nil,Errors.Create(Codes.INVENTORY_DISABLED,'Inventory integration is intentionally disabled') end
    if not Manager.IsHealthy() then local err=Errors.Create(Codes.INVENTORY_UNAVAILABLE,'Selected inventory integration is unavailable',{selected=selectedName}); Logger.Infrastructure(err,'inventory','nexm_core'); return nil,err end
    return selectedAdapter,nil
end
local function setIntegrationState(name,state) if name and Integrations.SetStateInternal then Integrations.SetStateInternal('inventory',name,state,'nexm_core') end end
local function availableCount()
    local count=0
    for _,adapter in pairs(adapters) do local ok,v=pcall(adapter.IsAvailable); if ok and v==true then count=count+1 end end
    return count
end
function Manager.InitializeSelected()
    local ok,err=Manager.RegisterBuiltinAdapters(); if not ok then State.SetComponent('inventory',Health.FAILED); notify(Health.FAILED); return false,err end
    if Config.Inventory=='none' then
        selectedName,selectedAdapter=nil,nil
        State.SetComponent('inventory',Health.DISABLED,{configured='none'})
        notify(Health.DISABLED)
        return true,nil
    end
    if Config.Inventory=='auto' and availableCount()==0 then
        selectedName,selectedAdapter=nil,nil
        State.SetComponent('inventory',Health.UNAVAILABLE,{configured='auto',reason='no_supported_inventory'})
        Logger.Warn('No supported inventory integration detected; Core will remain READY and inventory-dependent products will fail requirements',{},'nexm_core')
        notify(Health.UNAVAILABLE)
        return true,nil
    end
    local priority=(Config.Integrations and Config.Integrations.priorities and Config.Integrations.priorities.inventory) or {}
    local selectedOk,nameOrErr=Integrations.Select('inventory',Config.Inventory,priority)
    if not selectedOk then State.SetComponent('inventory',Health.UNAVAILABLE,{error=nameOrErr}); notify(Health.UNAVAILABLE); return false,nameOrErr end
    local name=nameOrErr; local adapter=adapters[name]
    if not adapter then local e=Errors.Create(Codes.INVALID_INVENTORY_ADAPTER,'Selected inventory adapter is not registered',{selected=name}); State.SetComponent('inventory',Health.FAILED); notify(Health.FAILED); return false,e end
    local valid,validErr=Contract.Validate(adapter); if not valid then State.SetComponent('inventory',Health.FAILED); notify(Health.FAILED); return false,validErr end
    local callOk,result,initErr=pcall(adapter.Initialize)
    if not callOk or result~=true then local e=Errors.Is(initErr) and initErr or Errors.Create(Codes.INTEGRATION_ERROR,'Inventory adapter initialization failed',{integration=name}); Logger.Infrastructure(e,'inventory','nexm_core'); State.SetComponent('inventory',Health.FAILED); notify(Health.FAILED); return false,e end
    selectedName,selectedAdapter=name,adapter
    setIntegrationState(name,'HEALTHY')
    State.SetComponent('inventory',Health.HEALTHY,{name=name,resource=adapter.metadata.resource,capabilities=adapter.metadata.capabilities})
    notify(Health.HEALTHY)
    return true,nil
end
local function degrade()
    if selectedAdapter then pcall(selectedAdapter.Shutdown) end
    setIntegrationState(selectedName,'UNAVAILABLE')
    State.SetComponent('inventory',Health.UNAVAILABLE,{name=selectedName})
    notify(Health.UNAVAILABLE)
end
local function recover()
    if not selectedAdapter or not selectedName then return end
    local valid,err=Contract.Validate(selectedAdapter); if not valid then Logger.Infrastructure(err,'inventory:recovery','nexm_core'); State.SetComponent('inventory',Health.FAILED); notify(Health.FAILED); return end
    local availableOk,available=pcall(selectedAdapter.IsAvailable); if not availableOk or not available then return end
    local ok,result,initErr=pcall(selectedAdapter.Initialize); if not ok or result~=true then Logger.Infrastructure(Errors.Is(initErr) and initErr or Errors.Create(Codes.INTEGRATION_ERROR,'Inventory recovery failed',{integration=selectedName}),'inventory:recovery','nexm_core'); return end
    setIntegrationState(selectedName,'HEALTHY')
    State.SetComponent('inventory',Health.HEALTHY,{name=selectedName,resource=selectedAdapter.metadata.resource,capabilities=selectedAdapter.metadata.capabilities})
    notify(Health.HEALTHY)
end
local function refreshUnselected(resource,state)
    if Config.Inventory=='none' or selectedName then return end
    for name,adapter in pairs(adapters) do
        if adapter.metadata.resource==resource then setIntegrationState(name,state) end
    end
    if state=='AVAILABLE' then
        local ok,err=Manager.InitializeSelected()
        if not ok then Logger.Warn('Inventory became available but automatic selection was not possible',{error=err and err.code},'nexm_core') end
    end
end
function Manager.InstallResourceMonitoring()
    if monitorInstalled then return end; monitorInstalled=true
    AddEventHandler('onResourceStop',function(resource)
        if selectedAdapter and resource==selectedAdapter.metadata.resource then degrade() else refreshUnselected(resource,'UNAVAILABLE') end
    end)
    AddEventHandler('onResourceStart',function(resource)
        if selectedAdapter and resource==selectedAdapter.metadata.resource then recover() else refreshUnselected(resource,'AVAILABLE') end
    end)
end
NEXM_INTERNAL.Managers.Inventory=Manager
