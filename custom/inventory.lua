-- Editable customer integration point. This file is intentionally outside the
-- protected Core internals. Set enabled=true and implement every method below.
-- The adapter is validated by the SAME InventoryContract as built-in adapters.
NEXM_CUSTOM_INVENTORY_ADAPTER = NEXM_CUSTOM_INVENTORY_ADAPTER or {
    enabled = false,
    metadata = {
        name = 'custom', resource = 'custom', version = '1.0.0', critical = true,
        capabilities = { metadata = false, metadataFilter = false, canCarry = false, getItems = false }
    },
    IsAvailable = function() return NEXM_CUSTOM_INVENTORY_ADAPTER.enabled == true end,
    Initialize = function() if not NEXM_CUSTOM_INVENTORY_ADAPTER.enabled then return false end return true, nil end,
    Shutdown = function() return true, nil end,
    GetState = function() return NEXM_CUSTOM_INVENTORY_ADAPTER.enabled and 'HEALTHY' or 'UNAVAILABLE' end,
    HasItem = function() return false, { code='UNSUPPORTED_FEATURE', message='Implement custom HasItem', context={} } end,
    GetItemCount = function() return nil, { code='UNSUPPORTED_FEATURE', message='Implement custom GetItemCount', context={} } end,
    AddItem = function() return false, { code='UNSUPPORTED_FEATURE', message='Implement custom AddItem', context={} } end,
    RemoveItem = function() return false, { code='UNSUPPORTED_FEATURE', message='Implement custom RemoveItem', context={} } end,
    CanCarry = function() return false, { code='UNSUPPORTED_FEATURE', message='Implement custom CanCarry', context={} } end
}
