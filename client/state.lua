local ClientState = {}
local current = nil

local function copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return '<cycle>' end
    seen[value] = true
    local out = {}
    for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
    seen[value] = nil
    return out
end

function ClientState.Set(snapshot)
    current = type(snapshot) == 'table' and copy(snapshot) or nil
end
function ClientState.Clear() current = nil end
function ClientState.Get() return current and copy(current) or nil end
function ClientState.IsLoaded() return current ~= nil and current.loaded == true end

NEXM_INTERNAL.Modules.ClientPlayerState = ClientState
