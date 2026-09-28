local Constants = NEXM_INTERNAL.Modules.Constants
local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = Constants.ERROR_CODES

local TemporaryAppearance = {}

local function createError(code, message, context)
    return Errors.Create(code, message, context)
end

local function cfg()
    local value = Config and Config.TemporaryAppearance or {}
    return {
        restoreModel = value.restoreModel ~= false,
        modelLoadTimeoutMs = tonumber(value.modelLoadTimeoutMs) or 5000,
        verifyDelayMs = tonumber(value.verifyDelayMs) or 50
    }
end

local function entry(container, index)
    if type(container) ~= 'table' then return nil end
    return container[tostring(index)] or container[index]
end

function TemporaryAppearance.Capture()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return nil, createError(Codes.TEMP_APPEARANCE_CAPTURE_FAILED, 'Local player ped is not available')
    end

    local snapshot = {
        version = 1,
        model = GetEntityModel(ped),
        components = {},
        props = {}
    }

    for componentId = 0, 11 do
        snapshot.components[tostring(componentId)] = {
            drawable = GetPedDrawableVariation(ped, componentId),
            texture = GetPedTextureVariation(ped, componentId),
            palette = GetPedPaletteVariation(ped, componentId)
        }
    end

    for propId = 0, 7 do
        local drawable = GetPedPropIndex(ped, propId)
        snapshot.props[tostring(propId)] = {
            drawable = drawable,
            texture = drawable == -1 and 0 or GetPedPropTextureIndex(ped, propId)
        }
    end

    return snapshot, nil
end

local function ensureModel(model, options)
    local ped = PlayerPedId()
    if GetEntityModel(ped) == model then return ped, nil end

    local settings = cfg()
    local restoreModel = options and options.restoreModel
    if restoreModel == nil then restoreModel = settings.restoreModel end
    if restoreModel ~= true then
        return nil, createError(Codes.TEMP_APPEARANCE_MODEL_MISMATCH, 'Current ped model does not match the saved appearance model', {
            currentModel = GetEntityModel(ped),
            savedModel = model
        })
    end

    if not IsModelInCdimage(model) or not IsModelValid(model) then
        return nil, createError(Codes.TEMP_APPEARANCE_RESTORE_FAILED, 'Saved ped model is not valid', { model = model })
    end

    RequestModel(model)
    local started = GetGameTimer()
    while not HasModelLoaded(model) do
        if GetGameTimer() - started >= settings.modelLoadTimeoutMs then
            SetModelAsNoLongerNeeded(model)
            return nil, createError(Codes.TEMP_APPEARANCE_RESTORE_FAILED, 'Timed out loading saved ped model', {
                model = model,
                timeoutMs = settings.modelLoadTimeoutMs
            })
        end
        Wait(0)
    end

    SetPlayerModel(PlayerId(), model)
    SetModelAsNoLongerNeeded(model)
    Wait(0)

    ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) or GetEntityModel(ped) ~= model then
        return nil, createError(Codes.TEMP_APPEARANCE_RESTORE_FAILED, 'Saved ped model could not be applied', { model = model })
    end
    return ped, nil
end

function TemporaryAppearance.Verify(snapshot, options)
    if type(snapshot) ~= 'table' or type(snapshot.components) ~= 'table' or type(snapshot.props) ~= 'table' then
        return false, createError(Codes.TEMP_APPEARANCE_INVALID, 'Invalid appearance snapshot for verification')
    end

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false, createError(Codes.TEMP_APPEARANCE_RESTORE_FAILED, 'Local player ped is not available for verification')
    end

    local settings = cfg()
    local restoreModel = options and options.restoreModel
    if restoreModel == nil then restoreModel = settings.restoreModel end
    if restoreModel and GetEntityModel(ped) ~= snapshot.model then
        return false, createError(Codes.TEMP_APPEARANCE_MODEL_MISMATCH, 'Restored ped model verification failed', {
            currentModel = GetEntityModel(ped), savedModel = snapshot.model
        })
    end
    if not restoreModel and GetEntityModel(ped) ~= snapshot.model then
        return false, createError(Codes.TEMP_APPEARANCE_MODEL_MISMATCH, 'Current ped model differs from saved appearance model', {
            currentModel = GetEntityModel(ped), savedModel = snapshot.model
        })
    end

    for componentId = 0, 11 do
        local saved = entry(snapshot.components, componentId)
        if type(saved) ~= 'table' then
            return false, createError(Codes.TEMP_APPEARANCE_INVALID, 'Missing component in saved appearance', { componentId = componentId })
        end
        local drawable = GetPedDrawableVariation(ped, componentId)
        local texture = GetPedTextureVariation(ped, componentId)
        local palette = GetPedPaletteVariation(ped, componentId)
        if drawable ~= saved.drawable or texture ~= saved.texture or palette ~= saved.palette then
            return false, createError(Codes.TEMP_APPEARANCE_RESTORE_FAILED, 'Ped component verification failed', {
                componentId = componentId,
                expectedDrawable = saved.drawable,
                actualDrawable = drawable,
                expectedTexture = saved.texture,
                actualTexture = texture,
                expectedPalette = saved.palette,
                actualPalette = palette
            })
        end
    end

    for propId = 0, 7 do
        local saved = entry(snapshot.props, propId)
        if type(saved) ~= 'table' then
            return false, createError(Codes.TEMP_APPEARANCE_INVALID, 'Missing prop in saved appearance', { propId = propId })
        end
        local drawable = GetPedPropIndex(ped, propId)
        local texture = drawable == -1 and 0 or GetPedPropTextureIndex(ped, propId)
        if drawable ~= saved.drawable or texture ~= saved.texture then
            return false, createError(Codes.TEMP_APPEARANCE_RESTORE_FAILED, 'Ped prop verification failed', {
                propId = propId,
                expectedDrawable = saved.drawable,
                actualDrawable = drawable,
                expectedTexture = saved.texture,
                actualTexture = texture
            })
        end
    end

    return true, nil
end

function TemporaryAppearance.Restore(snapshot, options)
    if type(snapshot) ~= 'table' or type(snapshot.model) ~= 'number' or type(snapshot.components) ~= 'table' or type(snapshot.props) ~= 'table' then
        return false, createError(Codes.TEMP_APPEARANCE_INVALID, 'Invalid appearance snapshot for restore')
    end

    local ped, modelErr = ensureModel(snapshot.model, options)
    if not ped then return false, modelErr end

    for componentId = 0, 11 do
        local saved = entry(snapshot.components, componentId)
        if type(saved) ~= 'table' then
            return false, createError(Codes.TEMP_APPEARANCE_INVALID, 'Missing component in saved appearance', { componentId = componentId })
        end
        SetPedComponentVariation(ped, componentId, saved.drawable, saved.texture, saved.palette)
    end

    for propId = 0, 7 do
        local saved = entry(snapshot.props, propId)
        if type(saved) ~= 'table' then
            return false, createError(Codes.TEMP_APPEARANCE_INVALID, 'Missing prop in saved appearance', { propId = propId })
        end
        if saved.drawable == -1 then
            ClearPedProp(ped, propId)
        else
            SetPedPropIndex(ped, propId, saved.drawable, saved.texture, true)
        end
    end

    local settings = cfg()
    if settings.verifyDelayMs > 0 then Wait(settings.verifyDelayMs) end
    return TemporaryAppearance.Verify(snapshot, options)
end

RegisterNetEvent('nexm_core:client:temporaryAppearanceDebug', function(lines)
    if not (Config and Config.Debug == true) or type(lines) ~= 'table' then return end
    for _, line in ipairs(lines) do
        print(('[NEXM Core][TemporaryAppearance] %s'):format(tostring(line)))
    end
end)

NEXM_INTERNAL.Modules.ClientTemporaryAppearance = TemporaryAppearance
