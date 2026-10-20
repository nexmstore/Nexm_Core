-- Offline coroutine harness for server/database.lua callback -> promise -> Await.
local total, failed = 0, 0
local function expect(name, condition)
    total = total + 1
    if condition then print('[PASS] '..name) else failed = failed + 1; print('[FAIL] '..name) end
end

Config = { Debug = false, Database = { healthQuery = 'SELECT 1' } }
GetResourceState = function() return 'started' end

local Codes = { DATABASE_ERROR='DATABASE_ERROR', DATABASE_INVALID_PARAMS='DATABASE_INVALID_PARAMS', INVALID_ARGUMENT='INVALID_ARGUMENT', DATABASE_UNAVAILABLE='DATABASE_UNAVAILABLE' }
local Errors = {}
function Errors.Create(code, message, context) return { code=code, message=message, context=context or {} } end
local Validation = {}
function Validation.String(v) if type(v)=='string' and #v>0 then return true,nil end return false,Errors.Create('INVALID_ARGUMENT','bad sql') end
function Validation.Table(v, opts)
    if type(v)~='table' then return false,Errors.Create('INVALID_ARGUMENT','bad table') end
    local n=0; for _ in pairs(v) do n=n+1 end
    if opts and opts.minEntries and n<opts.minEntries then return false,Errors.Create('INVALID_ARGUMENT','small') end
    return true,nil
end
local Logger = {}
for _,n in ipairs({'Infrastructure','Debug'}) do Logger[n]=function() end end
local State = { SetComponent=function() end }
local Ownership = { Resolve=function() return 'nexm_test' end }

NEXM_INTERNAL={Modules={Errors=Errors,Validation=Validation,Logger=Logger,State=State,Ownership=Ownership,Constants={ERROR_CODES=Codes,HEALTH={FAILED='FAILED',HEALTHY='HEALTHY'}}}}

local pendingCallback
MySQL={}
for _,name in ipairs({'query','single','scalar','insert','update'}) do
    MySQL[name]=function(sql, params, cb) pendingCallback=cb end
end
MySQL.transaction=function(queries, params, cb) pendingCallback=cb end

promise={}
function promise.new()
    local p={resolved=false,value=nil}
    function p:resolve(v) self.resolved=true; self.value=v end
    return p
end
Citizen={}
function Citizen.Await(p)
    if not p.resolved then coroutine.yield({kind='await',promise=p}) end
    return p.value
end

dofile('server/database.lua')
local DB=NEXM_INTERNAL.Modules.DB

local function start(fn)
    pendingCallback=nil
    local co=coroutine.create(fn)
    local ok, req=coroutine.resume(co)
    return co,ok,req
end

-- success callback resumes direct Await without a protected Await frame.
do
    local co,ok,req=start(function() return DB.Query('SELECT 1', {}, 'nexm_test') end)
    local suspended=ok and coroutine.status(co)=='suspended' and req.kind=='await' and type(pendingCallback)=='function'
    pendingCallback({{value=1}}, nil)
    local ok2,result,err=coroutine.resume(co)
    expect('DB async callback success', suspended and ok2 and coroutine.status(co)=='dead' and type(result)=='table' and err==nil)
end

-- SQL callback error returns a structured NEXM DATABASE_ERROR, not success.
do
    local co,ok,req=start(function() return DB.Query('SELECT broken', {}, 'nexm_test') end)
    local suspended=ok and coroutine.status(co)=='suspended' and req.kind=='await'
    pendingCallback(nil, 'forced sql error')
    local ok2,result,err=coroutine.resume(co)
    expect('DB async callback failure is structured', suspended and ok2 and coroutine.status(co)=='dead' and result==nil and type(err)=='table' and err.code=='DATABASE_ERROR')
end

print(('RESULT tests=%d pass=%d fail=%d'):format(total,total-failed,failed))
if failed>0 then os.exit(1) end
