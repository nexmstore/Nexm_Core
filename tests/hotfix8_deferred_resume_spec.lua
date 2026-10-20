-- Models the critical hotfix.8 invariant: oxmysql callback must return before
-- the awaiting coroutine is resumed.
local total, failed = 0, 0
local function expect(name, condition)
    total = total + 1
    if condition then print('[PASS] '..name) else failed = failed + 1; print('[FAIL] '..name) end
end

local timers = {}
function SetTimeout(ms, fn) timers[#timers+1] = fn end
local function runTimers()
    local q=timers; timers={}
    for _,fn in ipairs(q) do fn() end
end

Config = { Debug = false, Database = { healthQuery = 'SELECT 1' } }
GetResourceState = function() return 'started' end
local Codes={DATABASE_ERROR='DATABASE_ERROR',DATABASE_INVALID_PARAMS='DATABASE_INVALID_PARAMS',INVALID_ARGUMENT='INVALID_ARGUMENT',DATABASE_UNAVAILABLE='DATABASE_UNAVAILABLE'}
local Errors={}
function Errors.Create(code,message,context) return {code=code,message=message,context=context or {}} end
local Validation={}
function Validation.String(v) if type(v)=='string' and #v>0 then return true,nil end return false,Errors.Create('INVALID_ARGUMENT','bad sql') end
function Validation.Table(v,opts) if type(v)~='table' then return false,Errors.Create('INVALID_ARGUMENT','bad table') end local n=0 for _ in pairs(v) do n=n+1 end if opts and opts.minEntries and n<opts.minEntries then return false,Errors.Create('INVALID_ARGUMENT','small') end return true,nil end
local Logger={Infrastructure=function() end,Debug=function() end}
local State={SetComponent=function() end}
local Ownership={Resolve=function() return 'nexm_test' end}
NEXM_INTERNAL={Modules={Errors=Errors,Validation=Validation,Logger=Logger,State=State,Ownership=Ownership,Constants={ERROR_CODES=Codes,HEALTH={FAILED='FAILED',HEALTHY='HEALTHY'}}}}

local pendingCallback
MySQL={}
for _,name in ipairs({'query','single','scalar','insert','update'}) do
    MySQL[name]=function(sql,params,cb) pendingCallback=cb end
end
MySQL.transaction=function(q,p,cb) pendingCallback=cb end

promise={}
function promise.new()
    local p={resolved=false,value=nil,waiter=nil}
    function p:resolve(v)
        self.resolved=true; self.value=v
        if self.waiter and coroutine.status(self.waiter)=='suspended' then
            local co=self.waiter; self.waiter=nil
            local ok,err=coroutine.resume(co)
            if not ok then error(err) end
        end
    end
    return p
end
Citizen={}
function Citizen.Await(p)
    if not p.resolved then p.waiter=coroutine.running(); coroutine.yield() end
    return p.value
end
CreateThread=function(fn) local co=coroutine.create(fn); assert(coroutine.resume(co)); return co end
Wait=function() coroutine.yield() end

dofile('server/database.lua')
local DB=NEXM_INTERNAL.Modules.DB

local afterQuery=false
local co=coroutine.create(function()
    local rows,err=DB.Query('SELECT 1',{},'nexm_test')
    assert(err==nil and type(rows)=='table')
    afterQuery=true
end)
assert(coroutine.resume(co))
expect('query coroutine waits for callback', coroutine.status(co)=='suspended' and type(pendingCallback)=='function')

local callbackReturned=false
pendingCallback({{ok=1}},nil)
callbackReturned=true
expect('oxmysql callback returns before awaiting continuation resumes', callbackReturned and afterQuery==false and coroutine.status(co)=='suspended')
runTimers()
expect('continuation resumes on deferred tick', afterQuery==true and coroutine.status(co)=='dead')

print(('RESULT tests=%d pass=%d fail=%d'):format(total,total-failed,failed))
if failed>0 then os.exit(1) end
