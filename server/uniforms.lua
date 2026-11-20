-- es_jobs: uniforms. Each department or business keeps uniforms per body (male / female), each from a rank up. They are
-- made in WHIP's own character editor (EditAppearance on the clothes and props tabs only, so every add-on clothing pack
-- the server streams is there, with its pictures), and worn from a station's locker room.
--
-- Wearing one: the character's own clothes (their saved look's clothes and props) are kept in es_jobs_wardrobe, and the
-- uniform becomes their saved look's clothes (SetPlayerAppearance, clothes and props only), so WHIP itself puts it back
-- after a revive, a model reload or a relog. Clocking off (or logging out: WHIP clocks everyone off) puts their own
-- clothes back; a row still there when they next load (a crash) is put back then.
ESJ = ESJ or {}
local WC = exports.whip_core
local U = {}           -- [id] = { id, jobId, name, body, minLevel, parts, sort }
local worn = {}        -- [charId] = { own, uniformId, jobId } (cache of es_jobs_wardrobe)
local COMPS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 11 }          -- the editor's clothes tabs (2 is hair, 0 the head)
local PROPS = { 0, 1, 2, 6, 7 }                            -- hat, glasses, ears, watch, bracelet
local PART_NAMES = { c1 = 'Mask', c3 = 'Arms / gloves', c4 = 'Legs', c5 = 'Bag', c6 = 'Shoes', c7 = 'Accessory', c8 = 'Undershirt',
    c9 = 'Vest / armor', c10 = 'Badge / decal', c11 = 'Top', p0 = 'Hat', p1 = 'Glasses', p2 = 'Ears', p6 = 'Watch', p7 = 'Bracelet' }
local ONLY = { 'apparel', 'props' }
ESJ.UNIFORM_PARTS = PART_NAMES

local function G() return Config.Gear or {} end
local function bodyOf(model) return model == 'mp_f_freemode_01' and 'female' or (model == 'mp_m_freemode_01' and 'male' or nil) end
local function deep(v) return json.decode(json.encode(v)) end

--- the clothes and props of a look, as uniform parts: { c = { ['11'] = { d, t } }, p = { ['0'] = { d, t } } }
--- `skip` = { c1 = true, p1 = true ... }: parts the uniform leaves as the wearer's own
local function partsOf(look, skip)
    local out = { c = {}, p = {} }
    skip = skip or {}
    for _, i in ipairs(COMPS) do
        local x = (look.components or {})[tostring(i)]
        if x and not skip['c' .. i] then out.c[tostring(i)] = { ESJ.int(x.drawable, 0, 4095, 0), ESJ.int(x.texture, 0, 255, 0) } end
    end
    for _, i in ipairs(PROPS) do
        local x = (look.props or {})[tostring(i)]
        if not skip['p' .. i] then
            out.p[tostring(i)] = x and { ESJ.int(x.drawable, -1, 4095, -1), ESJ.int(x.texture, 0, 255, 0) } or { -1, 0 }
        end
    end
    return out
end

--- a look with these parts put on (a copy)
local function dress(look, parts)
    local out = deep(look)
    out.components, out.props = out.components or {}, out.props or {}
    for k, v in pairs(parts.c or {}) do out.components[k] = { drawable = v[1], texture = v[2] } end
    for k, v in pairs(parts.p or {}) do out.props[k] = { drawable = v[1], texture = v[2] } end
    return out
end

local function cleanParts(p)
    if type(p) ~= 'table' then return nil end
    local out, n = { c = {}, p = {} }, 0
    for _, i in ipairs(COMPS) do
        local v = type(p.c) == 'table' and p.c[tostring(i)]
        if type(v) == 'table' then out.c[tostring(i)] = { ESJ.int(v[1], 0, 4095, 0), ESJ.int(v[2], 0, 255, 0) } n = n + 1 end
    end
    for _, i in ipairs(PROPS) do
        local v = type(p.p) == 'table' and p.p[tostring(i)]
        if type(v) == 'table' then out.p[tostring(i)] = { ESJ.int(v[1], -1, 4095, -1), ESJ.int(v[2], 0, 255, 0) } n = n + 1 end
    end
    return n > 0 and out or nil
end

-- ---------------------------------------------------------------- load
function ESJ.loadUniforms()
    local ok, rows = pcall(MySQL.query.await, 'SELECT * FROM `es_jobs_uniforms`')
    if not ok or type(rows) ~= 'table' then return false end
    U = {}
    for _, r in ipairs(rows) do
        local okj, parts = pcall(json.decode, r.parts or '')
        parts = okj and cleanParts(parts)
        if parts then U[r.id] = { id = r.id, jobId = r.jobId, name = r.name, body = r.body, minLevel = r.minLevel or 0, parts = parts, sort = r.sort or 0 } end
    end
    local okw, wr = pcall(MySQL.query.await, 'SELECT * FROM `es_jobs_wardrobe`')
    worn = {}
    if okw and type(wr) == 'table' then
        for _, r in ipairs(wr) do
            local okj, own = pcall(json.decode, r.own or '')
            own = okj and cleanParts(own)
            if own then worn[r.charId] = { own = own, uniformId = r.uniformId, jobId = r.jobId } end
        end
    end
    return true
end

local function savedLook(source)
    local look = WC:GetPlayerMetadata(source, 'appearance')
    if type(look) ~= 'table' or not look.model then return nil, 'Make your character first (your look is not saved yet)' end
    return look
end

--- put parts on: kept as their saved clothes, and on their ped now
local function putOn(source, look, parts)
    local ok, kept = WC:SetPlayerAppearance(source, dress(look, parts), { only = ONLY })
    if not ok then return false, kept end
    TriggerClientEvent('es_jobs:client:dress', source, parts)
    return true
end

-- ---------------------------------------------------------------- wear / own clothes
local function wear(source, u, jobId)
    local cid = WC:GetCharId(source)
    local look, why = savedLook(source)
    if not look then return false, why end
    if bodyOf(look.model) ~= u.body then return false, 'That uniform is cut for the other body' end
    local w = worn[cid]
    local own = w and w.own or partsOf(look)      -- their own clothes: kept once, the first time they change
    if not w then
        local okw = MySQL.insert.await('INSERT INTO `es_jobs_wardrobe` (`charId`,`own`,`uniformId`,`jobId`) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE `uniformId` = VALUES(`uniformId`), `jobId` = VALUES(`jobId`)',
            { cid, json.encode(own), u.id, jobId })
        if okw == nil then return false, 'Your own clothes could not be put away' end
    else
        MySQL.update('UPDATE `es_jobs_wardrobe` SET `uniformId` = ?, `jobId` = ? WHERE `charId` = ?', { u.id, jobId, cid })
    end
    -- the uniform over their own clothes, so the parts it leaves alone are their own (not the last uniform's)
    local ok, err = putOn(source, dress(look, own), u.parts)
    if not ok then
        if not w then MySQL.update('DELETE FROM `es_jobs_wardrobe` WHERE `charId` = ?', { cid }) end
        return false, err
    end
    worn[cid] = { own = own, uniformId = u.id, jobId = jobId }
    return true
end

--- their own clothes back (clock-off, the locker's button, a load after a crash). quiet: no toast
function ESJ.ownClothes(source, quiet)
    local cid = WC:GetCharId(source)
    local w = cid and worn[cid]
    if not w then return false, 'You are wearing your own clothes' end
    local look, why = savedLook(source)
    if not look then return false, why end
    local ok, err = putOn(source, look, w.own)
    if not ok then return false, err end
    worn[cid] = nil
    MySQL.update('DELETE FROM `es_jobs_wardrobe` WHERE `charId` = ?', { cid })
    if not quiet then WC:NotifyPlayer(source, 'Back in your own clothes', 'info') end
    return true
end

function ESJ.wearing(cid) return worn[cid] end

-- ---------------------------------------------------------------- the locker room
local function lockerAt(source, d, needDuty)
    local s, st, me = ESJ.at(source, d, needDuty)
    if not s then return false, st end
    if s.type ~= 'locker' then return false, 'That is not a locker room' end
    return s, st, me
end

local function canDesign(source, jobId)
    return ESJ.isAdmin(source) or WC:HasJobPermission(source, jobId, 'canManage') == true
end

local function list(source, d)
    local s, st, me = lockerAt(source, d, false)
    if not s then return false, st end
    local look = savedLook(source)
    local body = look and bodyOf(look.model) or 'male'
    local cid = WC:GetCharId(source)
    local out = { body = body, onlyOnDuty = G().uniformsOnlyOnDuty ~= false, adjust = G().adjust ~= false, orgs = {},
        wearing = worn[cid] and worn[cid].uniformId or false, wearingAny = worn[cid] ~= nil, parts = PART_NAMES,
        personal = (G().lockerSlots or 0) > 0 }
    for _, j in ipairs(me.jobs) do
        local o = ESJ.orgByJob(j.jobId)
        local roles = {}
        for _, r in ipairs(WC:GetJobRoles(j.jobId) or {}) do roles[#roles + 1] = { name = r.name or r.label, level = r.level or 0 } end
        table.sort(roles, function(a, b) return a.level < b.level end)
        local og = { jobId = j.jobId, name = o and o.name or ('Job ' .. j.jobId), short = o and o.short, kind = o and o.kind, id = o and o.id,
            logoVer = o and o.logoVer, color = o and o.color, level = j.level, rank = j.role, onDuty = j.onDuty,
            canDesign = canDesign(source, j.jobId), roles = roles, uniforms = {} }
        for _, u in pairs(U) do
            if u.jobId == j.jobId and (u.body == body or og.canDesign) then
                og.uniforms[#og.uniforms + 1] = { id = u.id, name = u.name, body = u.body, minLevel = u.minLevel, parts = u.parts, sort = u.sort,
                    allowed = u.body == body and j.level >= u.minLevel and (j.onDuty or G().uniformsOnlyOnDuty == false) }
            end
        end
        table.sort(og.uniforms, function(a, b) if a.sort ~= b.sort then return a.sort < b.sort end return a.minLevel < b.minLevel end)
        out.orgs[#out.orgs + 1] = og
    end
    return out
end

local function wearCb(source, d)
    local s, st, me = lockerAt(source, d, false)
    if not s then return false, st end
    local u = U[tonumber(d.id) or 0]
    if not u then return false, 'That uniform is gone' end
    local mine
    for _, j in ipairs(me.jobs) do if j.jobId == u.jobId then mine = j end end
    if not mine then return false, 'That is another department\'s uniform' end
    if G().uniformsOnlyOnDuty ~= false and not mine.onDuty then return false, 'Clock on first' end
    if mine.level < u.minLevel then return false, 'Your rank cannot wear that one yet' end
    local ok, why = wear(source, u, u.jobId)
    if not ok then return false, why end
    return { id = u.id }
end

local function ownCb(source, d)
    local s, st = lockerAt(source, d, false)
    if not s then return false, st end
    return ESJ.ownClothes(source, true)
end

--- a look from WHIP's editor, made into a uniform (new or changed) for one department or business
local function saveCb(source, d)
    local s, st, me = lockerAt(source, d, false)
    if not s then return false, st end
    local jobId = tonumber(d.jobId)
    local belongs = false
    for _, j in ipairs(me.jobs) do if j.jobId == jobId then belongs = true end end
    if not (belongs or ESJ.isAdmin(source)) or not canDesign(source, jobId) then return false, 'Only its leaders make uniforms' end
    local name = ESJ.trim(d.name):sub(1, 40)
    if name == '' then return false, 'Give it a name' end
    local minLevel = ESJ.int(d.minLevel, 0, 1000, 0)
    local u = d.id and U[tonumber(d.id) or 0]
    if d.id and (not u or u.jobId ~= jobId) then return false, 'That uniform is gone' end
    local parts, body
    if type(d.look) == 'table' then
        local okS, look = WC:SanitizeAppearance(d.look)
        if not okS then return false, 'That look is not valid: ' .. tostring(look) end
        body = bodyOf(look.model)
        if not body then return false, 'Uniforms are for MP characters (male or female freemode)' end
        local skip = {}
        for _, k in ipairs(type(d.skip) == 'table' and d.skip or {}) do if PART_NAMES[k] then skip[k] = true end end
        parts = partsOf(look, skip)
    elseif u then
        parts, body = deep(u.parts), u.body
        for _, k in ipairs(type(d.skip) == 'table' and d.skip or {}) do
            if PART_NAMES[k] then (k:sub(1, 1) == 'c' and parts.c or parts.p)[k:sub(2)] = nil end
        end
        if not cleanParts(parts) then return false, 'A uniform needs at least one part of its own' end
    else
        return false, 'Dress it in the editor first'
    end
    local cid = WC:GetCharId(source)
    local enc = json.encode(parts)
    if u then
        MySQL.update.await('UPDATE `es_jobs_uniforms` SET `name` = ?, `minLevel` = ?, `parts` = ?, `body` = ?, `updatedBy` = ? WHERE `id` = ?',
            { name, minLevel, enc, body, cid, u.id })
        u.name, u.minLevel, u.parts, u.body = name, minLevel, parts, body
    else
        local n = 0
        for _, x in pairs(U) do if x.jobId == jobId then n = n + 1 end end
        if n >= 40 then return false, 'A department keeps up to 40 uniforms' end
        local id = MySQL.insert.await('INSERT INTO `es_jobs_uniforms` (`jobId`,`name`,`body`,`minLevel`,`parts`,`sort`,`updatedBy`) VALUES (?,?,?,?,?,?,?)',
            { jobId, name, body, minLevel, enc, n, cid })
        if not id then return false, 'It could not be saved' end
        u = { id = id, jobId = jobId, name = name, body = body, minLevel = minLevel, parts = parts, sort = n }
        U[id] = u
    end
    local o = ESJ.orgByJob(jobId)
    WC:LogActivity(source, 'es_jobs_uniform', { detail = ('%s uniform "%s" (%s, rank %d+)'):format(o and o.short or jobId, name, body, minLevel) })
    return { id = u.id }
end

local function deleteCb(source, d)
    local s = lockerAt(source, d, false)
    if not s then return false, 'Go to a locker room first' end
    local u = U[tonumber(d.id) or 0]
    if not u then return false, 'That uniform is gone' end
    if not canDesign(source, u.jobId) then return false, 'Only its leaders change uniforms' end
    MySQL.update.await('DELETE FROM `es_jobs_uniforms` WHERE `id` = ?', { u.id })
    U[u.id] = nil
    return true
end

local function orderCb(source, d)
    local s = lockerAt(source, d, false)
    if not s then return false, 'Go to a locker room first' end
    local jobId = tonumber(d.jobId)
    if not canDesign(source, jobId) then return false, 'Only its leaders change uniforms' end
    for i, id in ipairs(type(d.ids) == 'table' and d.ids or {}) do
        local u = U[tonumber(id) or 0]
        if u and u.jobId == jobId and i <= 60 then u.sort = i MySQL.update('UPDATE `es_jobs_uniforms` SET `sort` = ? WHERE `id` = ?', { i, u.id }) end
    end
    return true
end

--- the officer's own changes to the uniform they wear (WHIP's editor, clothes and props): kept for the shift only
local function adjustCb(source, d)
    if G().adjust == false then return false, 'Uniforms cannot be adjusted here' end
    local s = lockerAt(source, d, false)
    if not s then return false, 'Go to a locker room first' end
    local cid = WC:GetCharId(source)
    if not worn[cid] then return false, 'Put a uniform on first' end
    if type(d.look) ~= 'table' then return false, 'Nothing to keep' end
    local ok, kept = WC:SetPlayerAppearance(source, d.look, { only = ONLY })
    if not ok then return false, kept end
    return true
end

--- a leader opening an existing uniform in the editor: it is put on first (the editor starts from the saved look)
local function tryOnCb(source, d)
    local s, st, me = lockerAt(source, d, false)
    if not s then return false, st end
    local u = U[tonumber(d.id) or 0]
    if not u then return false, 'That uniform is gone' end
    if not canDesign(source, u.jobId) then return false, 'Only its leaders change uniforms' end
    local look, why = savedLook(source)
    if not look then return false, why end
    if bodyOf(look.model) ~= u.body then return false, ('That one is for a %s character: ask a %s leader to change it'):format(u.body, u.body) end
    return wear(source, u, u.jobId) and { id = u.id } or false
end

function ESJ.registerUniforms(cb)
    cb('es_jobs:uni:list', 600, list)
    cb('es_jobs:uni:wear', 1500, wearCb)
    cb('es_jobs:uni:own', 1500, ownCb)
    cb('es_jobs:uni:save', 1500, saveCb)
    cb('es_jobs:uni:delete', 1000, deleteCb)
    cb('es_jobs:uni:order', 800, orderCb)
    cb('es_jobs:uni:adjust', 1500, adjustCb)
    cb('es_jobs:uni:tryOn', 1500, tryOnCb)
end

-- clocking off (or logging out, which clocks off): their own clothes, if the uniform was that job's
AddEventHandler('whip_core:job:clockedOff', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' or not e.source or not e.charId then return end
    local w = worn[e.charId]
    if not w or G().restoreOnClockOff == false then return end
    if w.jobId and e.jobId and w.jobId ~= e.jobId then return end
    CreateThread(function() ESJ.ownClothes(e.source) end)
end)

-- a character who still has a row (the server went down while they wore a uniform): their clothes back as they load
AddEventHandler('whip_core:player:loaded', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' or not e.source or not e.charId then return end
    if not worn[e.charId] or G().restoreOnClockOff == false then return end
    SetTimeout(1500, function() ESJ.ownClothes(e.source, true) end)
end)
