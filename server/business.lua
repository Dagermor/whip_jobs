-- es_jobs: player-owned businesses (/business). Made like a department: a name, a short name, a colour and a logo with a
-- live preview; ranks with pay; a roster (hire people standing near, set rank, let go); its own business bank account;
-- stations placed with the same editor. WHIP keeps the job (EnsureJob with an owner), its roles, staff list and account;
-- we keep the name, colours and logo. An admin makes one for its owner; Config.Business.playerCreate lets players pay to start one.
ESJ = ESJ or {}
local WC = exports.whip_core
local LOGO_MAX = 400000            -- characters of a data URL (a 256 px webp is ~20-60 KB)
local CHUNK = 15000
local uploads = {}                 -- [source] = { id, total, parts }

local function log(source, what, detail)
    if source and source > 0 then CreateThread(function() WC:LogActivity(source, 'es_jobs_' .. what, { detail = detail }) end) end
end

function ESJ.loadBusinesses()
    local rows = MySQL.query.await('SELECT `id`,`jobId`,`name`,`short`,`color`,`blurb`,`logo`,`logoVer`,`ownerCharId`,`createdAt` FROM `es_jobs_businesses`')
    if not rows then return false end
    ESJ.Biz, ESJ.BizLogo = {}, {}
    for _, r in ipairs(rows) do
        ESJ.BizLogo[r.id] = r.logo
        r.logo = nil
        ESJ.Biz[r.id] = r
    end
    return true
end

local function bizOf(id) return ESJ.Biz[tonumber(id) or 0] end
local function by(source) if ESJ.isAdmin(source) then return nil end return { by = source } end
local function color(c) return type(c) == 'string' and c:match('^#%x%x%x%x%x%x$') and c or nil end

--- what this player may do at this business
function ESJ.bizRights(source, b)
    local admin = ESJ.isAdmin(source)
    local role = WC:GetPlayerRole(source, b.jobId)
    local function jp(p) return admin or (role ~= nil and WC:HasJobPermission(source, b.jobId, p) == true) end
    return { admin = admin, view = admin or role ~= nil, manage = jp('canManage'), hire = jp('canHire'), fire = jp('canFire'),
        promote = jp('canPromote') or jp('canDemote'), myLevel = role and role.level or nil,
        owner = b.ownerCharId ~= nil and WC:GetCharId(source) == b.ownerCharId }
end

local function changed(id)
    TriggerClientEvent('es_jobs:client:bizChanged', -1, id)
    if ESJ.onOrgsChanged then ESJ.onOrgsChanged() end
end

local function cleanBiz(d, needAll)
    d = type(d) == 'table' and d or {}
    local name, short = ESJ.trim(d.name):sub(1, 48), ESJ.trim(d.short):upper():sub(1, 12)
    if needAll or d.name ~= nil then if #name < 3 then return nil, 'The name needs 3 letters or more' end end
    if needAll or d.short ~= nil then if not short:match('^[%w&%-]+$') or #short < 2 then return nil, 'The short name is 2-12 letters, digits, & or -' end end
    return { name = name, short = short, color = color(d.color) or '#4f8ff7', blurb = ESJ.trim(d.blurb):sub(1, 200) }
end

--- the screen's list: businesses they own, work at or (admins) all; plus departments they lead (pay, money, stations)
function ESJ.bizList(source)
    local admin = ESJ.isAdmin(source)
    local mine = WC:GetPlayerJobs(source) or {}
    local out = {}
    for _, o in ipairs(ESJ.orgs()) do
        local member = mine[o.jobId]
        local manage = admin or (member and WC:HasJobPermission(source, o.jobId, 'canManage') == true)
        if (o.kind == 'biz' and (admin or member)) or (o.kind == 'dept' and manage) then
            o.manage = manage == true
            o.myRank = member and member.roleName or nil
            out[#out + 1] = o
        end
    end
    local owned = 0
    local cid = WC:GetCharId(source)
    for _, b in pairs(ESJ.Biz) do if b.ownerCharId == cid then owned = owned + 1 end end
    local B = Config.Business or {}
    return { list = out, admin = admin, canCreate = admin or (B.playerCreate == true and owned < (B.maxPerOwner or 2)),
        price = (not admin and B.playerCreate) and (B.createPrice or 0) or 0, charId = cid }
end

--- one business or department, as the screen shows it
function ESJ.orgDetail(source, jobId)
    local o = ESJ.orgByJob(jobId)
    if not o then return false, 'No such business or department' end
    local admin = ESJ.isAdmin(source)
    local role = WC:GetPlayerRole(source, o.jobId)
    local manage = ESJ.canManage(source, o.jobId)
    if not (admin or (o.kind == 'biz' and role) or manage) then return false, 'That is not yours to see' end
    local out = { org = o, manage = manage, admin = admin }
    if o.kind == 'biz' then
        local b = bizOf(o.id)
        out.biz = { id = b.id, name = b.name, short = b.short, color = b.color, blurb = b.blurb, ownerCharId = b.ownerCharId,
            ownerName = ESJ.nameOf(b.ownerCharId), logoVer = b.logoVer }
        out.rights = ESJ.bizRights(source, b)
    end
    local roles = WC:GetJobRoles(o.jobId) or {}
    table.sort(roles, function(a, c) return (a.level or 0) > (c.level or 0) end)
    local pay = ESJ.payTable(o.jobId)
    out.ranks = {}
    for _, r in ipairs(roles) do
        local p = r.permissions or {}
        out.ranks[#out.ranks + 1] = { roleId = r.roleId, name = r.name, level = r.level, pay = pay[r.roleId], payDefault = ESJ.defaultPay(r.level),
            perms = { canHire = p.canHire == true, canFire = p.canFire == true, canPromote = p.canPromote == true, canDemote = p.canDemote == true, canManage = p.canManage == true } }
    end
    if o.kind == 'biz' then
        local staff = WC:GetJobEmployees(o.jobId) or {}
        local ids = {}
        for _, e in pairs(staff) do ids[#ids + 1] = e.charId end
        local names = (#ids > 0 and WC:GetCharacterNames(ids)) or {}
        local online = {}
        for src, p in pairs(WC:GetPlayers({ light = true }) or {}) do if p.charId then online[p.charId] = tonumber(src) end end
        out.roster = {}
        for _, e in pairs(staff) do
            local src = online[e.charId]
            out.roster[#out.roster + 1] = { charId = e.charId, name = names[e.charId] or ('#' .. e.charId), roleId = e.roleId, roleName = e.roleName,
                level = e.roleLevel or 0, online = src ~= nil, onDuty = src ~= nil and WC:IsPlayerClockedOn(src, o.jobId) == true,
                owner = e.charId == out.biz.ownerCharId }
        end
        table.sort(out.roster, function(a, c) if a.level ~= c.level then return a.level > c.level end return a.name < c.name end)
    end
    if manage then
        local acct = ESJ.account(o.jobId)
        out.account = acct and { id = acct.accountId, number = acct.accountNumber, balance = acct.balance, frozen = acct.frozen == true or acct.frozen == 1 } or false
        out.ledger = ESJ.ledgerOf(o.jobId, 60)
        out.payInterval = (Config.Pay or {}).intervalMinutes or 15
        out.payOn = (Config.Pay or {}).enabled ~= false
        out.payWeek = ESJ.payWeek(o.jobId)
    end
    out.stations = ESJ.stationsOf and ESJ.stationsOf(o.jobId) or {}
    return out
end

local function newKey(short)
    local base = 'biz_' .. short:lower():gsub('[^%w]', ''):sub(1, 20)
    local key, n = base, 1
    while WC:GetJob(key) do n = n + 1 key = base .. n end
    return key
end

local function create(source, d)
    local admin = ESJ.isAdmin(source)
    local B = Config.Business or {}
    local info, why = cleanBiz(d, true)
    if not info then return false, why end
    for _, b in pairs(ESJ.Biz) do
        if b.name:lower() == info.name:lower() then return false, 'There is already a business with that name' end
        if b.short:lower() == info.short:lower() then return false, 'That short name is taken' end
    end
    local ownerCid
    if admin then
        local t = tonumber(d.owner)
        if t and t > 0 then
            ownerCid = WC:GetCharId(t)
            if not ownerCid then return false, 'Nobody with that id is in the city' end
        else ownerCid = WC:GetCharId(source) end
    else
        if not B.playerCreate then return false, 'Ask an admin to open your business' end
        ownerCid = WC:GetCharId(source)
        local owned = 0
        for _, b in pairs(ESJ.Biz) do if b.ownerCharId == ownerCid then owned = owned + 1 end end
        if owned >= (B.maxPerOwner or 2) then return false, ('You can own %d businesses at most'):format(B.maxPerOwner or 2) end
    end
    if not ownerCid then return false, 'No owner' end
    local receipt
    local price = (not admin) and math.floor(tonumber(B.createPrice) or 0) or 0
    if price > 0 then
        local w
        receipt, w = WC:ChargePlayer(source, price, { method = 'bank', reason = 'Business licence: ' .. info.name })
        if not receipt then return false, w or 'You cannot pay for the licence' end
    end
    local function undo(msg) if receipt then WC:RefundPlayer(receipt) end return false, msg end
    local roles = {}
    for _, r in ipairs(B.ranks or {}) do roles[#roles + 1] = { name = r.name, level = r.level, permissions = r.permissions or {} } end
    local key = newKey(info.short)
    local job, jwhy = WC:EnsureJob(key, { name = info.name, owner = { charId = ownerCid }, roles = roles, selfClockOn = true })
    if not job then return undo(jwhy or 'WHIP refused the job') end
    local logo = type(d.logo) == 'string' and #d.logo <= LOGO_MAX and d.logo:match('^data:image/[%w]+;base64,') and d.logo or nil
    local id = MySQL.insert.await([[INSERT INTO `es_jobs_businesses` (`jobId`,`name`,`short`,`color`,`blurb`,`logo`,`logoVer`,`ownerCharId`,`createdBy`)
        VALUES (?,?,?,?,?,?,?,?,?)]], { job.jobId, info.name, info.short, info.color, info.blurb, logo, logo and 1 or 0, ownerCid, WC:GetCharId(source) })
    if not id then WC:DeleteJob(job.jobId) return undo('Could not save that (database error)') end
    ESJ.Biz[id] = { id = id, jobId = job.jobId, name = info.name, short = info.short, color = info.color, blurb = info.blurb,
        logoVer = logo and 1 or 0, ownerCharId = ownerCid }
    ESJ.BizLogo[id] = logo
    -- the owner holds the top role (EnsureJob's owner); a business account for its money
    if not ESJ.account(job.jobId) then
        local acct, awhy = WC:CreateBankAccount({ charId = ownerCid }, info.name, { type = 'business', job = job.jobId })
        if not acct then print(('^3[es_jobs] %s: the business account could not be made: %s^7'):format(info.name, tostring(awhy))) end
    end
    local start = admin and math.floor(tonumber(B.startBalance) or 0) or 0
    local acct = ESJ.account(job.jobId)
    if start > 0 and acct then WC:BankSystemDeposit(acct.accountId, start, { reason = 'Opening balance' }) end
    ESJ.ledger(job.jobId, 'open', start, ownerCid, 'Business opened' .. (price > 0 and (' (licence $' .. price .. ')') or ''))
    log(source, 'biz_create', ('%s (%s) for #%d'):format(info.name, info.short, ownerCid))
    changed(id)
    return { id = id, jobId = job.jobId }
end

function ESJ.registerBusiness(cb)
    cb('es_jobs:biz:list', 300, function(source) return ESJ.bizList(source) end)
    cb('es_jobs:org:get', 250, function(source, d) return ESJ.orgDetail(source, tonumber(d.jobId)) end)
    cb('es_jobs:biz:create', 3000, function(source, d) return create(source, d) end)

    cb('es_jobs:biz:update', 800, function(source, d)
        local b = bizOf(d.id)
        if not b then return false, 'No such business' end
        local r = ESJ.bizRights(source, b)
        if not r.manage then return false, 'Only its managers can change it' end
        local info, why = cleanBiz(d, true)
        if not info then return false, why end
        for _, x in pairs(ESJ.Biz) do
            if x.id ~= b.id and (x.name:lower() == info.name:lower() or x.short:lower() == info.short:lower()) then return false, 'Another business has that name' end
        end
        MySQL.update.await('UPDATE `es_jobs_businesses` SET `name`=?,`short`=?,`color`=?,`blurb`=? WHERE `id`=?', { info.name, info.short, info.color, info.blurb, b.id })
        b.name, b.short, b.color, b.blurb = info.name, info.short, info.color, info.blurb
        WC:UpdateJob(b.jobId, { name = info.name })
        -- an admin may hand it to someone else (they must be in the city)
        if r.admin and tonumber(d.newOwner) then
            local cid = WC:GetCharId(tonumber(d.newOwner))
            if not cid then return false, 'Saved, but nobody with that id is in the city to take it over' end
            local ok, owhy = WC:UpdateJob(b.jobId, { owner = { charId = cid } })
            if not ok then return false, 'Saved, but the owner did not change: ' .. tostring(owhy) end
            MySQL.update.await('UPDATE `es_jobs_businesses` SET `ownerCharId`=? WHERE `id`=?', { cid, b.id })
            b.ownerCharId = cid
        end
        log(source, 'biz_update', b.name)
        changed(b.id)
        return true
    end)

    cb('es_jobs:biz:logoPart', 60, function(source, d)
        local b = bizOf(d.id)
        if not b then return false, 'No such business' end
        if not ESJ.bizRights(source, b).manage then return false, 'Only its managers can change the logo' end
        local i, total, part = tonumber(d.i), tonumber(d.total), d.part
        if not (i and total and total >= 1 and total <= math.ceil(LOGO_MAX / CHUNK) and i >= 1 and i <= total and type(part) == 'string' and #part <= CHUNK) then
            return false, 'That picture is too big'
        end
        local u = uploads[source]
        if i == 1 or not u or u.id ~= b.id or u.total ~= total then u = { id = b.id, total = total, parts = {} } uploads[source] = u end
        u.parts[i] = part
        if i < total then return { got = i } end
        local data = table.concat(u.parts)
        uploads[source] = nil
        if #data > LOGO_MAX or not data:match('^data:image/[%w]+;base64,[%w%+/=]+$') then return false, 'That is not a picture' end
        local ver = (b.logoVer or 0) + 1
        MySQL.update.await('UPDATE `es_jobs_businesses` SET `logo`=?,`logoVer`=? WHERE `id`=?', { data, ver, b.id })
        b.logoVer, ESJ.BizLogo[b.id] = ver, data
        changed(b.id)
        return { done = true, logoVer = ver }
    end, 40)

    cb('es_jobs:biz:logo', 50, function(_, d)
        local b = bizOf(d.id)
        local data = b and ESJ.BizLogo[b.id]
        if not data then return { total = 0, ver = b and b.logoVer or 0 } end
        local total = math.ceil(#data / CHUNK)
        local i = math.max(1, math.min(total, tonumber(d.i) or 1))
        return { total = total, ver = b.logoVer, part = data:sub((i - 1) * CHUNK + 1, i * CHUNK) }
    end, 40)

    cb('es_jobs:biz:rank', 500, function(source, d)
        local b = bizOf(d.id)
        if not b then return false, 'No such business' end
        if not ESJ.bizRights(source, b).manage then return false, 'Only its managers can change ranks' end
        local name = ESJ.trim(d.name):sub(1, 40)
        local level = ESJ.int(d.level, 1, 100)
        if #name < 2 then return false, 'A rank needs a name' end
        if not level then return false, 'A level is 1 to 100' end
        local p = type(d.perms) == 'table' and d.perms or {}
        local perms = { canHire = p.canHire == true, canFire = p.canFire == true, canPromote = p.canPromote == true,
            canDemote = p.canDemote == true, canManage = p.canManage == true }
        local roleId = tonumber(d.roleId) or 0
        if roleId == 0 then
            local role, why = WC:CreateJobRole(b.jobId, { name = name, level = level, permissions = perms }, by(source))
            if not role then return false, why end
            roleId = role.roleId
        else
            local ok, why = WC:UpdateJobRole(b.jobId, roleId, { name = name, level = level, permissions = perms }, by(source))
            if not ok then return false, why end
        end
        log(source, 'biz_rank', ('%s: %s (%d)'):format(b.short, name, level))
        changed(b.id)
        return roleId
    end)

    cb('es_jobs:biz:rankDelete', 800, function(source, d)
        local b = bizOf(d.id)
        if not b then return false, 'No such business' end
        if not ESJ.bizRights(source, b).manage then return false, 'Only its managers can change ranks' end
        local ok, why = WC:DeleteJobRole(b.jobId, tonumber(d.roleId) or 0, by(source))
        if not ok then return false, why end
        changed(b.id)
        return true
    end)

    --- people standing near them who could be hired (controller-friendly: pick from a list, no ids to type)
    cb('es_jobs:biz:nearby', 600, function(source, d)
        local b = bizOf(d.id)
        if not b then return false, 'No such business' end
        local ped = GetPlayerPed(source)
        if not ped or ped == 0 then return {} end
        local out = {}
        for _, s in ipairs(WC:GetPlayersInRange(GetEntityCoords(ped), 8.0) or {}) do
            if s ~= source then
                local cid = WC:GetCharId(s)
                if cid and not WC:GetPlayerRole(s, b.jobId) then out[#out + 1] = { source = s, name = WC:GetPlayerFullName(s) or ('#' .. s) } end
            end
        end
        return out
    end)

    cb('es_jobs:biz:hire', 800, function(source, d)
        local b = bizOf(d.id)
        if not b then return false, 'No such business' end
        local r = ESJ.bizRights(source, b)
        if not r.hire then return false, 'Your rank cannot hire' end
        local t = tonumber(d.target)
        if not t or not WC:GetCharId(t) then return false, 'They are not in the city' end
        if not r.admin then
            local a, c = GetPlayerPed(source), GetPlayerPed(t)
            if not (a and c and a ~= 0 and c ~= 0) or #(GetEntityCoords(a) - GetEntityCoords(c)) > 10.0 then return false, 'Stand next to them to hire them' end
        end
        local ok, why = WC:HirePlayer(t, b.jobId, tonumber(d.roleId), by(source))
        if not ok then return false, why end
        WC:NotifyPlayer(t, ('You now work at %s'):format(b.name), 'success', 8000)
        log(source, 'biz_hire', ('%s: #%s'):format(b.short, tostring(WC:GetCharId(t))))
        changed(b.id)
        return true
    end)

    cb('es_jobs:biz:setRank', 500, function(source, d)
        local b = bizOf(d.id)
        if not b then return false, 'No such business' end
        if not ESJ.bizRights(source, b).promote then return false, 'Your rank cannot promote or demote' end
        local cid = tonumber(d.charId)
        if cid == b.ownerCharId then return false, 'The owner keeps the top rank' end
        local ok, why = WC:SetPlayerRole({ charId = cid }, b.jobId, tonumber(d.roleId), by(source))
        if not ok then return false, why end
        changed(b.id)
        return true
    end)

    cb('es_jobs:biz:fire', 800, function(source, d)
        local b = bizOf(d.id)
        if not b then return false, 'No such business' end
        if not ESJ.bizRights(source, b).fire then return false, 'Your rank cannot let people go' end
        local cid = tonumber(d.charId)
        if cid == b.ownerCharId then return false, 'The owner cannot be let go' end
        local ok, why = WC:FirePlayer({ charId = cid }, b.jobId, by(source))
        if not ok then return false, why end
        log(source, 'biz_fire', ('%s: #%s'):format(b.short, tostring(cid)))
        changed(b.id)
        return true
    end)

    cb('es_jobs:biz:delete', 3000, function(source, d)
        local b = bizOf(d.id)
        if not b then return false, 'No such business' end
        if not ESJ.isAdmin(source) then return false, 'Only an admin can close a business' end
        local acct = ESJ.account(b.jobId)
        if acct and (tonumber(acct.balance) or 0) > 0 then return false, ('Its account still holds $%d: move it out first'):format(acct.balance) end
        local ok, why = WC:DeleteJob(b.jobId)
        if not ok then return false, why end
        MySQL.update.await('DELETE FROM `es_jobs_businesses` WHERE `id` = ?', { b.id })
        ESJ.Biz[b.id], ESJ.BizLogo[b.id] = nil, nil
        log(source, 'biz_delete', b.name)
        changed(b.id)
        return true
    end)
end
