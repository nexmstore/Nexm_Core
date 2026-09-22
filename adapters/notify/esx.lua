local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local adapter = {
    metadata = {
        name='esx', resource='es_extended', version='1.15.2',
        capabilities={ advanced=false }, critical=false
    }
}
local function available()
    return GetResourceState and GetResourceState('es_extended') == 'started' and GetResourceState('esx_notify') == 'started'
end
function adapter.IsAvailable() return available() end
function adapter.Initialize() return available() and true or false, available() and nil or Errors.Create(Codes.NOTIFY_UNAVAILABLE,'ESX notify is unavailable') end
function adapter.Shutdown() return true,nil end
function adapter.GetState() return available() and 'HEALTHY' or 'UNAVAILABLE' end
function adapter.Send(message, notifyType, duration, options)
    if not available() then return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE,'ESX notify is unavailable') end
    local ok, err = pcall(function()
        local ESX = exports['es_extended']:getSharedObject()
        if not ESX or type(ESX.ShowNotification) ~= 'function' then error('ESX.ShowNotification missing') end
        ESX.ShowNotification(message, notifyType, duration, options and options.title or nil, options and options.position or nil)
    end)
    if not ok then return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE,'ESX notify failed',{detail=tostring(err)}) end
    return true,nil
end
NEXM_INTERNAL.Adapters.Notify.esx = adapter
