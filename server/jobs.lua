local Player = NEXM_INTERNAL.Modules.Player
local Framework = NEXM_INTERNAL.Managers.Framework
local Validation = NEXM_INTERNAL.Modules.Validation
local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local Jobs = {}
local function validateJobName(name)
    return Validation.String(name, { name = 'job name', nonEmpty = true, min = 1, max = 128, pattern = '^[%w%._%-]+$' })
end
function Jobs.Get(source) return Player.GetJob(source) end
function Jobs.Has(source, jobName)
    local ok, err = validateJobName(jobName); if not ok then return false, err end
    local job, jobErr = Player.GetJob(source); if not job then return false, jobErr end
    return job.name == jobName, nil
end
function Jobs.HasAny(source, jobs)
    local ok, err = Validation.Table(jobs, { name = 'jobs', minEntries = 1, maxEntries = 128 })
    if not ok then return false, err end
    local job, jobErr = Player.GetJob(source); if not job then return false, jobErr end
    for _, name in ipairs(jobs) do
        local valid, nameErr = validateJobName(name); if not valid then return false, nameErr end
        if job.name == name then return true, nil end
    end
    return false, nil
end
function Jobs.MinimumGrade(source, jobName, grade)
    local ok, err = validateJobName(jobName); if not ok then return false, err end
    ok, err = Validation.Integer(grade, { name = 'job grade', min = 0, max = 100000 })
    if not ok then return false, err end
    local job, jobErr = Player.GetJob(source); if not job then return false, jobErr end
    return job.name == jobName and job.grade >= grade, nil
end
function Jobs.IsOnDuty(source)
    local caps = Framework.GetCapabilities() or {}
    if not (caps.player and caps.player.duty == true) then
        return nil, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'Active framework does not expose duty semantics', {
            feature = 'player.duty', framework = Framework.GetName()
        })
    end
    local job, err = Player.GetJob(source); if not job then return nil, err end
    if type(job.onDuty) ~= 'boolean' then
        return nil, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'Active framework did not provide a usable duty value', {
            feature = 'player.duty', framework = Framework.GetName()
        })
    end
    return job.onDuty, nil
end
NEXM_INTERNAL.Modules.Jobs = Jobs
