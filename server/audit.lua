local SafeData = NEXM_INTERNAL.Modules.SafeData
local Validation = NEXM_INTERNAL.Modules.Validation
local Errors = NEXM_INTERNAL.Modules.Errors
local Logger = NEXM_INTERNAL.Modules.Logger
local DB = NEXM_INTERNAL.Modules.InternalDB or NEXM_INTERNAL.Modules.DB
local Player = NEXM_INTERNAL.Modules.Player
local State = NEXM_INTERNAL.Modules.State
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Health = NEXM_INTERNAL.Modules.Constants.HEALTH

local Audit = {}
local queue, scheduled, metrics = {}, false, { accepted=0, processed=0, dropped=0, retries=0, failures=0 }
local nextId = 0
local backendState = { console='DISABLED', database='DISABLED', discord='DISABLED', custom='DISABLED' }
local severities = { debug=true, info=true, warning=true, error=true, critical=true }

local function cfg() return Config and Config.Audit or {} end
local function queueCfg() return cfg().Queue or {} end
local function nowIso() return os.date('!%Y-%m-%dT%H:%M:%SZ') end

local function refreshComponentState()
    if not cfg().Enabled then State.SetComponent('audit', Health.DISABLED); return end
    local backends = cfg().Backends or {}
    local degraded = false
    for name, enabled in pairs(backends) do
        if enabled == true and backendState[name] ~= 'HEALTHY' then degraded = true; break end
    end
    State.SetComponent('audit', degraded and Health.DEGRADED or Health.HEALTHY, {
        backends = backendState,
        retentionDays = cfg().RetentionDays or 0
    })
end

local function safeJson(value)
    local ok, encoded = pcall(function() return json.encode(value) end)
    return ok and encoded or '{}'
end

local function cloneEntry(entry)
    local copied = SafeData.ForLog(entry,{maxDepth=10,maxEntries=512,maxTotalNodes=1024,maxStringLength=4096})
    return copied
end

local function enqueue(job)
    local maxSize = queueCfg().maxSize or 256
    if #queue >= maxSize then
        local policy = queueCfg().dropPolicy or 'oldest'
        if policy == 'newest' then
            metrics.dropped = metrics.dropped + 1
            Logger.Warn('Audit queue full; dropping newest entry',{component='audit',backend=job.backend},'nexm_core')
            return false
        end
        table.remove(queue,1)
        metrics.dropped = metrics.dropped + 1
        Logger.Warn('Audit queue full; dropping oldest entry',{component='audit',backend=job.backend},'nexm_core')
    end
    queue[#queue+1]=job
    return true
end

local function retry(job, detail)
    local limit = queueCfg().retryLimit or 2
    if job.attempt >= limit then
        metrics.failures=metrics.failures+1
        Logger.Warn('Audit backend retry exhausted',{component='audit',backend=job.backend,attempt=job.attempt,detail=detail},'nexm_core')
        return
    end
    job.attempt=job.attempt+1; metrics.retries=metrics.retries+1
    local delay=(queueCfg().retryBackoffMs or 1000) * job.attempt
    SetTimeout(delay,function() enqueue(job); Audit.Schedule() end)
end

local function ensureDatabaseTable()
    local _,err=DB.Query([[
        CREATE TABLE IF NOT EXISTS `nexm_audit_log` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `resource` VARCHAR(128) NOT NULL,
            `action` VARCHAR(128) NOT NULL,
            `actor_identifier` VARCHAR(256) NULL,
            `subject_identifier` VARCHAR(256) NULL,
            `severity` VARCHAR(16) NOT NULL,
            `data_json` LONGTEXT NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `idx_nexm_audit_resource` (`resource`),
            INDEX `idx_nexm_audit_action` (`action`),
            INDEX `idx_nexm_audit_created_at` (`created_at`),
            INDEX `idx_nexm_audit_actor` (`actor_identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],{},'nexm_core')
    if err then backendState.database='UNAVAILABLE'; refreshComponentState(); return false,err end
    backendState.database='HEALTHY'; refreshComponentState(); return true,nil
end

local function processDatabase(job)
    if backendState.database~='HEALTHY' then local ok,err=ensureDatabaseTable(); if not ok then retry(job,err and err.code or 'database unavailable'); return false end end
    local e=job.entry
    local _,err=DB.Insert([[INSERT INTO `nexm_audit_log`
        (`resource`,`action`,`actor_identifier`,`subject_identifier`,`severity`,`data_json`,`created_at`)
        VALUES (?,?,?,?,?,?,CURRENT_TIMESTAMP)]],{
        e.ownerResource,e.action,e.actorCharacter,e.subject,e.severity,safeJson(e.data or {})
    },'nexm_core')
    if err then backendState.database='UNAVAILABLE'; refreshComponentState(); retry(job,err.code); return false end
    backendState.database='HEALTHY'; refreshComponentState(); return true
end

local function webhookPayload(entry)
    local dataSummary=safeJson(SafeData.ForLog(entry.data or {},{maxDepth=4,maxEntries=32,maxTotalNodes=96,maxStringLength=512}))
    if #dataSummary>1500 then dataSummary=dataSummary:sub(1,1500)..'...' end
    local includeIds = cfg().DiscordIncludeIdentifiers == true
    local actor = entry.actorType=='system' and 'System' or (entry.actorName or 'Player')
    if includeIds and entry.actorCharacter then actor = actor .. ' [' .. entry.actorCharacter .. ']' end
    local subject = includeIds and (entry.subject or '-') or (entry.subject and '<identifier omitted>' or '-')
    return {
        username='NEXM Audit',
        embeds={{
            title=entry.action,
            description=('Resource: %s\nActor: %s\nSubject: %s\nSeverity: %s\nData: %s'):format(
                entry.ownerResource,actor,subject,entry.severity,dataSummary),
            footer={text='NEXM Core Audit'}
        }}
    }
end

local function processDiscord(job)
    local webhook=cfg().DiscordWebhook
    if type(webhook)~='string' or webhook=='' or not PerformHttpRequest then retry(job,'webhook unavailable'); return false end
    local ok,err=pcall(function()
        PerformHttpRequest(webhook,function(status)
            if type(status)~='number' or status<200 or status>=300 then
                backendState.discord='UNAVAILABLE'; refreshComponentState(); retry(job,'http:'..tostring(status))
            else
                backendState.discord='HEALTHY'; refreshComponentState(); metrics.processed=metrics.processed+1
            end
        end,'POST',safeJson(webhookPayload(job.entry)),{['Content-Type']='application/json'})
    end)
    if not ok then backendState.discord='UNAVAILABLE'; refreshComponentState(); retry(job,tostring(err)); return false end
    return nil -- asynchronous completion updates metrics in the HTTP callback
end

local function processCustom(job)
    if not NEXM_CUSTOM_AUDIT_BACKEND or type(NEXM_CUSTOM_AUDIT_BACKEND.Send)~='function' then retry(job,'custom backend missing'); return false end
    local ok,result,err=pcall(NEXM_CUSTOM_AUDIT_BACKEND.Send,cloneEntry(job.entry))
    if not ok or result~=true then backendState.custom='UNAVAILABLE'; refreshComponentState(); retry(job,tostring(err or result)); return false end
    backendState.custom='HEALTHY'; refreshComponentState(); return true
end

local function process(job)
    if job.backend=='database' then return processDatabase(job) end
    if job.backend=='discord' then return processDiscord(job) end
    if job.backend=='custom' then return processCustom(job) end
    return true
end

function Audit.FlushBatch()
    scheduled=false
    local batch=queueCfg().batchSize or 16
    local n=math.min(batch,#queue)
    for _=1,n do
        local job=table.remove(queue,1)
        local ok=process(job)
        if ok == true then metrics.processed=metrics.processed+1 end
    end
    if #queue>0 then Audit.Schedule() end
end

function Audit.Schedule()
    if scheduled or #queue==0 then return end
    scheduled=true
    SetTimeout(0,Audit.FlushBatch)
end

local function normalize(definition,owner)
    if type(definition)~='table' then return nil,Errors.Create(Codes.INVALID_ARGUMENT,'Audit entry must be a table') end
    local ok,err=Validation.String(definition.action,{name='audit action',nonEmpty=true,min=1,max=cfg().MaxActionLength or 128,pattern='^[%a_][%w_%.:%-]*$'}); if not ok then return nil,err end
    local severity=definition.severity or 'info'
    if type(severity)~='string' or not severities[severity] then return nil,Errors.Create(Codes.INVALID_ARGUMENT,'Invalid audit severity',{severity=severity}) end
    local actorSource=nil; local actorCharacter=nil; local actorName=nil; local actorType='system'
    if definition.actor~=nil then
        ok,err=Validation.Source(definition.actor,{name='audit actor'}); if not ok then return nil,err end
        actorSource=definition.actor; actorType='player'
        local snapshot,playerErr=Player.Get(actorSource)
        if snapshot then actorCharacter=snapshot.identity and snapshot.identity.character or nil; actorName=snapshot.name end
        if not snapshot and playerErr and playerErr.code~=Codes.FRAMEWORK_UNAVAILABLE then return nil,playerErr end
    end
    local subject=definition.subject
    if subject~=nil then
        ok,err=Validation.String(subject,{name='audit subject',nonEmpty=true,max=cfg().MaxSubjectLength or 256}); if not ok then return nil,err end
    end
    local data=definition.data or {}
    local copied,copyErr=SafeData.Copy(data,{
        field='audit data', maxDepth=cfg().MaxDataDepth or 8,maxEntries=cfg().MaxDataEntries or 256,
        maxTotalNodes=cfg().MaxDataNodes or 768,maxStringLength=cfg().MaxDataStringLength or 4096,maxKeyLength=128
    }); if copyErr then return nil,copyErr end
    nextId=nextId+1
    return {
        id=nextId,timestamp=nowIso(),ownerResource=owner,action=definition.action,severity=severity,
        actorType=actorType,actorSource=actorSource,actorCharacter=actorCharacter,actorName=actorName,
        subject=subject,data=copied
    },nil
end

function Audit.Log(definition,ownerResource)
    if not cfg().Enabled then return false,Errors.Create(Codes.AUDIT_DISABLED,'Audit is disabled') end
    local entry,err=normalize(definition,ownerResource or 'nexm_core'); if not entry then return false,err end
    metrics.accepted=metrics.accepted+1
    local backends=cfg().Backends or {}
    if backends.console then Logger.Info('AUDIT '..entry.action,{component='audit',entry=entry},entry.ownerResource) end
    local enqueued=0
    for _,backend in ipairs({'database','discord','custom'}) do
        if backends[backend] then if enqueue({backend=backend,entry=entry,attempt=0}) then enqueued=enqueued+1 end end
    end
    if enqueued>0 then Audit.Schedule() end
    return true,nil
end

function Audit.Initialize()
    if not cfg().Enabled then State.SetComponent('audit',Health.DISABLED); return true,nil end
    local backends=cfg().Backends or {}
    local enabled={}; local degraded=false
    for name,value in pairs(backends) do
        if value==true then enabled[#enabled+1]=name; backendState[name]='HEALTHY' else backendState[name]='DISABLED' end
    end
    if backends.database then local ok=ensureDatabaseTable(); if not ok then degraded=true end end
    if backends.discord and (type(cfg().DiscordWebhook)~='string' or cfg().DiscordWebhook=='') then backendState.discord='UNAVAILABLE'; degraded=true end
    if backends.custom and (not NEXM_CUSTOM_AUDIT_BACKEND or type(NEXM_CUSTOM_AUDIT_BACKEND.Send)~='function') then backendState.custom='UNAVAILABLE'; degraded=true end
    refreshComponentState()
    return true,nil
end
function Audit.GetQueueDepth() return #queue end
function Audit.GetMetrics() local out={}; for k,v in pairs(metrics) do out[k]=v end; out.backends={}; for k,v in pairs(backendState) do out.backends[k]=v end; return out end
function Audit.ResetForTests() queue={}; scheduled=false; metrics={accepted=0,processed=0,dropped=0,retries=0,failures=0}; nextId=0; backendState={console='DISABLED',database='DISABLED',discord='DISABLED',custom='DISABLED'} end

NEXM_INTERNAL.Modules.Audit=Audit
