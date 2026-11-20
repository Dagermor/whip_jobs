-- whip_jobs 0.3.0: EMS. Wounded and down, the calls (es_mdt), first aid, EMS treatment, the hospital desk, medical
-- records and bills.
--
-- Dying (WHIP's own death) first makes a player WOUNDED: WHIP revives them where they fell, and their own game keeps
-- them on the ground (crawl only) with a timer. They call EMS themselves, or the call goes out on its own. Someone with
-- a first aid kit helps them up; EMS treat them. The timer running out, or more damage, kills them again: DOWN. Down is
-- WHIP's own death screen with its respawn timer; the call is upgraded in place (the same es_mdt call, now P1) and the
-- respawn is held (HoldRespawn) while EMS units are on that call. A medic revives them, or they respawn (billed).
-- Every treatment is a medical record; what the patient owes is paid to the EMS department's own account.
ESJ = ESJ or {}
local WC = exports.whip_core
local Hurt = {}          -- [src] = { state = 'wounded'|'down', charId, name, since, untilAt, autoAt, headshot, cause, callId, ... }
local Info = {}          -- [src] = { headshot, cause, street, at }: what their own game said about the killing blow
local DeskCalls = {}     -- [charId] = os.time() of the last "patient at the desk" call
local function E() return Config.EMS or {} end
local function on() return E().enabled ~= false end
local function mdtOn() return GetResourceState('es_mdt') == 'started' end
local function now() return os.time() end

--- the EMS jobs: es_mdt departments of an EMS type, and Config.EMS.jobs
function ESJ.emsJobs()
    local out, seen = {}, {}
    for _, o in ipairs(ESJ.orgs()) do
        if o.kind == 'dept' and (E().types or {})[o.type] then out[#out + 1] = o.jobId seen[o.jobId] = true end
    end
    for _, j in ipairs(E().jobs or {}) do
        local job = WC:GetJob(j)
        local id = type(job) == 'table' and job.jobId or tonumber(j)
        if id and not seen[id] then out[#out + 1] = id seen[id] = true end
    end
    return out
end

--- the EMS job they are on duty at, or nil
local function medic(source)
    local mine = WC:GetPlayerJobs(source) or {}
    for _, j in ipairs(ESJ.emsJobs()) do
        if mine[j] and mine[j].clockedOn then return j end
    end
    return nil
end
ESJ.medic = medic

local function medicsOnDuty()
    local n = 0
    for src in pairs(WC:GetPlayers({ light = true }) or {}) do
        if medic(tonumber(src)) then n = n + 1 end
    end
    return n
end

local function name(src) return WC:GetPlayerFullName(src) or ('#' .. tostring(src)) end
local function pedOf(src) local p = GetPlayerPed(src) return (p and p ~= 0) and p or nil end
local function posOf(src)
    local p = pedOf(src)
    if not p then return nil end
    local c = GetEntityCoords(p)
    return { x = c.x, y = c.y, z = c.z }
end

local function setState(src, v)
    pcall(function() Player(src).state:set('esHurt', v, true) end)
end

local function tell(src, d) TriggerClientEvent('whip_jobs:client:hurt', src, d) end

-- ---------------------------------------------------------------- records and bills
--- a medical record: { charId, name, kind, injury, treatment, notes, jobId, bill, byCharId, byName, place } -> id
function ESJ.medRecord(r)
    local id = MySQL.insert.await([[INSERT INTO `es_jobs_medical` (`charId`,`name`,`kind`,`injury`,`treatment`,`notes`,`jobId`,`bill`,`byCharId`,`byName`,`place`)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)]], { r.charId, ESJ.trim(r.name or '?'):sub(1, 80), r.kind, r.injury and tostring(r.injury):sub(1, 200) or nil,
        r.treatment and tostring(r.treatment):sub(1, 200) or nil, r.notes and tostring(r.notes):sub(1, 1000) or nil, r.jobId, math.max(0, math.floor(r.bill or 0)),
        r.byCharId, r.byName and tostring(r.byName):sub(1, 80) or nil, r.place and tostring(r.place):sub(1, 120) or nil })
    return id
end

--- the EMS job to pay: the one asked for, else the first EMS job with a bank account
local function payee(jobId)
    if jobId and ESJ.account(jobId) then return jobId end
    for _, j in ipairs(ESJ.emsJobs()) do if ESJ.account(j) then return j end end
    return nil
end

--- take money from a player (cash or bank) into a job's account. -> true | false, why
local function collect(src, jobId, amount, method, reason)
    local acct = ESJ.account(jobId)
    if not acct then return false, 'The hospital has no bank account to pay into' end
    local receipt, why = WC:ChargePlayer(src, amount, { method = method or 'bank', reason = reason })
    if not receipt then return false, why or 'The payment failed' end
    local ok, why2 = WC:BankSystemDeposit(acct.accountId, amount, { reason = reason, actorCharId = WC:GetCharId(src) })
    if not ok then WC:RefundPlayer(receipt) return false, why2 or 'The payment could not be taken' end
    ESJ.ledger(jobId, 'medical', amount, WC:GetCharId(src), reason)
    return true
end

--- bill a patient: paid from their bank there and then if it can be; what can't is a bill they pay at a hospital desk.
--- -> amount, 'paid'|'owed'|nil
function ESJ.medBill(src, charId, jobId, amount, reason, recordId)
    amount = math.floor(tonumber(amount) or 0)
    jobId = payee(jobId)
    if amount <= 0 or not jobId then return 0, nil end
    local paid = src and WC:GetCharId(src) == charId and collect(src, jobId, amount, 'bank', 'Medical: ' .. reason) == true
    MySQL.insert.await('INSERT INTO `es_jobs_med_bills` (`charId`,`jobId`,`amount`,`reason`,`status`,`recordId`,`paidAt`) VALUES (?,?,?,?,?,?,?)',
        { charId, jobId, amount, tostring(reason):sub(1, 120), paid and 'paid' or 'unpaid', recordId, paid and os.date('%Y-%m-%d %H:%M:%S') or nil })
    if src then
        if paid then WC:NotifyPlayer(src, ('Medical bill: $%d paid from your bank (%s)'):format(amount, reason), 'info', 7000)
        else WC:NotifyPlayer(src, ('Medical bill: $%d (%s). Your bank could not cover it: pay at a hospital desk.'):format(amount, reason), 'error', 9000) end
    end
    return amount, paid and 'paid' or 'owed'
end

local function unpaidOf(charId)
    local rows = MySQL.query.await([[SELECT `id`,`jobId`,`amount`,`reason`,UNIX_TIMESTAMP(`createdAt`) AS `at` FROM `es_jobs_med_bills`
        WHERE `charId` = ? AND `status` = 'unpaid' ORDER BY `id` DESC LIMIT 30]], { charId }) or {}
    for _, r in ipairs(rows) do local o = ESJ.orgByJob(r.jobId) r.dept = o and (o.short or o.name) or nil end
    return rows
end

-- ---------------------------------------------------------------- calls (es_mdt)
local function closeCall(h, outcome)
    if not h or not h.callId or not mdtOn() then return end
    local cid = h.callId
    h.callId = nil
    pcall(function() exports.es_mdt:CloseCall(cid, outcome) end)
end

local function injuryText(h)
    local t = {}
    if h.headshot then t[#t + 1] = 'head wound' end
    if h.cause and h.cause ~= '' then t[#t + 1] = h.cause end
    return #t > 0 and table.concat(t, ', ') or nil
end

--- call EMS for them (auto: nobody pressed it). A down call upgrades the wounded call already open.
local function callFor(src, h, auto)
    if not mdtOn() then return false, 'Dispatch (es_mdt) is not running' end
    local C = E().calls or {}
    local pos = posOf(src) or { x = h.x, y = h.y, z = h.z }
    local inj = injuryText(h)
    if h.state == 'down' then
        local title = 'Person down: unresponsive'
        local msg = ('Not breathing / unresponsive%s'):format(inj and (' · ' .. inj) or '')
        if h.callId then
            local okU, ok = pcall(function() return exports.es_mdt:UpdateCall(h.callId, { priority = C.downPriority or 1, title = title, message = msg,
                critical = C.downCritical == true, note = 'The patient is now unresponsive (down)', upgraded = true }) end)
            if okU and ok then return true end
            closeCall(h, 'Upgraded: see the new call')   -- es_mdt older than 2.2.2: a new P1 call instead
        end
        local _, cid = pcall(function() return exports.es_mdt:AddCall({ kind = 'medical', groups = 'ems', priority = C.downPriority or 1, critical = C.downCritical == true,
            title = title, message = msg, street = h.street, coords = pos, merge = false }) end)
        h.callId = tonumber(cid)
        return h.callId ~= nil
    end
    if h.callId then return true end
    local msg = auto and ('Automatic alert: someone is badly hurt and cannot get up%s'):format(inj and (' · ' .. inj) or '')
        or ('Caller is badly hurt and cannot get up%s'):format(inj and (' · ' .. inj) or '')
    local _, cid = pcall(function() return exports.es_mdt:AddCall({ kind = 'medical', groups = 'ems', priority = C.woundedPriority or 2, title = 'Injured person',
        message = msg, street = h.street, coords = pos, merge = false,
        callerName = (not auto) and h.name or nil, callerCharId = (not auto) and h.charId or nil }) end)
    h.callId = tonumber(cid)
    h.calledAt = now()
    return h.callId ~= nil
end

-- ---------------------------------------------------------------- the states
local function clear(src, h)
    if Hurt[src] == h or h == nil then Hurt[src] = nil end
    setState(src, nil)
    pcall(function() WC:ReleaseRespawn(src, 'whip_jobs_ems') end)
end

local function newHurt(src, info, e)
    local p = posOf(src) or {}
    return { charId = WC:GetCharId(src), name = name(src), since = now(), headshot = info and info.headshot == true or false,
        cause = ESJ.trim((info and info.cause) or (e and e.reported) or ''):sub(1, 80), street = info and ESJ.trim(info.street or ''):sub(1, 120) or nil,
        x = p.x, y = p.y, z = p.z }
end

local function toDown(src, h, why)
    h.state, h.downAt, h.units = 'down', now(), 0
    Hurt[src] = h
    setState(src, 'down')
    callFor(src, h, true)
    tell(src, { state = 'down', called = h.callId ~= nil, why = why })
    WC:LogActivity(src, 'whip_jobs_ems', { detail = ('down%s'):format(why and (' (' .. why .. ')') or '') })
end

local function toWounded(src, info, e)
    local W = E().wounded or {}
    local h = newHurt(src, info, e)
    local ok = WC:RevivePlayer(src, 'whip_jobs: wounded')
    if not ok then return toDown(src, h, 'could not be wounded') end
    local secs = h.headshot and (W.headshotSeconds or 60) or (W.seconds or 180)
    h.state, h.untilAt = 'wounded', now() + secs
    local auto = tonumber(W.autoCallAfter) or 60
    h.autoAt = auto > 0 and (now() + auto) or nil
    Hurt[src] = h
    setState(src, 'wounded')
    tell(src, { state = 'wounded', left = secs, auto = auto > 0 and auto or nil, health = W.health or 120, headshot = h.headshot,
        crawl = W.crawlSpeed or 1.0 })
    WC:LogActivity(src, 'whip_jobs_ems', { detail = ('wounded for %ds%s'):format(secs, h.headshot and ' (headshot)' or '') })
end

--- their own game, the moment it died: the killing blow as it saw it (a headshot shortens the wounded timer)
local function onInfo(source, d)
    if type(d) ~= 'table' then return end
    Info[source] = { headshot = d.headshot == true, cause = type(d.cause) == 'string' and d.cause:sub(1, 80) or nil,
        street = type(d.street) == 'string' and d.street:sub(1, 120) or nil, at = now() }
end

AddEventHandler('whip_core:player:died', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' then return end
    local src = tonumber(e.source)
    if not src or not on() then return end
    local h = Hurt[src]
    CreateThread(function()
        Wait(900)   -- their own game's report (onInfo) comes just after the death
        if not WC:IsPlayerDead(src) then return end
        local info = Info[src]
        Info[src] = nil
        if info and now() - info.at > 15 then info = nil end
        if h and Hurt[src] == h then
            if h.state == 'wounded' then toDown(src, h, h.bleeding and 'bled out' or 'hurt again') end
            return
        end
        local W = E().wounded or {}
        if info and info.headshot and W.headshotDown then return toDown(src, newHurt(src, info, e), 'headshot') end
        Wait(2600)   -- the fall plays out first
        if not WC:IsPlayerDead(src) or Hurt[src] then return end
        toWounded(src, info, e)
    end)
end)

AddEventHandler('whip_core:player:revived', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' then return end
    local src = tonumber(e.source)
    local h = src and Hurt[src]
    if not h or h.reviving then return end
    if e.how == 'respawned' then
        local B = E().bills or {}
        local job = payee(nil)
        local rid = ESJ.medRecord({ charId = h.charId, name = h.name, kind = 'respawn', injury = injuryText(h), treatment = 'Woke up at the hospital',
            jobId = job, bill = B.respawn or 0 })
        ESJ.medBill(src, h.charId, job, B.respawn or 0, 'Hospital care', rid)
        closeCall(h, 'Patient taken to hospital')
    else
        closeCall(h, 'Patient revived')
    end
    clear(src, h)
    tell(src, { state = 'none' })
end)

local function gone(src)
    local h = Hurt[src]
    if not h then return end
    closeCall(h, 'Patient left')
    Hurt[src] = nil
end
AddEventHandler('playerDropped', function() gone(source) Info[source] = nil end)
AddEventHandler('whip_core:player:logout', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' then return end
    local src = tonumber(e.source)
    if src then gone(src) setState(src, nil) end
end)

-- the clock: the automatic call, the bleed-out, the respawn hold while units are on the call
local tickN = 0
local function tick()
    tickN = tickN + 1
    local t = now()
    for src, h in pairs(Hurt) do
        if WC:GetCharId(src) ~= h.charId then
            gone(src)
        elseif h.state == 'wounded' then
            if not WC:IsPlayerDead(src) then
                if not h.callId and h.autoAt and t >= h.autoAt then
                    if callFor(src, h, true) then tell(src, { state = 'wounded', called = true, auto = true }) end
                end
                if t >= h.untilAt and (not h.bleeding or t >= h.bleeding + 8) then
                    h.bleeding = t
                    TriggerClientEvent('whip_jobs:client:bleedOut', src)
                end
            end
        elseif h.state == 'down' then
            if not WC:IsPlayerDead(src) then
                -- up again some way that did not say so (should not happen): the call ends
                closeCall(h, 'Patient revived')
                clear(src, h)
                tell(src, { state = 'none' })
            end
        end
        -- units on the call: the HUD says so, and the respawn waits while they come
        if Hurt[src] == h and h.callId and mdtOn() and tickN % 2 == 0 then
            local ok, r = pcall(function() return exports.es_mdt:GetCallUnits(h.callId) end)
            if ok and type(r) == 'table' then
                local n = r.active and #(r.units or {}) or 0
                if not r.active then h.callId = nil end
                if n ~= h.units then
                    h.units = n
                    tell(src, { state = h.state, units = n, called = h.callId ~= nil })
                end
                if h.state == 'down' then
                    if n > 0 and (E().calls or {}).holdRespawn ~= false then
                        WC:HoldRespawn(src, 'whip_jobs_ems', ('EMS is on the way · %d unit%s'):format(n, n == 1 and '' or 's'))
                    else
                        WC:ReleaseRespawn(src, 'whip_jobs_ems')
                    end
                end
            end
        end
    end
end
ESJ.emsTick = tick   -- (the sims drive it)
CreateThread(function()
    while true do
        Wait(2000)
        local ok, err = pcall(tick)
        if not ok then print(('^3[whip_jobs] ems: %s^7'):format(tostring(err))) end
    end
end)

-- ---------------------------------------------------------------- the patient's own buttons
local function callEms(source)
    local h = Hurt[source]
    if not h or h.state ~= 'wounded' then return false, 'You are not wounded' end
    if h.callId then return { called = true } end
    local ok, why = callFor(source, h, false)
    if not ok then return false, why or 'The call did not go through' end
    return { called = true }
end

-- ---------------------------------------------------------------- treating someone
local function targetOf(source, d, range)
    local t = tonumber(d.target)
    if not t or t == source or not WC:GetCharId(t) then return nil, 'Nobody there' end
    local me, them = pedOf(source), pedOf(t)
    if not me or not them then return nil, 'Nobody there' end
    if GetPlayerRoutingBucket(t) ~= GetPlayerRoutingBucket(source) then return nil, 'Nobody there' end
    if #(GetEntityCoords(me) - GetEntityCoords(them)) > (range or 3.0) + 1.0 then return nil, 'Get closer' end
    return t, them
end

-- at most 8 s: it runs inside a SecureCallback, which the client gives up on after 10
local function bar(source, label, seconds, them)
    local ok, why = WC:Progress(source, { label = label, duration = math.floor(math.max(1, math.min(8, seconds or 5)) * 1000), icon = 'heart',
        anim = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 1 },
        disable = { move = true, combat = true, car = true }, near = { coords = GetEntityCoords(them), range = 4.0 } })
    if ok ~= true then return false, why == 'too far' and 'They moved away' or 'Stopped' end
    return true
end

--- up again from wounded (first aid, treatment): the call closes, their game lets them stand
local function recover(t, health, outcome)
    local h = Hurt[t]
    if h then closeCall(h, outcome) end
    clear(t, h)
    tell(t, { state = 'none', health = health })
end

local function placeOf(src)
    local h = Hurt[src]
    return h and h.street or nil
end

local function firstAid(source, d)
    local F = E().firstAid or {}
    local item = F.item or 'whip_jobs_first_aid'
    if not WC:HasItem(source, item) then return false, 'You need a first aid kit' end
    local t, them = targetOf(source, d)
    if not t then return false, them end
    local h = Hurt[t]
    if WC:IsPlayerDead(t) then return false, 'They need EMS: they are not breathing' end
    if not h or h.state ~= 'wounded' then return false, 'They are not wounded' end
    WC:NotifyPlayer(t, name(source) .. ' is patching you up', 'info')
    local ok, why = bar(source, 'First aid...', F.seconds or 7, them)
    if not ok then return false, why end
    if Hurt[t] ~= h or h.state ~= 'wounded' then return false, 'Too late' end
    if not WC:RemoveItem(source, item, 1) then return false, 'You need a first aid kit' end
    ESJ.medRecord({ charId = h.charId, name = h.name, kind = 'aid', injury = injuryText(h), treatment = 'First aid kit',
        byCharId = WC:GetCharId(source), byName = name(source), place = placeOf(t) })
    recover(t, F.health or 150, 'Patient helped up')
    WC:NotifyPlayer(source, 'You helped ' .. name(t) .. ' up', 'success')
    WC:LogActivity(source, 'whip_jobs_ems', { detail = 'first aid on ' .. name(t) })
    return true
end

local function needMedic(source)
    local job = medic(source)
    if not job then return nil, 'Only EMS on duty' end
    if not WC:HasItem(source, (E().medbag or {}).item or 'whip_jobs_medbag') then return nil, 'You need a medical bag' end
    return job
end

local function treat(source, d)
    local job, why = needMedic(source)
    if not job then return false, why end
    local t, them = targetOf(source, d)
    if not t then return false, them end
    if WC:IsPlayerDead(t) then return false, 'They are not breathing: revive them' end
    local h = Hurt[t]
    if not h and GetEntityHealth(them) >= 200 then return false, 'They are not hurt' end
    WC:NotifyPlayer(t, 'A medic is treating you', 'info')
    local ok, w = bar(source, 'Treating...', (E().treat or {}).seconds or 6, them)
    if not ok then return false, w end
    local cid = WC:GetCharId(t)
    local B = E().bills or {}
    local rid = ESJ.medRecord({ charId = cid, name = name(t), kind = 'treat', injury = h and injuryText(h) or 'Injuries', treatment = 'Treated on scene',
        jobId = job, bill = B.treat or 0, byCharId = WC:GetCharId(source), byName = name(source), place = placeOf(t), notes = ESJ.trim(d.notes or ''):sub(1, 300) })
    recover(t, 200, 'Patient treated')
    ESJ.medBill(t, cid, job, B.treat or 0, 'Treatment', rid)
    WC:NotifyPlayer(source, 'Treated ' .. name(t), 'success')
    WC:LogActivity(source, 'whip_jobs_ems', { detail = 'treated ' .. name(t) })
    return true
end

local function revive(source, d)
    local job, why = needMedic(source)
    if not job then return false, why end
    local t, them = targetOf(source, d)
    if not t then return false, them end
    if not WC:IsPlayerDead(t) then return false, 'They are breathing: treat them instead' end
    local ok, w = bar(source, 'Reviving...', (E().treat or {}).revive or 8, them)
    if not ok then return false, w end
    if not WC:IsPlayerDead(t) then return false, 'They are up already' end
    local h = Hurt[t] or newHurt(t, nil, nil)
    h.reviving = true
    local okR, whyR = WC:RevivePlayer(t, 'whip_jobs: EMS')
    h.reviving = nil
    if not okR then return false, whyR or 'They could not be revived' end
    local cid = WC:GetCharId(t)
    local B = E().bills or {}
    local rid = ESJ.medRecord({ charId = cid, name = name(t), kind = 'revive', injury = injuryText(h), treatment = 'Revived on scene',
        jobId = job, bill = B.revive or 0, byCharId = WC:GetCharId(source), byName = name(source), place = h.street, notes = ESJ.trim(d.notes or ''):sub(1, 300) })
    closeCall(h, 'Patient revived')
    clear(t, Hurt[t])
    tell(t, { state = 'none' })
    ESJ.medBill(t, cid, job, B.revive or 0, 'Revive', rid)
    WC:NotifyPlayer(source, 'Revived ' .. name(t), 'success')
    WC:LogActivity(source, 'whip_jobs_ems', { detail = 'revived ' .. name(t) })
    return true
end

local function examine(source, d)
    if not medic(source) then return false, 'Only EMS on duty' end
    local t, them = targetOf(source, d)
    if not t then return false, them end
    local h = Hurt[t]
    local dead = WC:IsPlayerDead(t) == true
    local out = { name = name(t), state = dead and 'down' or (h and h.state) or 'ok', headshot = h and h.headshot or false,
        cause = h and h.cause or nil, minutes = h and math.floor((now() - h.since) / 60) or nil,
        left = (h and h.state == 'wounded' and not dead) and math.max(0, h.untilAt - now()) or nil,
        health = (not dead) and math.max(0, GetEntityHealth(them) - 100) or 0 }
    return out
end

-- ---------------------------------------------------------------- the hospital desk
local function deskJob(st, source)
    local ems = {}
    for _, j in ipairs(ESJ.emsJobs()) do ems[j] = true end
    for _, j in ipairs(st.jobs or {}) do if ems[j] then return j end end
    return medic(source)
end

function ESJ.hospitalInfo(source, s, st)
    local cid = WC:GetCharId(source)
    local ped = pedOf(source)
    local hp = ped and GetEntityHealth(ped) or 200
    local D = E().desk or {}
    local n = medicsOnDuty()
    local staffedAt = tonumber(D.staffedAt) or 1
    local job = medic(source)
    return { health = math.max(0, hp - 100), hurt = hp < 200, price = (E().bills or {}).desk or 0, staffed = staffedAt > 0 and n >= staffedAt,
        medics = n, bills = unpaidOf(cid), methods = E().billMethods or { 'bank', 'cash' }, medic = job ~= nil, on = on() }
end

local function desk(source, d)
    local s, st = ESJ.at(source, d, false, 4.0)
    if not s then return false, st end
    if s.type ~= 'hospital' then return false, 'Ask at a hospital desk' end
    return s, st
end

local function deskTreat(source, d)
    local s, st = desk(source, d)
    if not s then return false, st end
    if Hurt[source] then return false, 'You need EMS' end
    local info = ESJ.hospitalInfo(source, s, st)
    if info.staffed then
        local cid = WC:GetCharId(source)
        if (DeskCalls[cid] or 0) > now() - 120 then return { called = true, again = true } end
        if not mdtOn() then return false, 'Dispatch (es_mdt) is not running' end
        local _, ok = pcall(function() return exports.es_mdt:AddCall({ kind = 'medical', groups = 'ems', priority = 3, title = 'Patient at the front desk',
            message = ('%s is waiting for treatment at %s'):format(name(source), st.name), street = st.name,
            coords = { x = s.x, y = s.y, z = s.z }, callerName = name(source), callerCharId = cid, merge = false }) end)
        if not ok then return false, 'The desk could not reach EMS' end
        DeskCalls[cid] = now()
        return { called = true }
    end
    if not info.hurt then return false, 'You are not hurt' end
    local price = math.floor(tonumber(info.price) or 0)
    local job = payee(deskJob(st, source))
    local method = d.method == 'cash' and 'cash' or 'bank'
    if price > 0 then
        if not job then return false, 'The hospital has no bank account to pay into' end
        local ped = pedOf(source)
        local ok, why = WC:Progress(source, { label = 'Being treated...', duration = math.floor(math.min(8, (E().desk or {}).seconds or 8) * 1000), icon = 'heart',
            disable = { move = true, combat = true, car = true }, near = { coords = GetEntityCoords(ped), range = 2.0 } })
        if ok ~= true then return false, why == 'too far' and 'You walked away' or 'Stopped' end
        local paid, w = collect(source, job, price, method, 'Medical: hospital treatment')
        if not paid then return false, w end
    end
    local cid = WC:GetCharId(source)
    ESJ.medRecord({ charId = cid, name = name(source), kind = 'desk', injury = 'Injuries', treatment = 'Treated at the hospital desk',
        jobId = job, bill = price, place = st.name })
    if price > 0 then
        MySQL.insert.await('INSERT INTO `es_jobs_med_bills` (`charId`,`jobId`,`amount`,`reason`,`status`,`paidAt`) VALUES (?,?,?,?,\'paid\',NOW())',
            { cid, job, price, 'Hospital treatment' })
    end
    tell(source, { state = 'none', health = 200 })
    return { healed = true }
end

local function payBill(source, d)
    local s, st = desk(source, d)
    if not s then return false, st end
    local cid = WC:GetCharId(source)
    local b = MySQL.single.await('SELECT * FROM `es_jobs_med_bills` WHERE `id` = ? AND `charId` = ?', { tonumber(d.id) or 0, cid })
    if not b or b.status ~= 'unpaid' then return false, 'That bill is not open' end
    local method = d.method == 'cash' and 'cash' or 'bank'
    local okM = false
    for _, m in ipairs(E().billMethods or { 'bank', 'cash' }) do if m == method then okM = true end end
    if not okM then return false, 'The desk does not take that' end
    local job = payee(b.jobId)
    if not job then return false, 'The hospital has no bank account to pay into' end
    local n = MySQL.update.await("UPDATE `es_jobs_med_bills` SET `status` = 'paying' WHERE `id` = ? AND `status` = 'unpaid'", { b.id })
    if n ~= 1 then return false, 'That bill is not open' end
    local ok, why = collect(source, job, b.amount, method, 'Medical bill: ' .. b.reason)
    MySQL.update.await('UPDATE `es_jobs_med_bills` SET `status` = ?, `paidAt` = IF(? = \'paid\', NOW(), NULL) WHERE `id` = ?',
        { ok and 'paid' or 'unpaid', ok and 'paid' or 'unpaid', b.id })
    if not ok then return false, why end
    return { bills = unpaidOf(cid) }
end

-- ---------------------------------------------------------------- medical records (EMS on duty, at a hospital desk)
local function recordsAccess(source, d)
    local s, st = desk(source, d)
    if not s then return false, st end
    local job = medic(source)
    if not job then return false, 'Medical records are for EMS on duty' end
    return job, st
end

local KIND = { aid = 'First aid', treat = 'Treated', revive = 'Revived', respawn = 'Hospital', desk = 'Desk', note = 'Note' }
local function shape(r)
    local o = r.jobId and ESJ.orgByJob(r.jobId)
    return { id = r.id, charId = r.charId, name = r.name, kind = r.kind, kindLabel = KIND[r.kind] or r.kind, injury = r.injury, treatment = r.treatment,
        notes = r.notes, bill = r.bill, by = r.byName, place = r.place, at = r.at, dept = o and (o.short or o.name) or nil }
end

local function records(source, d)
    local job, st = recordsAccess(source, d)
    if not job then return false, st end
    local q = ESJ.trim(d.q or ''):sub(1, 40)
    local rows
    if q ~= '' then
        rows = MySQL.query.await([[SELECT m.`charId`, MAX(m.`name`) AS `name`, COUNT(*) AS `n`, MAX(UNIX_TIMESTAMP(m.`at`)) AS `last` FROM `es_jobs_medical` m
            WHERE m.`name` LIKE ? OR m.`charId` = ? GROUP BY m.`charId` ORDER BY `last` DESC LIMIT 40]], { '%' .. q:gsub('[%%_]', '') .. '%', tonumber(q) or 0 }) or {}
    else
        rows = MySQL.query.await([[SELECT m.`charId`, MAX(m.`name`) AS `name`, COUNT(*) AS `n`, MAX(UNIX_TIMESTAMP(m.`at`)) AS `last` FROM `es_jobs_medical` m
            GROUP BY m.`charId` ORDER BY `last` DESC LIMIT 40]]) or {}
    end
    local recent = MySQL.query.await([[SELECT `id`,`charId`,`name`,`kind`,`injury`,`treatment`,`notes`,`jobId`,`bill`,`byName`,`place`,UNIX_TIMESTAMP(`at`) AS `at`
        FROM `es_jobs_medical` ORDER BY `id` DESC LIMIT 12]]) or {}
    local out = {}
    for _, r in ipairs(recent) do out[#out + 1] = shape(r) end
    return { patients = rows, recent = out }
end

local function patient(source, d)
    local job, st = recordsAccess(source, d)
    if not job then return false, st end
    local cid = tonumber(d.charId)
    if not cid then return false, 'Pick a patient' end
    local rows = MySQL.query.await([[SELECT `id`,`charId`,`name`,`kind`,`injury`,`treatment`,`notes`,`jobId`,`bill`,`byName`,`place`,UNIX_TIMESTAMP(`at`) AS `at`
        FROM `es_jobs_medical` WHERE `charId` = ? ORDER BY `id` DESC LIMIT 60]], { cid }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = shape(r) end
    local bills = unpaidOf(cid)
    local owed = 0
    for _, b in ipairs(bills) do owed = owed + b.amount b.canWaive = ESJ.canManage(source, b.jobId) end
    return { charId = cid, name = rows[1] and rows[1].name or ESJ.nameOf(cid), records = out, bills = bills, owed = owed }
end

local function note(source, d)
    local job, st = recordsAccess(source, d)
    if not job then return false, st end
    local cid = tonumber(d.charId)
    local text = ESJ.trim(d.text or ''):sub(1, 1000)
    if not cid then return false, 'Pick a patient' end
    if #text < 2 then return false, 'Write the note first' end
    local last = MySQL.single.await('SELECT `name` FROM `es_jobs_medical` WHERE `charId` = ? ORDER BY `id` DESC LIMIT 1', { cid })
    ESJ.medRecord({ charId = cid, name = last and last.name or ESJ.nameOf(cid), kind = 'note', notes = text, jobId = job,
        byCharId = WC:GetCharId(source), byName = name(source), place = st.name })
    return patient(source, d)
end

local function waive(source, d)
    local job, st = recordsAccess(source, d)
    if not job then return false, st end
    local b = MySQL.single.await('SELECT * FROM `es_jobs_med_bills` WHERE `id` = ?', { tonumber(d.id) or 0 })
    if not b or b.status ~= 'unpaid' then return false, 'That bill is not open' end
    if not ESJ.canManage(source, b.jobId) then return false, 'Only the department\'s leaders waive a bill' end
    MySQL.update.await("UPDATE `es_jobs_med_bills` SET `status` = 'waived', `paidAt` = NOW() WHERE `id` = ?", { b.id })
    WC:LogActivity(source, 'whip_jobs_ems', { detail = ('waived medical bill #%d ($%d) of #%d'):format(b.id, b.amount, b.charId) })
    d.charId = b.charId
    return patient(source, d)
end

-- ---------------------------------------------------------------- items, callbacks
local ITEMS = {
    { key = function() return (E().firstAid or {}).item or 'whip_jobs_first_aid' end, def = { name = 'First aid kit', weight = 0.5, stack = true, maxStack = 10,
        desc = 'Aim at someone wounded (yellow) and pick First aid to help them up. One per use.', image = 'html/img/items/first_aid.webp' } },
    { key = function() return (E().medbag or {}).item or 'whip_jobs_medbag' end, def = { name = 'Medical bag', weight = 3.0, stack = false,
        desc = 'EMS: aim at a patient, EMS > Examine, Treat or Revive.', image = 'html/img/items/medbag.webp' } },
}

function ESJ.registerEms(cb)
    for _, it in ipairs(ITEMS) do
        local key = it.key()
        local def = {}
        for k, v in pairs(it.def) do def[k] = v end
        local ok, why = Whip.core:RegisterItem(key, def)
        if not ok then print(('^3[whip_jobs] item %s: %s (another script\'s item of that name is used)^7'):format(key, tostring(why))) end
    end
    Whip.core:SecureEvent('whip_jobs:ems:info', { rateLimit = 1000, burst = 2, sheet = 'light', whileDead = true, params = { { 'd', 'any' } } },
        function(source, _, d) onInfo(source, d) end)
    cb('whip_jobs:ems:call', 2000, callEms)
    cb('whip_jobs:ems:aid', 1500, firstAid)
    cb('whip_jobs:ems:treat', 1500, treat)
    cb('whip_jobs:ems:revive', 1500, revive)
    cb('whip_jobs:ems:examine', 800, examine)
    cb('whip_jobs:ems:me', 1000, function(source)
        local h = Hurt[source]
        if not h then return { state = 'none' } end
        return { state = h.state, left = h.untilAt and math.max(0, h.untilAt - now()) or nil, called = h.callId ~= nil, units = h.units or 0,
            health = (E().wounded or {}).health or 120, auto = h.autoAt and math.max(0, h.autoAt - now()) or nil }
    end)
    cb('whip_jobs:hosp:treat', 2500, deskTreat)
    cb('whip_jobs:hosp:pay', 2000, payBill)
    cb('whip_jobs:med:list', 800, records)
    cb('whip_jobs:med:patient', 600, patient)
    cb('whip_jobs:med:note', 2000, note)
    cb('whip_jobs:med:waive', 1500, waive)
end

--- es_mdt asks before its own "person down" alert: we file those (wounded and down calls) when EMS here is on
exports('HandlesDowns', function() return on() end)
--- 'wounded' | 'down' | nil
exports('GetHurtState', function(src) local h = Hurt[tonumber(src) or 0] return h and h.state or nil end)
