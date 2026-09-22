local Errors=NEXM_INTERNAL.Modules.Errors
local Validation=NEXM_INTERNAL.Modules.Validation
local Cache=NEXM_INTERNAL.Modules.PlayerCache
local Framework=NEXM_INTERNAL.Managers.Framework
local Codes=NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Guard={}
function Guard.Capture(source)
    local ok,err=Validation.Source(source,{name='source'}); if not ok then return nil,err end
    local _,fwErr=Framework.RequireHealthy(); if fwErr then return nil,fwErr end
    local session=Cache.GetSession(source)
    if not session then return nil,Errors.Create(Codes.PLAYER_NOT_FOUND,'No active normalized character session',{source=source}) end
    local snapshot=Cache.Get(source)
    return {source=source,characterSessionId=session,identifier=snapshot and snapshot.identifier or nil},nil
end
function Guard.Validate(context)
    if type(context)~='table' then return false,Errors.Create(Codes.INVALID_ARGUMENT,'Invalid character session context') end
    if not Cache.IsCurrentSession(context.source,context.characterSessionId) then
        return false,Errors.Create(Codes.STALE_CHARACTER_SESSION,'Character session changed before sensitive operation could complete',{source=context.source,expectedSession=context.characterSessionId,currentSession=Cache.GetSession(context.source)})
    end
    return true,nil
end
function Guard.Run(context,fn)
    local ok,err=Guard.Validate(context); if not ok then return false,err end
    local callOk,a,b=pcall(fn)
    if not callOk then return false,Errors.Create(Codes.ADAPTER_ERROR,'Sensitive adapter call failed',{source=context.source}) end
    local still,staleErr=Guard.Validate(context); if not still then return false,staleErr end
    return true,a,b
end
NEXM_INTERNAL.Modules.SessionGuard=Guard
