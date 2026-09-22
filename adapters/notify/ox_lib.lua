local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local adapter = {
    metadata = {
        name='ox_lib', resource='ox_lib', version='3.39.0',
        capabilities={ advanced=true }, critical=false
    }
}
function adapter.IsAvailable() return GetResourceState and GetResourceState('ox_lib') == 'started' end
function adapter.Initialize() return adapter.IsAvailable() and true or false, adapter.IsAvailable() and nil or Errors.Create(Codes.NOTIFY_UNAVAILABLE,'ox_lib is unavailable') end
function adapter.Shutdown() return true,nil end
function adapter.GetState() return adapter.IsAvailable() and 'HEALTHY' or 'UNAVAILABLE' end
function adapter.Send(message, notifyType, duration, options)
    if not adapter.IsAvailable() then return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE,'ox_lib is unavailable') end
    local data = { description=message, type=notifyType, duration=duration }
    if options then
        data.title = options.title
        data.position = options.position
        if type(options.adapter) == 'table' then
            for _, key in ipairs({'icon','iconColor','iconAnimation','showDuration'}) do
                if options.adapter[key] ~= nil then data[key] = options.adapter[key] end
            end
        end
    end
    local ok, err = pcall(function() exports['ox_lib']:notify(data) end)
    if not ok then return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE,'ox_lib notify failed',{detail=tostring(err)}) end
    return true,nil
end
NEXM_INTERNAL.Adapters.Notify.ox_lib = adapter
