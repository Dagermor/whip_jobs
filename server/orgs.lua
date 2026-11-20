-- whip_jobs: organisations. A department (es_mdt's /departments) or a business (ours, /business). Both are WHIP jobs, so
-- everything here is keyed by jobId: stations list jobIds, pay is per WHIP role, money goes to the job's bank account.
-- es_mdt is optional: without it there are only businesses (and the stations keep any department they listed, unused).
ESJ = ESJ or {}
local WC = exports.whip_core

ESJ.Biz = ESJ.Biz or {}        -- [id] = business row (no logo)
ESJ.BizLogo = ESJ.BizLogo or {}

local deptCache, deptAt = nil, 0
local function mdtOn() return GetResourceState('es_mdt') == 'started' end

--- es_mdt's departments, kept 15 s (dropped at once when es_mdt says one changed)
function ESJ.departments()
    if not mdtOn() then return {} end
    if deptCache and GetGameTimer() - deptAt < 15000 then return deptCache end
    local ok, list = pcall(function() return exports.es_mdt:GetDepartments() end)
    deptCache, deptAt = (ok and type(list) == 'table') and list or {}, GetGameTimer()
    return deptCache
end
AddEventHandler('es_departments:server:changed', function() deptCache = nil if ESJ.onOrgsChanged then ESJ.onOrgsChanged() end end)
AddEventHandler('onResourceStart', function(r) if r == 'es_mdt' then deptCache = nil if ESJ.onOrgsChanged then SetTimeout(3000, ESJ.onOrgsChanged) end end end)
AddEventHandler('onResourceStop', function(r) if r == 'es_mdt' then deptCache = nil end end)

--- the ped a new spot gets for a department (by type, then its name) or a business
function ESJ.defaultPed(org)
    local P = (Config.Stations or {}).peds or {}
    if not org then return P.none or 's_m_m_security_01' end
    if org.kind == 'biz' then return (Config.Business or {}).ped or 'a_m_y_business_01' end
    local n = ((org.short or '') .. ' ' .. (org.name or '')):lower()
    if org.type == 'ems' and (n:find('fire') or n:find('%f[%w]fd%f[%W]')) then return P.fire or 's_m_y_fireman_01' end
    if org.type == 'state' and (n:find('ranger') or n:find('park') or n:find('wildlife')) then return P.ranger or 's_m_y_ranger_01' end
    return P[org.type] or P.none or 's_m_m_security_01'
end

--- 0.4.0: the spot types that have their own default ped (the DOJ's), by type key
function ESJ.typePeds()
    local P, out = (Config.Stations or {}).peds or {}, {}
    for _, t in ipairs(ESJ.TYPES) do if t.pedKey and P[t.pedKey] then out[t.key] = P[t.pedKey] end end
    return out
end

--- every organisation, departments first: { jobId, kind, id, short, name, type, color, logoVer }
function ESJ.orgs()
    local out = {}
    for _, d in ipairs(ESJ.departments()) do
        out[#out + 1] = { jobId = d.jobId, kind = 'dept', id = d.id, short = d.short, name = d.name, type = d.type,
            color = d.color1, logoVer = d.logoVer or 0, key = d.key }
    end
    local biz = {}
    for _, b in pairs(ESJ.Biz) do biz[#biz + 1] = b end
    table.sort(biz, function(a, b) return a.id < b.id end)
    for _, b in ipairs(biz) do
        out[#out + 1] = { jobId = b.jobId, kind = 'biz', id = b.id, short = b.short, name = b.name, type = 'business',
            color = b.color, logoVer = b.logoVer or 0, ownerCharId = b.ownerCharId }
    end
    for _, o in ipairs(out) do o.ped = ESJ.defaultPed(o) end
    return out
end

function ESJ.orgByJob(jobId)
    jobId = tonumber(jobId)
    if not jobId then return nil end
    for _, o in ipairs(ESJ.orgs()) do if o.jobId == jobId then return o end end
    return nil
end

function ESJ.isAdmin(source)
    if not source or source <= 0 then return false end
    if WC:HasDevTools(source) == true or IsPlayerAceAllowed(source, Config.AdminAce or 'whip_jobs.admin')
        or IsPlayerAceAllowed(source, 'es_jobs.admin') then return true end   -- 0.5.0: the ace from before the rename still works
    if mdtOn() then
        local ok, staff = pcall(function() return exports.es_mdt:IsStaff(source) end)
        if ok and staff == true then return true end
    end
    return false
end

--- their role at a job: { roleId, name, level } or nil, and whether they are on duty there
function ESJ.roleAt(source, jobId)
    local role = WC:GetPlayerRole(source, jobId)
    if not role then return nil, false end
    return role, WC:IsPlayerClockedOn(source, jobId) == true
end

--- may they manage this job (its business, pay, outfits)? admins always; else WHIP's canManage there
function ESJ.canManage(source, jobId)
    if ESJ.isAdmin(source) then return true end
    return WC:HasJobPermission(source, jobId, 'canManage') == true
end

--- of these jobIds, the ones they belong to: { [jobId] = { role, onDuty } }
function ESJ.membership(source, jobIds)
    local out, any = {}, false
    local mine = WC:GetPlayerJobs(source) or {}
    for _, jid in ipairs(jobIds or {}) do
        local j = mine[jid]
        if j then
            out[jid] = { role = { roleId = j.roleId, name = j.roleName, level = j.roleLevel or 0 }, onDuty = j.clockedOn == true }
            any = true
        end
    end
    return out, any
end

--- the job's (first, open) bank account, or nil
function ESJ.account(jobId)
    local list = WC:GetJobBankAccounts(jobId) or {}
    for _, a in ipairs(list) do if not a.closedAt then return a end end
    return list[1]
end

function ESJ.nameOf(charId)
    if not charId then return nil end
    local ok, n = pcall(function() return WC:GetCharacterNames({ charId }) end)
    if ok and type(n) == 'table' and n[charId] then
        local v = n[charId]
        return type(v) == 'table' and (v.name or ((v.firstName or '') .. ' ' .. (v.lastName or ''))) or tostring(v)
    end
    return ('#%d'):format(charId)
end

function ESJ.notifyLeaders(jobId, text, kind)
    local roles = WC:GetJobRoles(jobId) or {}
    local top = 0
    for _, r in ipairs(roles) do if (r.level or 0) > top then top = r.level end end
    for src, p in pairs(WC:GetPlayers({ light = true }) or {}) do
        src = tonumber(src)
        local role = src and WC:GetPlayerRole(src, jobId)
        if role and ((role.level or 0) >= top or WC:HasJobPermission(src, jobId, 'canManage') == true) then
            WC:NotifyPlayer(src, text, kind or 'warning', 10000)
        end
    end
end
