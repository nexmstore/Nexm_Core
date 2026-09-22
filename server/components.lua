local State=NEXM_INTERNAL.Modules.State
local Framework=NEXM_INTERNAL.Managers.Framework
local Integrations=NEXM_INTERNAL.Managers.Integrations
local RegistryBase=NEXM_INTERNAL.Modules.RegistryBase

local Components={}
local function copy(v) return RegistryBase.Copy(v) end
function Components.Get(name)
    if type(name)~='string' then return nil end
    local c=State.GetComponent(name)
    if not c then return nil end
    local provider=nil; local caps=nil
    if name=='database' then provider='oxmysql'
    elseif name=='framework' then provider=Framework and Framework.GetName and Framework.GetName() or nil; caps=Framework and Framework.GetCapabilities and Framework.GetCapabilities() or nil
    elseif name=='money' then provider='framework'; local fc=Framework and Framework.GetCapabilities and Framework.GetCapabilities() or nil; caps=fc and fc.money or nil
    elseif name=='inventory' or name=='notify' then provider=Integrations.GetName(name); caps=Integrations.GetCapabilities(name)
    elseif name=='rpc' or name=='audit' then provider='nexm_core' end
    return {name=name,provider=provider,state=c.state,capabilities=copy(caps or {}),details=copy(c.details or {}),updatedAt=c.updatedAt}
end
function Components.GetAll()
    local out={}
    for _,name in ipairs({'database','framework','money','inventory','notify','rpc','audit'}) do out[name]=Components.Get(name) end
    return out
end
NEXM_INTERNAL.Modules.Components=Components
