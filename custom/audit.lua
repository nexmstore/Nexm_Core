-- Optional customer audit backend. Enable Config.Audit.Backends.custom only
-- after replacing this template implementation.
NEXM_CUSTOM_AUDIT_BACKEND = NEXM_CUSTOM_AUDIT_BACKEND or {}
function NEXM_CUSTOM_AUDIT_BACKEND.Send(_entry)
    return false, 'Custom audit backend is not implemented'
end
