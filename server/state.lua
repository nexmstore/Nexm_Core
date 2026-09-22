local Constants = NEXM_INTERNAL.Modules.Constants
local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = Constants.ERROR_CODES
local States = Constants.STATES

local State = {}

local current = States.BOOTING
local changedAt = os.time()
local lastError = nil
local components = {
    database = { state = Constants.HEALTH.NOT_INITIALIZED, updatedAt = os.time() },
    framework = { state = Constants.HEALTH.NOT_INITIALIZED, updatedAt = os.time() },
    money = { state = Constants.HEALTH.NOT_INITIALIZED, updatedAt = os.time() },
    inventory = { state = Constants.HEALTH.NOT_INITIALIZED, updatedAt = os.time() },
    notify = { state = Constants.HEALTH.NOT_INITIALIZED, updatedAt = os.time() },
    rpc = { state = Constants.HEALTH.NOT_INITIALIZED, updatedAt = os.time() },
    audit = { state = Constants.HEALTH.NOT_INITIALIZED, updatedAt = os.time() }
}

local transitions = {
    [States.BOOTING] = { [States.DATABASE] = true, [States.FAILED] = true, [States.STOPPING] = true },
    [States.DATABASE] = { [States.MIGRATING] = true, [States.FAILED] = true, [States.STOPPING] = true },
    [States.MIGRATING] = { [States.FRAMEWORK] = true, [States.FAILED] = true, [States.STOPPING] = true },
    [States.FRAMEWORK] = { [States.PLATFORM] = true, [States.FAILED] = true, [States.STOPPING] = true },
    [States.PLATFORM] = { [States.READY] = true, [States.DEGRADED] = true, [States.FAILED] = true, [States.STOPPING] = true },
    [States.READY] = { [States.DEGRADED] = true, [States.FAILED] = true, [States.STOPPING] = true },
    [States.DEGRADED] = { [States.READY] = true, [States.FAILED] = true, [States.STOPPING] = true },
    [States.FAILED] = { [States.STOPPING] = true },
    [States.STOPPING] = {}
}

local function copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return '<cycle>' end
    seen[value] = true
    local out = {}
    for key, item in pairs(value) do out[copy(key, seen)] = copy(item, seen) end
    seen[value] = nil
    return out
end

function State.Set(nextState)
    if current == nextState then return true, nil end
    if not transitions[current] or not transitions[current][nextState] then
        return false, Errors.Create(Codes.INVALID_STATE_TRANSITION, 'Invalid NEXM Core state transition', {
            from = current, to = nextState
        })
    end
    current = nextState
    changedAt = os.time()
    return true, nil
end

function State.Fail(err)
    lastError = Errors.Is(err) and Errors.Copy(err) or Errors.Create(Codes.INVALID_ARGUMENT, 'Core failed without structured error')
    if current ~= States.FAILED and current ~= States.STOPPING then
        current = States.FAILED
        changedAt = os.time()
    end
end

function State.SetComponent(name, healthState, details)
    components[name] = {
        state = healthState,
        updatedAt = os.time(),
        details = type(details) == 'table' and copy(details) or nil
    }
end

function State.GetComponent(name)
    local component = components[name]
    return component and copy(component) or nil
end

function State.Get() return current end
function State.IsReady() return current == States.READY end
function State.GetStatus()
    return {
        name = Constants.NAME,
        version = Constants.VERSION,
        buildId = Constants.BUILD_ID,
        state = current,
        changedAt = changedAt,
        components = copy(components),
        lastError = lastError and Errors.Copy(lastError) or nil
    }
end

NEXM_INTERNAL.Modules.State = State
