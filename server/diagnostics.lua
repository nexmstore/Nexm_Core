local State=NEXM_INTERNAL.Modules.State
local Resources=NEXM_INTERNAL.Managers.Resources
local Services=NEXM_INTERNAL.Managers.Services
local Features=NEXM_INTERNAL.Managers.Features
local Integrations=NEXM_INTERNAL.Managers.Integrations
local Framework=NEXM_INTERNAL.Managers.Framework
local Cache=NEXM_INTERNAL.Modules.PlayerCache
local Constants=NEXM_INTERNAL.Modules.Constants
local Callbacks=NEXM_INTERNAL.Modules.Callbacks
local Permissions=NEXM_INTERNAL.Modules.Permissions
local RateLimit=NEXM_INTERNAL.Modules.RateLimit
local EventBus=NEXM_INTERNAL.Modules.EventBus
local Components=NEXM_INTERNAL.Modules.Components
local Audit=NEXM_INTERNAL.Modules.Audit
local NotifyManager=NEXM_INTERNAL.Managers.Notify

local Diagnostics={}
local initialized=false
local function println(label,value) print(('%-28s %s'):format(label..':',tostring(value))) end
local function supported(value) return value==true and 'SUPPORTED' or 'NOT SUPPORTED' end

local function componentLine(name,label)
    local c=Components and Components.Get(name) or nil
    local value=c and ((c.provider and (tostring(c.provider)..' / ') or '')..tostring(c.state)) or 'UNKNOWN'
    println(label or name,value)
end

local function printCapabilities(prefix,caps,depth)
    depth=depth or 0
    if type(caps)~='table' or depth>4 then return end
    local keys={}; for k in pairs(caps) do keys[#keys+1]=k end; table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
    for _,k in ipairs(keys) do
        local v=caps[k]; local path=prefix and (prefix..'.'..k) or k
        if type(v)=='table' then printCapabilities(path,v,depth+1) else println('  '..path,supported(v)) end
    end
end

function Diagnostics.PrintStatus(verbose)
    local status=State.GetStatus()
    print(''); print('==================== NEXM CORE ====================')
    println('Version',Constants.VERSION); println('Build',Constants.BUILD_ID or '-'); println('Release status',Constants.RELEASE_STATUS or 'UNSPECIFIED'); println('Core state',status.state)
    componentLine('database','Database'); componentLine('framework','Framework'); componentLine('money','Money')
    componentLine('inventory','Inventory'); componentLine('notify','Notify'); componentLine('rpc','RPC'); componentLine('audit','Audit')
    println('Cached characters',Cache.Count()); println('Registered resources',Resources.Count()); println('Registered services',Services.Count())
    println('Registered integrations',Integrations.Count()); println('Registered features',Features.Count())
    if Callbacks and Callbacks.CountRegistered then println('Registered callbacks',Callbacks.CountRegistered()) end
    if Callbacks and Callbacks.CountActive then println('Active RPC requests',Callbacks.CountActive()) end
    if Permissions and Permissions.Count then println('Permissions',Permissions.Count()) end
    if RateLimit and RateLimit.CountBuckets then println('Rate buckets',RateLimit.CountBuckets()) end
    if EventBus and EventBus.CountListeners then println('Event listeners',EventBus.CountListeners()) end
    if Audit and Audit.GetQueueDepth then println('Audit queue depth',Audit.GetQueueDepth()) end
    if status.lastError then println('Last error',status.lastError.code..' - '..status.lastError.message) end

    if verbose then
        print('-------------------- COMPONENTS --------------------')
        for _,name in ipairs({'framework','money','inventory','notify'}) do
            local c=Components.Get(name)
            if c then
                println(name..' provider',c.provider or '-')
                println(name..' state',c.state)
                printCapabilities(name,c.capabilities)
            end
        end
        local notifyDiag=NotifyManager and NotifyManager.GetDiagnostics and NotifyManager.GetDiagnostics() or nil
        if notifyDiag then
            println('Notify provider',notifyDiag.provider or '-')
            println('Notify resource',notifyDiag.resource or '-')
            println('Notify resource state',notifyDiag.resourceState or 'missing')
            println('Notify availability',notifyDiag.available and 'true' or 'false')
            println('Notify fallback',notifyDiag.fallback and 'true' or 'false')
        end
        print('--------------------- RESOURCES --------------------')
        for _,r in ipairs(Resources.GetAll()) do
            println(r.name,r.version..' / '..r.state)
            local req=Resources.GetRequirementStatus and Resources.GetRequirementStatus(r.name) or nil
            if req then for _,check in ipairs(req.checks or {}) do println('  '..check.name,check.ok and 'OK' or ('MISSING ('..tostring(check.detail)..')')) end end
        end
        print('---------------------- SERVICES --------------------')
        for _,m in ipairs(Services.ListMetadata()) do
            println(m.name,('owner=%s version=%s api=%s'):format(m.ownerResource,m.metadata.version,m.metadata.apiVersion))
        end
        print('-------------------- INTEGRATIONS ------------------')
        for _,m in ipairs(Integrations.ListMetadata()) do
            println(m.metadata.category..'.'..m.metadata.name,m.metadata.state)
        end
        if Audit and Audit.GetMetrics then
            local metrics=Audit.GetMetrics()
            for k,v in pairs(metrics) do
                if k == 'backends' and type(v) == 'table' then
                    local names={}; for name in pairs(v) do names[#names+1]=name end; table.sort(names)
                    for _,name in ipairs(names) do println('Audit backend '..name,v[name]) end
                else
                    println('Audit '..k,v)
                end
            end
        end
    end
    print('====================================================='); print('')
end
function Diagnostics.Initialize()
    if initialized then return end
    initialized=true
    RegisterCommand('nexm:status',function(source,args)
        if source~=0 then return end
        Diagnostics.PrintStatus(type(args)=='table' and args[1]=='verbose')
    end,false)
end
NEXM_INTERNAL.Modules.Diagnostics=Diagnostics
