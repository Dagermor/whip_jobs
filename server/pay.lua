-- es_jobs: pay. People on duty at a department or business are paid by rank every Config.Pay.intervalMinutes on duty,
-- out of that job's own bank account (BankSystemTransfer to their default account). An account that can't pay: the
-- paycheck is missed (not owed), they are told, and so are the leaders (once per 10 minutes per job). Every payment,
-- miss and income (fines, impound fees from es_mdt) goes in the ledger the Finances tab shows.
ESJ = ESJ or {}
local WC = exports.whip_core
local PAY = {}            -- [roleId] = amount (what a rank's Pay tab set)
local onMin = {}          -- ['charId:jobId'] = { m = on-duty minutes towards the next paycheck, seen } (memory only)
local warned = {}         -- [jobId] = GetGameTimer() of the last 'cannot pay' to leaders

function ESJ.loadPay()
    local rows = MySQL.query.await('SELECT `roleId`,`amount` FROM `es_jobs_pay`')
    if not rows then return false end
    PAY = {}
    for _, r in ipairs(rows) do PAY[r.roleId] = r.amount end
    return true
end

function ESJ.defaultPay(level)
    local P = Config.Pay or {}
    return math.min(P.maxPay or 5000, math.floor((P.base or 150) + (tonumber(level) or 0) * (P.perLevel or 3)))
end

--- { [roleId] = amount } of the ranks at this job with their own pay set
function ESJ.payTable(jobId)
    local out = {}
    for _, r in ipairs(WC:GetJobRoles(jobId) or {}) do if PAY[r.roleId] then out[r.roleId] = PAY[r.roleId] end end
    return out
end

function ESJ.payFor(roleId, level)
    return math.min((Config.Pay or {}).maxPay or 5000, PAY[roleId] or ESJ.defaultPay(level))
end

function ESJ.ledger(jobId, kind, amount, charId, note)
    MySQL.insert('INSERT INTO `es_jobs_ledger` (`jobId`,`kind`,`amount`,`charId`,`note`) VALUES (?,?,?,?,?)',
        { jobId, tostring(kind):sub(1, 16), math.floor(tonumber(amount) or 0), charId, note and tostring(note):sub(1, 120) or nil })
end

function ESJ.ledgerOf(jobId, n)
    local rows = MySQL.query.await([[SELECT `id`,`kind`,`amount`,`charId`,`note`,UNIX_TIMESTAMP(`at`) AS `at` FROM `es_jobs_ledger`
        WHERE `jobId` = ? ORDER BY `id` DESC LIMIT ?]], { jobId, math.min(200, tonumber(n) or 60) }) or {}
    local ids, seen = {}, {}
    for _, r in ipairs(rows) do if r.charId and not seen[r.charId] then seen[r.charId] = true ids[#ids + 1] = r.charId end end
    local names = (#ids > 0 and WC:GetCharacterNames(ids)) or {}
    for _, r in ipairs(rows) do r.who = r.charId and (names[r.charId] or ('#' .. r.charId)) or nil end
    return rows
end

--- paid out and taken in over the last 7 days
function ESJ.payWeek(jobId)
    local r = MySQL.single.await([[SELECT COALESCE(SUM(CASE WHEN `amount` < 0 THEN -`amount` ELSE 0 END),0) AS `out`,
        COALESCE(SUM(CASE WHEN `amount` > 0 AND `kind` <> 'open' THEN `amount` ELSE 0 END),0) AS `inn`,
        COALESCE(SUM(`kind` = 'pay_missed'),0) AS `missed`
        FROM `es_jobs_ledger` WHERE `jobId` = ? AND `at` > NOW() - INTERVAL 7 DAY]], { jobId }) or {}
    return { paid = tonumber(r.out) or 0, income = tonumber(r.inn) or 0, missed = tonumber(r.missed) or 0 }
end

local function cantPay(o, jobId, src, charId, amount, why)
    ESJ.ledger(jobId, 'pay_missed', 0, charId, ('$%d not paid: %s'):format(amount, why))
    WC:NotifyPlayer(src, ('%s could not pay you this time ($%d): its account is short. Your leaders have been told.'):format(o.short or o.name, amount), 'warning', 9000)
    if (Config.Pay or {}).bossNotice == false then return end
    local now = GetGameTimer()
    if warned[jobId] and now - warned[jobId] < 600000 then return end
    warned[jobId] = now
    local msg = ('%s\'s account could not pay a $%d paycheck. Put money in it (bank > business accounts) to keep paying your people.'):format(o.name, amount)
    ESJ.notifyLeaders(jobId, msg, 'error')
    for src2 in pairs(WC:GetPlayers({ light = true }) or {}) do
        src2 = tonumber(src2)
        if src2 and ESJ.isAdmin(src2) and not WC:GetPlayerRole(src2, jobId) then WC:NotifyPlayer(src2, '[Staff] ' .. msg, 'warning', 8000) end
    end
    print(('^3[es_jobs] %s (job %d) cannot pay: %s^7'):format(o.name, jobId, tostring(why)))
end

local function payOne(o, src, charId, info)
    local amount = ESJ.payFor(info.roleId, info.roleLevel)
    if amount <= 0 then return end
    local acct = ESJ.account(o.jobId)
    if not acct then return cantPay(o, o.jobId, src, charId, amount, 'it has no bank account') end
    if acct.frozen then return cantPay(o, o.jobId, src, charId, amount, 'its account is frozen') end
    if (tonumber(acct.balance) or 0) < amount then return cantPay(o, o.jobId, src, charId, amount, ('the balance is $%d'):format(acct.balance or 0)) end
    local mine = WC:GetDefaultBankAccount({ charId = charId })
    if not mine then return WC:NotifyPlayer(src, 'Your paycheck could not be paid: you have no bank account. Open one at a bank.', 'warning', 8000) end
    local ok, why = WC:BankSystemTransfer(acct.accountId, mine.accountId, amount, { reason = ('Pay: %s, %s'):format(o.short or o.name, info.roleName or 'rank') })
    if not ok then return cantPay(o, o.jobId, src, charId, amount, why or 'the bank refused') end
    ESJ.ledger(o.jobId, 'pay', -amount, charId, ('Paycheck (%s)'):format(info.roleName or 'rank'))
    WC:NotifyPlayer(src, ('Paycheck from %s: $%d'):format(o.short or o.name, amount), 'success', 6000)
end

--- one on-duty minute for everyone on duty at a department or business; a paycheck at the interval
function ESJ.payTick()
    local P = Config.Pay or {}
    if P.enabled == false then return end
    local every = math.max(1, math.floor(P.intervalMinutes or 15))
    local orgs = {}
    for _, o in ipairs(ESJ.orgs()) do orgs[o.jobId] = o end
    local now = os.time()
    for src, p in pairs(WC:GetPlayers({ light = true }) or {}) do
        src = tonumber(src)
        local cid = p.charId
        if src and cid then
            for jobId, info in pairs(WC:GetPlayerJobs(src) or {}) do
                local o = orgs[jobId]
                if o and info.clockedOn then
                    local k = cid .. ':' .. jobId
                    local c = onMin[k] or { m = 0 }
                    onMin[k] = c
                    c.m, c.seen = c.m + 1, now
                    if c.m >= every then
                        c.m = 0
                        CreateThread(function() payOne(o, src, cid, info) end)
                    end
                end
            end
        end
    end
    -- minutes carry over between shifts the same day; a counter nobody added to for 12 hours goes
    for k, c in pairs(onMin) do if now - (c.seen or 0) > 43200 then onMin[k] = nil end end
end

--- their minutes towards the next paycheck at that job (the duty prompt shows it)
function ESJ.payProgress(charId, jobId)
    return (onMin[charId .. ':' .. jobId] or {}).m or 0, math.max(1, math.floor((Config.Pay or {}).intervalMinutes or 15))
end

function ESJ.registerPay(cb)
    cb('es_jobs:pay:set', 400, function(source, d)
        local jobId, roleId = tonumber(d.jobId), tonumber(d.roleId)
        local o = jobId and ESJ.orgByJob(jobId)
        if not o then return false, 'No such department or business' end
        if not ESJ.canManage(source, jobId) then return false, 'Only its leaders can set pay' end
        local role
        for _, r in ipairs(WC:GetJobRoles(jobId) or {}) do if r.roleId == roleId then role = r end end
        if not role then return false, 'No such rank' end
        if d.amount == nil or d.amount == false or d.amount == '' then
            MySQL.update.await('DELETE FROM `es_jobs_pay` WHERE `roleId` = ?', { roleId })
            PAY[roleId] = nil
            return { amount = ESJ.defaultPay(role.level), default = true }
        end
        local amount = ESJ.int(d.amount, 0, nil)
        local max = (Config.Pay or {}).maxPay or 5000
        if not amount then return false, 'Pay is a number' end
        if amount > max then return false, ('The most a paycheck can be is $%d (/whip > Settings > Jobs)'):format(max) end
        MySQL.update.await('INSERT INTO `es_jobs_pay` (`roleId`,`jobId`,`amount`) VALUES (?,?,?) ON DUPLICATE KEY UPDATE `amount` = VALUES(`amount`)', { roleId, jobId, amount })
        PAY[roleId] = amount
        WC:LogActivity(source, 'es_jobs_pay', { detail = ('%s %s: $%d'):format(o.short or o.name, role.name, amount) })
        return { amount = amount }
    end)
end

-- es_mdt tells us when a fine, ticket or impound fee went into a department's account (the money already moved there:
-- this is only the Finances tab's record). Server-side only (a local event; players cannot send it).
AddEventHandler('es_mdt:server:deptIncome', function(jobId, amount, kind, note, charId)
    jobId, amount = tonumber(jobId), tonumber(amount)
    if not jobId or not amount or amount == 0 then return end
    ESJ.ledger(jobId, tostring(kind or 'income'), amount, tonumber(charId), note)
end)
