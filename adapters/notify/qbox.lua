local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local adapter = {
    metadata = {
        name='qbox', resource='qbx_core', version='1.24.0',
        capabilities={ advanced=true }, critical=false
    }
}
function adapter.IsAvailable() return GetResourceState and GetResourceState('qbx_core') == 'started' end
function adapter.Initialize() return adapter.IsAvailable() and true or false, adapter.IsAvailable() and nil or Errors.Create(Codes.NOTIFY_UNAVAILABLE,'Qbox notify is unavailable') end
function adapter.Shutdown() return true,nil end
function adapter.GetState() return adapter.IsAvailable() and 'HEALTHY' or 'UNAVAILABLE' end
local map = { info='inform', success='success', warning='warning', error='error' }
function adapter.Send(message, notifyType, duration, options)
    if not adapter.IsAvailable() then return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE,'Qbox notify is unavailable') end
    local a = options and options.adapter or {}
    local ok, err = pcall(function()
        exports['qbx_core']:Notify(message, map[notifyType] or 'inform', duration,
            options and options.title or nil, options and options.position or nil,
            a and a.style or nil, a and a.icon or nil, a and a.iconColor or nil)
    end)
    if not ok then return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE,'Qbox notify failed',{detail=tostring(err)}) end
    return true,nil
end
NEXM_INTERNAL.Adapters.Notify.qbox = adapter
