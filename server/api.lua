local Constants = NEXM_INTERNAL.Modules.Constants
local State = NEXM_INTERNAL.Modules.State
local Errors = NEXM_INTERNAL.Modules.Errors
local Validation = NEXM_INTERNAL.Modules.Validation
local Transport = NEXM_INTERNAL.Modules.Transport
local SemVer = NEXM_INTERNAL.Modules.SemVer
local Logger = NEXM_INTERNAL.Modules.Logger
local Ownership = NEXM_INTERNAL.Modules.Ownership
local DB = NEXM_INTERNAL.Modules.DB
local Migrations = NEXM_INTERNAL.Modules.Migrations
local Readiness = NEXM_INTERNAL.Modules.Readiness
local Player = NEXM_INTERNAL.Modules.Player
local Jobs = NEXM_INTERNAL.Modules.Jobs
local Lifecycle = NEXM_INTERNAL.Modules.Lifecycle
local Money = NEXM_INTERNAL.Modules.Money
local Inventory = NEXM_INTERNAL.Modules.Inventory
local Callback = NEXM_INTERNAL.Modules.Callbacks
local EventBus = NEXM_INTERNAL.Modules.EventBus
local Permissions = NEXM_INTERNAL.Modules.Permissions
local RateLimit = NEXM_INTERNAL.Modules.RateLimit
local Notify = NEXM_INTERNAL.Modules.Notify
local Locale = NEXM_INTERNAL.Modules.Locale
local Audit = NEXM_INTERNAL.Modules.Audit
local Components = NEXM_INTERNAL.Modules.Components
local Resources = NEXM_INTERNAL.Managers.Resources
local Services = NEXM_INTERNAL.Managers.Services
local Features = NEXM_INTERNAL.Managers.Features
local Integrations = NEXM_INTERNAL.Managers.Integrations
local Framework = NEXM_INTERNAL.Managers.Framework
local Codes, States = Constants.ERROR_CODES, Constants.STATES

local facadeCache = {}
local transportFacadeCache = {}

local function requireReady()
    if State.IsReady() then return true, nil end
    return false, Errors.Create(Codes.CORE_NOT_READY, 'NEXM Core is not ready', { state = State.Get() })
end

local function requireFrameworkOperational()
    local state = State.Get()
    if state == States.READY or state == States.DEGRADED then return true, nil end
    return false, Errors.Create(Codes.CORE_NOT_READY, 'NEXM Core framework layer is not operational yet', { state = state })
end

local function getter(call)
    return function(...)
        local ok, err = requireFrameworkOperational()
        if not ok then return nil, err end
        return call(...)
    end
end
local function predicate(call)
    return function(...)
        local ok, err = requireFrameworkOperational()
        if not ok then return false, err end
        return call(...)
    end
end

-- Every public server API taking a player source enforces the canonical source
-- contract at the facade boundary before dispatching into domain services.
-- This is intentionally redundant with service-level validation: cross-resource
-- callers must never gain numeric-string coercion through a wrapper/adapter path.
local function sourceGetter(call)
    return getter(function(source, ...)
        local valid, err = Validation.Source(source, { name = 'source' })
        if not valid then return nil, err end
        return call(source, ...)
    end)
end
local function sourcePredicate(call)
    return predicate(function(source, ...)
        local valid, err = Validation.Source(source, { name = 'source' })
        if not valid then return false, err end
        return call(source, ...)
    end)
end

local function buildFacade(owner)
    local facade = {}
    facade.IsReady = function() return State.IsReady() end
    facade.GetStatus = function() return State.GetStatus() end

    facade.Version = {
        Get = function() return Constants.VERSION end,
        Compare = SemVer.Compare,
        Satisfies = SemVer.Satisfies,
        Require = function(constraint)
            local ok, err = SemVer.Satisfies(Constants.VERSION, constraint)
            if err then return false, err end
            if not ok then
                return false, Errors.Create(Codes.INCOMPATIBLE_CORE_VERSION,
                    'Installed NEXM Core version does not satisfy requirement', {
                        installed = Constants.VERSION, required = constraint
                    })
            end
            return true, nil
        end
    }

    facade.Validate = Validation
    facade.Log = {
        Debug = function(message, metadata) Logger.Debug(message, metadata, owner) end,
        Info = function(message, metadata) Logger.Info(message, metadata, owner) end,
        Warn = function(message, metadata) Logger.Warn(message, metadata, owner) end,
        Error = function(message, metadata) Logger.Error(message, metadata, owner) end,
        IsEnabled = Logger.IsEnabled
    }

    local function readyDB(call)
        return function(...)
            local ready, readyErr = requireReady()
            if not ready then return nil, readyErr end
            return call(...)
        end
    end
    facade.DB = {
        Query = readyDB(function(sql, params) return DB.Query(sql, params, owner) end),
        Single = readyDB(function(sql, params) return DB.Single(sql, params, owner) end),
        Scalar = readyDB(function(sql, params) return DB.Scalar(sql, params, owner) end),
        Insert = readyDB(function(sql, params) return DB.Insert(sql, params, owner) end),
        Update = readyDB(function(sql, params) return DB.Update(sql, params, owner) end),
        Transaction = function(queries, sharedParams)
            local ready, readyErr = requireReady()
            if not ready then return false, readyErr end
            return DB.Transaction(queries, sharedParams, owner)
        end
    }

    facade.Migrations = {
        Register = function(definition)
            local ready, readyErr = requireReady(); if not ready then return false, readyErr end
            return Migrations.Register(owner, definition, owner)
        end,
        Run = function()
            local ready, readyErr = requireReady(); if not ready then return false, readyErr end
            -- MigrationService uses the privileged internal DB module internally;
            -- it never calls this public READY-gated DB facade.
            return Migrations.Run(owner)
        end
    }

    facade.Resources = {
        Register = function(metadata)
            local ready, readyErr = requireReady(); if not ready then return false, readyErr end
            return Resources.Register(metadata, owner)
        end,
        IsRunning = Resources.IsRunning, Get = Resources.Get, GetAll = Resources.GetAll
    }
    facade.Services = {
        Register = function(name, api, metadata)
            local ready, readyErr = requireReady(); if not ready then return false, readyErr end
            return Services.Register(name, api, metadata, owner)
        end,
        Get = Services.Get, Has = Services.Has, GetMetadata = Services.GetMetadata
    }
    facade.Features = {
        Register = function(name, value, metadata)
            local ready, readyErr = requireReady(); if not ready then return false, readyErr end
            return Features.Register(name, value, metadata, owner)
        end,
        Has = Features.Has, Get = Features.Get, GetMetadata = Features.GetMetadata
    }
    facade.Integrations = {
        GetName = Integrations.GetName,
        IsAvailable = Integrations.IsAvailable,
        GetCapabilities = Integrations.GetCapabilities,
        GetState = Integrations.GetState,
        IsHealthy = Integrations.IsHealthy
    }
    facade.Components = {
        Get = Components.Get,
        GetAll = Components.GetAll
    }

    facade.Player = {
        Get = sourceGetter(Player.Get),
        Exists = sourcePredicate(Player.Exists),
        GetIdentifier = sourceGetter(Player.GetIdentifier),
        GetCharacterIdentifier = sourceGetter(Player.GetCharacterIdentifier),
        GetAccountIdentifier = sourceGetter(Player.GetAccountIdentifier),
        GetLicense = sourceGetter(Player.GetLicense),
        GetCharacterName = sourceGetter(Player.GetCharacterName),
        GetJob = sourceGetter(Player.GetJob),
        GetJobGrade = sourceGetter(Player.GetJobGrade),
        GetSource = getter(Player.GetSource),
        IsOnline = predicate(Player.IsOnline),
        GetFrameworkObject = sourceGetter(Player.GetFrameworkObject)
    }
    facade.Jobs = {
        Get = sourceGetter(Jobs.Get),
        Has = sourcePredicate(Jobs.Has),
        HasAny = sourcePredicate(Jobs.HasAny),
        MinimumGrade = sourcePredicate(Jobs.MinimumGrade),
        IsOnDuty = sourceGetter(Jobs.IsOnDuty)
    }

    facade.Money = {
        Get = sourceGetter(Money.Get),
        Add = sourcePredicate(Money.Add),
        Remove = sourcePredicate(Money.Remove),
        CanAfford = sourcePredicate(Money.CanAfford)
    }
    facade.Inventory = {
        HasItem = sourcePredicate(Inventory.HasItem),
        GetItemCount = sourceGetter(Inventory.GetItemCount),
        AddItem = sourcePredicate(Inventory.AddItem),
        RemoveItem = sourcePredicate(Inventory.RemoveItem),
        CanCarry = sourcePredicate(Inventory.CanCarry),
        GetItems = sourceGetter(Inventory.GetItems)
    }

    -- Supporting platform services are intentionally non-transactional helpers.
    facade.Notify = {
        Send = function(source, message, notifyType, duration, options)
            local ready, readyErr = requireReady(); if not ready then return false, readyErr end
            return Notify.Send(source, message, notifyType, duration, options)
        end
    }
    facade.Locale = {
        Register = function(locale, strings) return Locale.Register(locale, strings, owner) end,
        Get = function(key, vars) return Locale.Get(key, vars, owner) end,
        SetFallback = function(locale) return Locale.SetFallback(locale, owner) end
    }
    facade.Audit = {
        Log = function(entry)
            local ready, readyErr = requireReady(); if not ready then return false, readyErr end
            return Audit.Log(entry, owner)
        end
    }

    facade.Callback = {
        Register = function(name, handler, options)
            local ready, readyErr = requireReady(); if not ready then return false, readyErr end
            return Callback.Register(name, handler, options, owner)
        end
    }
    facade.RateLimit = {
        Check = function(source, key, options) return RateLimit.Check(source, key, options, owner) end,
        Reset = function(source, key) return RateLimit.Reset(source, key, owner) end
    }
    facade.Permissions = {
        Define = function(name, policy)
            local ready, readyErr = requireReady(); if not ready then return false, readyErr end
            return Permissions.Define(name, policy, owner)
        end,
        Has = function(source, name) return Permissions.Has(source, name, owner) end,
        HasAny = function(source, names) return Permissions.HasAny(source, names, owner) end
    }
    facade.Events = {
        OnReady = function(callback) return Readiness.Subscribe(callback, owner) end,
        On = function(name, callback) return EventBus.On(name, callback, owner) end,
        Emit = function(name, payload) return EventBus.Emit(name, payload) end,
        OnPlayerLoaded = function(callback) return Lifecycle.Subscribe('playerLoaded', callback, owner) end,
        OnPlayerUnloaded = function(callback) return Lifecycle.Subscribe('playerUnloaded', callback, owner) end,
        OnJobChanged = function(callback) return Lifecycle.Subscribe('jobChanged', callback, owner) end,
        OnDutyChanged = function(callback) return Lifecycle.Subscribe('dutyChanged', callback, owner) end
    }

    return facade
end

function GetCoreObject(transportMode)
    local owner = Ownership.Resolve('nexm_core')
    if not facadeCache[owner] then facadeCache[owner] = buildFacade(owner) end
    if Transport and Transport.IsRequested(transportMode) then
        if not transportFacadeCache[owner] then transportFacadeCache[owner] = Transport.WrapFacade(facadeCache[owner]) end
        return transportFacadeCache[owner]
    end
    return facadeCache[owner]
end
exports('GetCoreObject', GetCoreObject)

NEXM_INTERNAL.Modules.API = {
    ClearFacade = function(ownerResource)
        facadeCache[ownerResource] = nil
        transportFacadeCache[ownerResource] = nil
    end
}
