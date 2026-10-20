local Errors = NEXM_INTERNAL.Modules.Errors
local Validation = NEXM_INTERNAL.Modules.Validation
local Logger = NEXM_INTERNAL.Modules.Logger
local InventoryManager = NEXM_INTERNAL.Managers.Inventory
local FrameworkManager = NEXM_INTERNAL.Managers.Framework
local Constants = NEXM_INTERNAL.Modules.Constants
local Codes = Constants.ERROR_CODES
local Callable = NEXM_INTERNAL.Modules.Callable

local UsableItems = {}
local registry = {}
local generations = {}

local function copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local out = {}
    for key, item in pairs(value) do out[copy(key, seen)] = copy(item, seen) end
    seen[value] = nil
    return out
end

local function validateItemName(itemName)
    local ok = Validation.String(itemName, {
        name = 'itemName', nonEmpty = true, min = 1,
        max = (Config.Security and Config.Security.maxItemNameLength) or 128
    })
    if not ok or itemName:find('[%c]') then
        return nil, Errors.Create(Codes.INVALID_ITEM, 'Invalid usable item name', { actualType = type(itemName) })
    end
    return itemName, nil
end

local function validateOptions(options)
    if options == nil then return {}, nil end
    local ok, err = Validation.SerializableTable(options, {
        name = 'usable item options', required = false, maxDepth = 4, maxEntries = 64
    })
    if not ok then return nil, err end
    return copy(options), nil
end

local function currentEntry(itemName, generationToken)
    local entry = registry[itemName]
    if not entry then return nil end
    if generationToken ~= nil and entry.generation ~= generationToken then return nil end
    return entry
end

function UsableItems.DispatchProviderUse(itemName, source, context, generationToken, provider)
    local entry = currentEntry(itemName, generationToken)
    if not entry then return false, Errors.Create(Codes.REGISTRATION_NOT_FOUND, 'Usable item is no longer registered', { item = itemName }) end

    local sourceOk, sourceErr = Validation.Source(source, { name = 'source' })
    if not sourceOk then return false, sourceErr end
    if type(context) ~= 'table' or context.name ~= itemName then
        return false, Errors.Create(Codes.INTEGRATION_ERROR, 'Usable item provider returned an invalid context', { item = itemName, provider = provider })
    end

    local safeContext = {
        name = itemName,
        amount = 1,
        slot = tonumber(context.slot),
        metadata = type(context.metadata) == 'table' and copy(context.metadata) or nil,
        provider = tostring(context.provider or provider or 'unknown')
    }

    local ok, result = pcall(entry.handler, source, safeContext)
    if not ok then
        local err = Errors.Create(Codes.INTEGRATION_ERROR, 'Registered usable item handler failed', {
            item = itemName, ownerResource = entry.ownerResource, provider = safeContext.provider
        })
        Logger.Infrastructure(err, 'inventory:usable-item', entry.ownerResource)
        if Config.Debug then Logger.Debug('Usable item handler raw error', { item = itemName, rawError = tostring(result) }, entry.ownerResource) end
        return false, err
    end
    return true, nil
end

local function bindViaInventory(itemName, generationToken)
    local adapter, invErr = InventoryManager.RequireHealthy()
    if not adapter then return false, invErr end
    local caps = adapter.metadata and adapter.metadata.capabilities or {}
    if caps.usableItems ~= true then return nil, nil end
    if type(adapter.RegisterUsableItem) ~= 'function' then
        return false, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'Selected inventory does not expose usable-item registration', {
            feature = 'inventory.usableItems', inventory = InventoryManager.GetName()
        })
    end
    local ok, err = adapter.RegisterUsableItem(itemName, UsableItems.DispatchProviderUse, generationToken)
    if ok ~= true then return false, err or Errors.Create(Codes.INTEGRATION_ERROR, 'Inventory usable-item registration failed', { item = itemName, inventory = InventoryManager.GetName() }) end
    return true, 'inventory'
end

local function frameworkPathAllowed(inventoryName, frameworkName)
    return (inventoryName == 'qb-inventory' and frameworkName == 'qbcore')
        or (inventoryName == 'esx' and frameworkName == 'esx')
end

local function bindViaFramework(itemName, generationToken)
    local inventoryName = InventoryManager.GetName()
    local frameworkName = FrameworkManager.GetName()
    if not frameworkPathAllowed(inventoryName, frameworkName) then
        return false, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'Usable-item registration is not supported for the selected framework/inventory profile', {
            feature = 'inventory.usableItems', inventory = inventoryName, framework = frameworkName
        })
    end
    local adapter, frameworkErr = FrameworkManager.RequireHealthy()
    if not adapter then return false, frameworkErr end
    local caps = adapter.metadata and adapter.metadata.capabilities and adapter.metadata.capabilities.framework or {}
    if caps.usableItems ~= true or type(adapter.RegisterUsableItem) ~= 'function' then
        return false, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'Selected framework does not support usable-item registration', {
            feature = 'framework.usableItems', framework = frameworkName
        })
    end
    local ok, err = adapter.RegisterUsableItem(itemName, UsableItems.DispatchProviderUse, generationToken)
    if ok ~= true then return false, err or Errors.Create(Codes.INTEGRATION_ERROR, 'Framework usable-item registration failed', { item = itemName, framework = frameworkName }) end
    return true, 'framework'
end

local function bind(itemName, generationToken)
    local ok, pathOrErr = bindViaInventory(itemName, generationToken)
    if ok == true then return true, pathOrErr end
    if ok == false then return false, pathOrErr end
    return bindViaFramework(itemName, generationToken)
end

function UsableItems.Register(itemName, handler, options, ownerResource)
    local item, itemErr = validateItemName(itemName); if not item then return false, itemErr end
    if not Callable.Is(handler) then
        return false, Errors.Create(Codes.INVALID_HANDLER, 'Usable item handler must be a function', { item = item })
    end
    if type(ownerResource) ~= 'string' or ownerResource == '' then
        return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Usable item registration owner is invalid')
    end
    local normalizedOptions, optionsErr = validateOptions(options); if not normalizedOptions then return false, optionsErr end

    local existing = registry[item]
    if existing then
        return false, Errors.Create(Codes.ALREADY_REGISTERED, 'Usable item is already registered', {
            item = item, ownerResource = ownerResource, existingOwnerResource = existing.ownerResource,
            sameOwner = existing.ownerResource == ownerResource
        })
    end

    generations[item] = (generations[item] or 0) + 1
    local generationToken = generations[item]
    registry[item] = {
        name = item,
        ownerResource = ownerResource,
        handler = handler,
        options = normalizedOptions,
        registeredAt = os.time(),
        generation = generationToken,
        binding = nil
    }

    local ok, bindingOrErr = bind(item, generationToken)
    if ok ~= true then
        registry[item] = nil
        generations[item] = generationToken + 1
        return false, bindingOrErr
    end
    registry[item].binding = bindingOrErr
    return true, nil
end

function UsableItems.CleanupOwner(ownerResource)
    local removed = 0
    for itemName, entry in pairs(registry) do
        if entry.ownerResource == ownerResource then
            registry[itemName] = nil
            generations[itemName] = (generations[itemName] or entry.generation or 0) + 1
            removed = removed + 1
        end
    end
    return removed
end

function UsableItems.RebindFramework()
    if not FrameworkManager.IsHealthy() then return 0 end
    local rebound = 0
    for itemName, entry in pairs(registry) do
        if entry.binding == 'framework' then
            local ok, err = bindViaFramework(itemName, entry.generation)
            if ok then
                rebound = rebound + 1
            else
                Logger.Infrastructure(err, 'inventory:usable-item-rebind', entry.ownerResource)
            end
        end
    end
    return rebound
end

function UsableItems.CountRegistered()
    local count = 0
    for _ in pairs(registry) do count = count + 1 end
    return count
end

function UsableItems.GetRegistration(itemName)
    local entry = registry[itemName]
    if not entry then return nil end
    return {
        name = entry.name, ownerResource = entry.ownerResource,
        registeredAt = entry.registeredAt, generation = entry.generation, binding = entry.binding
    }
end

AddEventHandler('nexm_core:server:frameworkRecovered', function()
    UsableItems.RebindFramework()
end)

NEXM_INTERNAL.Modules.UsableItems = UsableItems
