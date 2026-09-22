local Errors=NEXM_INTERNAL.Modules.Errors
local Validation=NEXM_INTERNAL.Modules.Validation
local Logger=NEXM_INTERNAL.Modules.Logger
local Framework=NEXM_INTERNAL.Managers.Framework
local Guard=NEXM_INTERNAL.Modules.SessionGuard
local Codes=NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Money={}
local infra={ [Codes.FRAMEWORK_UNAVAILABLE]=true,[Codes.ADAPTER_ERROR]=true,[Codes.INTEGRATION_ERROR]=true }
local function log(err) if err and infra[err.code] then Logger.Infrastructure(err,'money','nexm_core') end end
local function validateAccount(account)
    local ok,err=Validation.String(account,{name='account',nonEmpty=true,allowed={'cash','bank'}})
    if not ok then return nil,Errors.Create(Codes.UNSUPPORTED_ACCOUNT,'Unsupported canonical money account',{account=account}) end
    return account,nil
end
local function validateAmount(amount)
    local ok,err=Validation.Integer(amount,{name='amount',min=1,max=(Config.Security.MaxMoneyTransaction or 10000000)})
    if not ok then return nil,Errors.Create(Codes.INVALID_AMOUNT,'Invalid money amount',{actualType=type(amount),max=Config.Security.MaxMoneyTransaction}) end
    return amount,nil
end
local function validateReason(reason)
    local ok,err=Validation.String(reason,{name='reason',nonEmpty=true,min=1,max=(Config.Security.maxTransactionReasonLength or 128)})
    if not ok then return nil,err end
    if reason:find('[%c]') then return nil,Errors.Create(Codes.INVALID_ARGUMENT,'Transaction reason contains control characters') end
    return reason,nil
end
local function adapterFor(account)
    local adapter,err=Framework.RequireHealthy(); if not adapter then log(err); return nil,err end
    local caps=adapter.metadata.capabilities.money
    if not caps or caps[account]~=true then return nil,Errors.Create(Codes.UNSUPPORTED_ACCOUNT,'Selected framework does not support this money account',{account=account,framework=adapter.metadata.name}) end
    return adapter,nil
end
local function begin(source,account)
    local a,ae=validateAccount(account); if not a then return nil,nil,ae end
    local ctx,ce=Guard.Capture(source); if not ctx then log(ce); return nil,nil,ce end
    local adapter,fe=adapterFor(a); if not adapter then return nil,nil,fe end
    return ctx,adapter,nil
end
function Money.Get(source,account)
    local ctx,adapter,err=begin(source,account); if not ctx then return nil,err end
    local callOk,value,adapterErr=pcall(adapter.GetMoney,source,account)
    if not callOk then local e=Errors.Create(Codes.ADAPTER_ERROR,'Framework GetMoney threw',{account=account}); log(e); return nil,e end
    local still,stale=Guard.Validate(ctx); if not still then return nil,stale end
    if value==nil then log(adapterErr); return nil,adapterErr end
    if type(value)~='number' or not Validation.Finite(value) then local e=Errors.Create(Codes.ADAPTER_ERROR,'Framework returned invalid money balance',{account=account}); log(e); return nil,e end
    return value,nil
end
function Money.CanAfford(source,account,amount)
    local validAmount,amountErr=validateAmount(amount); if not validAmount then return false,amountErr end
    local value,err=Money.Get(source,account); if value==nil then return false,err end
    return value>=validAmount,nil
end
function Money.Add(source,account,amount,reason)
    local validAmount,amountErr=validateAmount(amount); if not validAmount then return false,amountErr end
    local validReason,reasonErr=validateReason(reason); if not validReason then return false,reasonErr end
    local ctx,adapter,err=begin(source,account); if not ctx then return false,err end
    local ok,preErr=Guard.Validate(ctx); if not ok then return false,preErr end
    local callOk,result,adapterErr=pcall(adapter.AddMoney,source,account,validAmount,validReason)
    if not callOk then local e=Errors.Create(Codes.ADAPTER_ERROR,'Framework AddMoney threw',{account=account}); log(e); return false,e end
    local still,stale=Guard.Validate(ctx); if not still then return false,stale end
    if result~=true then adapterErr=adapterErr or Errors.Create(Codes.INTEGRATION_ERROR,'Framework money addition failed',{account=account}); log(adapterErr); return false,adapterErr end
    return true,nil
end
function Money.Remove(source,account,amount,reason)
    local validAmount,amountErr=validateAmount(amount); if not validAmount then return false,amountErr end
    local validReason,reasonErr=validateReason(reason); if not validReason then return false,reasonErr end
    -- Capture the character session BEFORE the affordability read so an adapter
    -- that yields cannot let a later character on the same source inherit the
    -- remainder of this mutation workflow.
    local ctx,adapter,err=begin(source,account); if not ctx then return false,err end
    local callOk,balance,balanceErr=pcall(adapter.GetMoney,source,account)
    if not callOk then local e=Errors.Create(Codes.ADAPTER_ERROR,'Framework GetMoney threw during removal',{account=account}); log(e); return false,e end
    local current,stale=Guard.Validate(ctx); if not current then return false,stale end
    if balance==nil then log(balanceErr); return false,balanceErr end
    if type(balance)~='number' or not Validation.Finite(balance) then local e=Errors.Create(Codes.ADAPTER_ERROR,'Framework returned invalid money balance',{account=account}); log(e); return false,e end
    if balance<validAmount then return false,Errors.Create(Codes.INSUFFICIENT_FUNDS,'Insufficient funds',{account=account,required=validAmount,balance=balance}) end
    local ok,preErr=Guard.Validate(ctx); if not ok then return false,preErr end
    local callOk,result,adapterErr=pcall(adapter.RemoveMoney,source,account,validAmount,validReason)
    if not callOk then local e=Errors.Create(Codes.ADAPTER_ERROR,'Framework RemoveMoney threw',{account=account}); log(e); return false,e end
    local still,stale=Guard.Validate(ctx); if not still then return false,stale end
    if result~=true then
        adapterErr=adapterErr or Errors.Create(Codes.INTEGRATION_ERROR,'Framework money removal failed',{account=account})
        if adapterErr.code~=Codes.INSUFFICIENT_FUNDS then log(adapterErr) end
        return false,adapterErr
    end
    return true,nil
end
NEXM_INTERNAL.Modules.Money=Money
