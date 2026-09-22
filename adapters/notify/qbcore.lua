local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local adapter = {
    metadata = {
        name='qbcore', resource='qb-core', version='1.3.0',
        capabilities={ advanced=false }, critical=false
    }
}
local function sameResourceAlias()
    if not GetResourceState or GetResourceState('qb-core') ~= 'started' or GetResourceState('qbx_core') ~= 'started' then return false end
    if GetResourcePath then
        local okA,a=pcall(GetResourcePath,'qb-core'); local okB,b=pcall(GetResourcePath,'qbx_core')
        if okA and okB and type(a)=='string' and a~='' and a==b then return true end
    end
    return false
end
local function available()
    return GetResourceState and GetResourceState('qb-core') == 'started' and not sameResourceAlias()
end
function adapter.IsAvailable() return available() end
function adapter.Initialize() return available() and true or false, available() and nil or Errors.Create(Codes.NOTIFY_UNAVAILABLE,'QBCore notify is unavailable') end
function adapter.Shutdown() return true,nil end
function adapter.GetState() return available() and 'HEALTHY' or 'UNAVAILABLE' end
local map = { info='primary', success='success', warning='warning', error='error' }
function adapter.Send(message, notifyType, duration, options)
    if not available() then return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE,'QBCore notify is unavailable') end
    local ok, err = pcall(function()
        local QB = exports['qb-core']:GetCoreObject()
        if not QB or not QB.Functions or type(QB.Functions.Notify) ~= 'function' then error('QBCore.Functions.Notify missing') end
        QB.Functions.Notify(message, map[notifyType] or 'primary', duration, options and options.adapter and options.adapter.icon or nil)
    end)
    if not ok then return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE,'QBCore notify failed',{detail=tostring(err)}) end
    return true,nil
end
NEXM_INTERNAL.Adapters.Notify.qbcore = adapter
