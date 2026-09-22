local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local Cache = {}
local playersBySource = {}
local sourceByCharacter = {}
local generation = 0

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

local function publicSnapshot(record)
    return record and copy(record.snapshot) or nil
end

function Cache.Store(source, snapshot)
    local old = playersBySource[source]
    local canonical = snapshot.identifier
    local existingSource = canonical and sourceByCharacter[canonical] or nil
    if existingSource and existingSource ~= source then
        return nil, Errors.Create(Codes.IDENTITY_CONFLICT, 'Canonical character is already cached on another source', {
            source = source, existingSource = existingSource, identifier = canonical
        })
    end

    if old and old.snapshot.identifier and old.snapshot.identifier ~= canonical
        and sourceByCharacter[old.snapshot.identifier] == source then
        sourceByCharacter[old.snapshot.identifier] = nil
    end

    generation = generation + 1
    local record = { snapshot = copy(snapshot), characterSessionId = generation }
    playersBySource[source] = record
    if canonical then sourceByCharacter[canonical] = source end
    return generation, nil
end

function Cache.Get(source) return publicSnapshot(playersBySource[source]) end
function Cache.GetInternal(source) return playersBySource[source] end
function Cache.GetSession(source)
    local record = playersBySource[source]
    return record and record.characterSessionId or nil
end
function Cache.IsCurrentSession(source, sessionId)
    local record = playersBySource[source]
    return record ~= nil and record.characterSessionId == sessionId
end
function Cache.GetSource(identifier) return sourceByCharacter[identifier] end
function Cache.IsOnline(identifier) return sourceByCharacter[identifier] ~= nil end
function Cache.Remove(source)
    local record = playersBySource[source]
    if not record then return nil end
    playersBySource[source] = nil
    if record.snapshot.identifier and sourceByCharacter[record.snapshot.identifier] == source then
        sourceByCharacter[record.snapshot.identifier] = nil
    end
    return { snapshot = publicSnapshot(record), characterSessionId = record.characterSessionId }
end
function Cache.UpdateJob(source, job, expectedSession)
    local record = playersBySource[source]
    if not record or (expectedSession and record.characterSessionId ~= expectedSession) then
        return false, Errors.Create(Codes.STALE_CHARACTER_SESSION, 'Player state update belongs to a stale character session', {
            source = source, expectedSession = expectedSession,
            currentSession = record and record.characterSessionId or nil
        })
    end
    local oldJob = copy(record.snapshot.job)
    record.snapshot.job = copy(job)
    return true, oldJob
end
function Cache.ClearAll()
    local old = {}
    for source, record in pairs(playersBySource) do
        old[source] = { snapshot = publicSnapshot(record), characterSessionId = record.characterSessionId }
    end
    playersBySource, sourceByCharacter = {}, {}
    return old
end
function Cache.Count()
    local count = 0
    for _ in pairs(playersBySource) do count = count + 1 end
    return count
end
function Cache.ListSources()
    local out = {}
    for source in pairs(playersBySource) do out[#out + 1] = source end
    table.sort(out)
    return out
end

NEXM_INTERNAL.Modules.PlayerCache = Cache
