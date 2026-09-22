local Contract = NEXM_INTERNAL.Modules.NotifyContract
local Manager = NEXM_INTERNAL.Managers.Notify
local Validation = NEXM_INTERNAL.Modules.Validation
local Errors = NEXM_INTERNAL.Modules.Errors
local Logger = NEXM_INTERNAL.Modules.Logger
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Health = NEXM_INTERNAL.Modules.Constants.HEALTH
local State = NEXM_INTERNAL.Modules.State

local Notify = {}

function Notify.Send(source, message, notifyType, duration, options)
    local ok, err = Validation.Source(source,{name='notification source'}); if not ok then return false,err end
    if GetPlayerName and GetPlayerName(source) == nil then return false,Errors.Create(Codes.PLAYER_NOT_FOUND,'Notification target player was not found') end
    local payload; payload,err=Contract.ValidatePayload(message,notifyType,duration,options); if not payload then return false,err end
    local component=State.GetComponent('notify')
    if component and component.state==Health.DISABLED then return false,Errors.Create(Codes.NOTIFY_DISABLED,'Notifications are disabled') end

    -- Refresh on dispatch so resource state is current. This keeps nexm_notify
    -- stop/start/restart recovery independent from nexm_core restarts.
    local refreshed; refreshed,err=Manager.Refresh('send')
    if not refreshed then return false,err or Errors.Create(Codes.NOTIFY_UNAVAILABLE,'Notification provider is unavailable') end

    local provider=Manager.GetName()
    local sent, raw
    if provider == 'nexm_notify' then
        local function clamp(value,minValue,maxValue)
            if value < minValue then return minValue end
            if value > maxValue then return maxValue end
            return value
        end
        local function truncate(value,maxLength)
            if type(value) ~= 'string' or #value <= maxLength then return value end
            return value:sub(1,maxLength)
        end
        local types={info='info',success='success',warning='warning',error='error'}
        local nexmPayload={
            type=types[payload.type] or 'default',
            message=truncate(payload.message,300),
            duration=clamp(payload.duration,1000,30000)
        }
        if payload.options then
            if payload.options.title ~= nil then nexmPayload.title=truncate(payload.options.title,80) end
            if payload.options.id ~= nil then nexmPayload.id=payload.options.id end
        end
        sent, raw = pcall(TriggerClientEvent,'nexm_notify:notify',source,nexmPayload)
    else
        sent, raw = pcall(TriggerClientEvent,'nexm_core:client:notify',source,payload.message,payload.type,payload.duration,payload.options,provider)
    end
    if not sent then
        local e=Errors.Create(Codes.NOTIFY_UNAVAILABLE,'Failed to dispatch normalized notification')
        Logger.Infrastructure(e,'notify','nexm_core')
        return false,e
    end
    return true,nil
end

NEXM_INTERNAL.Modules.Notify = Notify
