-- whip_jobs: stations. A station is a named place shared by one or more departments and businesses (its `jobs`, by
-- WHIP jobId), with spots: duty, armory, locker, garage, helipad, boat dock (and later impound, hospital, court).
-- Each spot has a point, an optional ped and, by type, stock (armory), vehicles and spawn points (garages).
-- Every change keeps the previous version in es_jobs_station_history: undo, restore, and a deleted station comes back.
ESJ = ESJ or {}
local WC = exports.whip_core
ESJ.Stations = ESJ.Stations or {}
local L = ESJ.LIMITS

local function decode(s, def) local ok, v = pcall(json.decode, s or '') return (ok and v ~= nil) and v or def end

function ESJ.loadStations()
    local rows = MySQL.query.await('SELECT `id`,`name`,`jobs`,`blip`,`spots`,`rev` FROM `es_jobs_stations`')
    if not rows then return false end
    ESJ.Stations = {}
    for _, r in ipairs(rows) do
        ESJ.Stations[r.id] = { id = r.id, name = r.name, jobs = decode(r.jobs, {}), blip = decode(r.blip, { show = 'everyone' }),
            spots = decode(r.spots, {}), rev = r.rev }
    end
    return true
end

-- ---------------------------------------------------------------- who may edit
--- the jobIds they may put a station under (admins: every org)
function ESJ.manageable(source)
    local admin = ESJ.isAdmin(source)
    local out = {}
    for _, o in ipairs(ESJ.orgs()) do
        if admin or WC:HasJobPermission(source, o.jobId, 'canManage') == true then out[o.jobId] = true end
    end
    return out, admin
end

--- an admin, or a leader (canManage) at one of the station's departments or businesses
function ESJ.canEdit(source, st)
    local mine, admin = ESJ.manageable(source)
    if admin then return true end
    for _, j in ipairs(st.jobs or {}) do if mine[j] then return true end end
    return false
end

-- ---------------------------------------------------------------- checks
local itemCache, itemAt = nil, 0
local function items()
    if not itemCache or GetGameTimer() - itemAt > 60000 then itemCache, itemAt = WC:GetItemDefs() or {}, GetGameTimer() end
    return itemCache
end

local function cleanSpot(s, i)
    if type(s) ~= 'table' then return nil, ('Spot %d is broken'):format(i) end
    local T = ESJ.TYPE[s.type]
    if not T then return nil, ('Spot %d has no type'):format(i) end
    if (T.phase or 1) > ESJ.PHASE then return nil, ('%s spots come in a later update'):format(T.label) end
    local p = ESJ.point(s)
    if not p then return nil, ('Spot %d (%s) is not placed'):format(i, T.label) end
    local out = { id = ESJ.name(s.id, true) or ('s' .. i .. '_' .. math.random(1000, 9999)), type = T.key,
        label = ESJ.trim(s.label):sub(1, L.label), x = p.x, y = p.y, z = p.z, h = p.h }
    if out.label == '' then out.label = T.label end
    if s.ped and s.ped ~= '' then
        out.ped = ESJ.name(s.ped)
        if not out.ped then return nil, ('%s: the ped is not a model name'):format(out.label) end
    else out.ped = false end
    if T.stock then
        out.stock = {}
        local defs = items()
        for j, it in ipairs(type(s.stock) == 'table' and s.stock or {}) do
            if j > L.stock then break end
            local key = ESJ.name(it.item, true)
            if not key or not defs[key] then return nil, ('%s: "%s" is not an item'):format(out.label, tostring(it.item)) end
            out.stock[#out.stock + 1] = { item = key, min = ESJ.int(it.min, 0, 100, 0), max = ESJ.int(it.max, 1, (Config.Gear or {}).armoryMax or 10, 1) }
        end
    end
    if T.spawns then
        out.spawns, out.vehicles = {}, {}
        for j, sp in ipairs(type(s.spawns) == 'table' and s.spawns or {}) do
            if j > L.spawns then break end
            local q = ESJ.point(sp)
            if q then out.spawns[#out.spawns + 1] = q end
        end
        for j, v in ipairs(type(s.vehicles) == 'table' and s.vehicles or {}) do
            if j > L.vehicles then break end
            local m = ESJ.name(v.model)
            if not m then return nil, ('%s: "%s" is not a vehicle model'):format(out.label, tostring(v.model)) end
            local lbl = ESJ.trim(v.label):sub(1, L.label)
            out.vehicles[#out.vehicles + 1] = { model = m, label = lbl ~= '' and lbl or m, min = ESJ.int(v.min, 0, 100, 0),
                livery = ESJ.int(v.livery, -1, 60, -1), extras = v.extras == true or nil }
        end
    end
    return out
end

local BLIP_SHOW = { everyone = true, members = true, none = true }
local function cleanStation(source, d, old)
    if type(d) ~= 'table' then return nil, 'Nothing to save' end
    local name = ESJ.trim(d.name):sub(1, L.name)
    if #name < 2 then return nil, 'Name the station' end
    local mine, admin = ESJ.manageable(source)
    local known = {}
    for _, o in ipairs(ESJ.orgs()) do known[o.jobId] = true end
    local jobs, seen = {}, {}
    for _, j in ipairs(type(d.jobs) == 'table' and d.jobs or {}) do
        j = tonumber(j)
        if j and known[j] and not seen[j] then seen[j] = true jobs[#jobs + 1] = j end
    end
    if not admin then
        -- a leader may add or remove only their own departments; others already on the station stay
        local before = {}
        for _, j in ipairs(old and old.jobs or {}) do before[j] = true end
        for _, j in ipairs(jobs) do if not before[j] and not mine[j] then return nil, 'You can only add departments you lead' end end
        for j in pairs(before) do if not seen[j] and not mine[j] then jobs[#jobs + 1] = j seen[j] = true end end
        local any = false
        for _, j in ipairs(jobs) do if mine[j] then any = true end end
        if not any then return nil, 'Keep one of your own departments on it' end
    end
    local b = type(d.blip) == 'table' and d.blip or {}
    local blip = { show = BLIP_SHOW[b.show] and b.show or 'everyone', sprite = ESJ.int(b.sprite, 1, 900, (Config.Stations or {}).blipSprite or 60),
        color = ESJ.int(b.color, 0, 85, (Config.Stations or {}).blipColor or 29), scale = ESJ.num(b.scale, 0.4, 1.5) or 0.8 }
    local spots, ids = {}, {}
    for i, s in ipairs(type(d.spots) == 'table' and d.spots or {}) do
        if i > L.spots then return nil, ('A station has %d spots at most'):format(L.spots) end
        local c, why = cleanSpot(s, i)
        if not c then return nil, why end
        while ids[c.id] do c.id = c.id .. 'x' end
        ids[c.id] = true
        spots[#spots + 1] = c
    end
    if #jobs == 0 then
        -- a station of public spots only (an impound lot, a hospital) needs no department: an admin's
        local public = admin and #spots > 0
        for _, c in ipairs(spots) do if not (ESJ.TYPE[c.type] and ESJ.TYPE[c.type].public) then public = false end end
        if not public then return nil, 'Pick at least one department or business for this station' end
    end
    return { name = name, jobs = jobs, blip = blip, spots = spots }
end

-- ---------------------------------------------------------------- saving, history
local function snapshot(st, action, charId)
    MySQL.insert.await('INSERT INTO `es_jobs_station_history` (`stationId`,`name`,`snapshot`,`action`,`byCharId`) VALUES (?,?,?,?,?)',
        { st.id, st.name, json.encode({ name = st.name, jobs = st.jobs, blip = st.blip, spots = st.spots }), action, charId })
    local keep = math.max(5, math.floor((Config.Stations or {}).historyKeep or 30))
    MySQL.update.await([[DELETE FROM `es_jobs_station_history` WHERE `stationId` = ? AND `action` <> 'deleted' AND `id` NOT IN
        (SELECT `id` FROM (SELECT `id` FROM `es_jobs_station_history` WHERE `stationId` = ? ORDER BY `id` DESC LIMIT ?) AS k)]], { st.id, st.id, keep })
end

--- what every client gets: stations without the stock lists (those come when someone opens a spot)
function ESJ.publicStations()
    local out = {}
    for _, st in pairs(ESJ.Stations) do
        local spots = {}
        for _, s in ipairs(st.spots) do
            spots[#spots + 1] = { id = s.id, type = s.type, label = s.label, x = s.x, y = s.y, z = s.z, h = s.h, ped = s.ped }
        end
        out[#out + 1] = { id = st.id, name = st.name, jobs = st.jobs, blip = st.blip, spots = spots }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local pushQueued = false
function ESJ.pushStations(target)
    if target then return TriggerClientEvent('whip_jobs:client:stations', target, ESJ.publicStations(), ESJ.orgColors()) end
    if pushQueued then return end
    pushQueued = true
    SetTimeout(250, function()
        pushQueued = false
        TriggerClientEvent('whip_jobs:client:stations', -1, ESJ.publicStations(), ESJ.orgColors())
    end)
end

--- jobId -> { short, name } for prompts and blip names
function ESJ.orgColors()
    local out = {}
    for _, o in ipairs(ESJ.orgs()) do out[tostring(o.jobId)] = { short = o.short, name = o.name, kind = o.kind, color = o.color, type = o.type } end
    return out
end

local function write(st, charId)
    local ok = MySQL.update.await('UPDATE `es_jobs_stations` SET `name`=?,`jobs`=?,`blip`=?,`spots`=?,`rev`=`rev`+1,`updatedBy`=? WHERE `id`=?',
        { st.name, json.encode(st.jobs), json.encode(st.blip), json.encode(st.spots), charId, st.id })
    if ok then st.rev = (st.rev or 0) + 1 end
    return ok
end

local function insert(st, charId, id)
    local newId = MySQL.insert.await('INSERT INTO `es_jobs_stations` (' .. (id and '`id`,' or '') .. '`name`,`jobs`,`blip`,`spots`,`updatedBy`) VALUES (' .. (id and '?,' or '') .. '?,?,?,?,?)',
        (function()
            local v = { st.name, json.encode(st.jobs), json.encode(st.blip), json.encode(st.spots), charId }
            if id then table.insert(v, 1, id) end
            return v
        end)())
    if not newId then return nil end
    st.id, st.rev = id or newId, 1
    ESJ.Stations[st.id] = st
    return st
end

--- a department or business went away: take it off every station (only while es_mdt runs, so a stopped es_mdt
--- never empties stations)
function ESJ.onOrgsChanged()
    if GetResourceState('es_mdt') ~= 'started' then ESJ.pushStations() return end
    local known = {}
    for _, o in ipairs(ESJ.orgs()) do known[o.jobId] = true end
    for _, st in pairs(ESJ.Stations) do
        local keep, gone = {}, false
        for _, j in ipairs(st.jobs) do if known[j] then keep[#keep + 1] = j else gone = true end end
        if gone then
            snapshot(st, 'department removed', nil)
            st.jobs = keep
            write(st, nil)
        end
    end
    ESJ.pushStations()
end

function ESJ.stationsOf(jobId)
    local out = {}
    for _, st in pairs(ESJ.Stations) do
        for _, j in ipairs(st.jobs) do
            if j == jobId then
                local types = {}
                for _, s in ipairs(st.spots) do types[s.type] = (types[s.type] or 0) + 1 end
                out[#out + 1] = { id = st.id, name = st.name, spots = #st.spots, types = types, shared = #st.jobs > 1 }
                break
            end
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

--- a spot by station and spot id
function ESJ.spot(stationId, spotId)
    local st = ESJ.Stations[tonumber(stationId) or 0]
    if not st then return nil end
    for _, s in ipairs(st.spots) do if s.id == spotId then return s, st end end
    return nil, st
end

-- ---------------------------------------------------------------- 0.4.0: the courthouse, once
--- es_mdt (before 2.4.0) had the court clerk window at fixed coords. The first time both run, those desks become a
--- "Courthouse" station of the DOJ departments (a clerk window spot each, the old blip), unless a DOJ spot is already
--- placed. Done once (a resource KVP); the station is then edited like any other.
local MIGRATED = 'whip_jobs:doj_courthouse_migrated'
function ESJ.migrateCourthouse()
    if GetResourceKvpString(MIGRATED) == '1' then return end
    if GetResourceState('es_mdt') ~= 'started' then return end
    for _, st in pairs(ESJ.Stations) do
        for _, s in ipairs(st.spots) do
            if ESJ.TYPE[s.type] and ESJ.TYPE[s.type].doj then SetResourceKvp(MIGRATED, '1') return end
        end
    end
    local ok, C = pcall(function() return exports.es_mdt:GetCourthouse() end)
    if not ok or type(C) ~= 'table' then return end   -- an older es_mdt: try again when it is updated
    local jobs = {}
    for _, o in ipairs(ESJ.orgs()) do if o.kind == 'dept' and o.type == 'doj' and o.jobId then jobs[#jobs + 1] = o.jobId end end
    if #jobs == 0 then return end                      -- no DOJ department yet: wait for one (es_mdt restarts, or next start)
    local spots = {}
    for i, d in ipairs(C.desks or {}) do
        local p = ESJ.point({ x = d.x, y = d.y, z = (tonumber(d.z) or 0) - 0.98, h = d.h or 0.0 })   -- es_mdt kept chest height
        if p then
            spots[#spots + 1] = { id = 'clerk' .. i, type = 'court_clerk', label = ESJ.trim(d.label) ~= '' and ESJ.trim(d.label):sub(1, L.label) or 'Court clerk',
                x = p.x, y = p.y, z = p.z, h = p.h, ped = ESJ.typePeds().court_clerk or 'a_f_y_business_01' }
        end
    end
    if #spots == 0 then SetResourceKvp(MIGRATED, '1') return end
    local b = type(C.blip) == 'table' and C.blip or {}
    local st = { name = (ESJ.trim(C.label) ~= '' and ESJ.trim(C.label) or 'Courthouse'):sub(1, L.name), jobs = jobs,
        blip = { show = 'everyone', sprite = ESJ.int(b.sprite, 1, 900, 419), color = ESJ.int(b.color, 0, 85, 5), scale = ESJ.num(b.scale, 0.4, 1.5) or 0.8 },
        spots = spots }
    local newId = MySQL.insert.await('INSERT INTO `es_jobs_stations` (`name`,`jobs`,`blip`,`spots`,`updatedBy`) VALUES (?,?,?,?,NULL)',
        { st.name, json.encode(st.jobs), json.encode(st.blip), json.encode(st.spots) })
    if not newId then print('^3[whip_jobs] could not make the Courthouse station (database error); trying again next start^7') return end
    st.id, st.rev = newId, 1
    ESJ.Stations[st.id] = st
    SetResourceKvp(MIGRATED, '1')
    print(('^2[whip_jobs] the courthouse clerk window%s moved into station #%d "%s" (DOJ). Edit it in /w -> Stations.^7'):format(#spots > 1 and 's' or '', st.id, st.name))
    ESJ.pushStations()
    TriggerEvent('whip_jobs:server:dojSpots')
end

--- 0.4.0: does any station have a DOJ spot of this type (es_mdt asks, so it drops its own fallback desk)
function ESJ.hasSpotType(key)
    for _, st in pairs(ESJ.Stations) do
        for _, s in ipairs(st.spots) do if s.type == key then return true end end
    end
    return false
end
exports('HasSpotType', function(key) return ESJ.hasSpotType(key) end)

-- ---------------------------------------------------------------- callbacks
function ESJ.registerStations(cb)
    cb('whip_jobs:st:list', 300, function(source)
        local mine, admin = ESJ.manageable(source)
        if not admin and next(mine) == nil then return false, 'Only admins and department or business leaders can set up stations' end
        local list = {}
        for _, st in pairs(ESJ.Stations) do
            local can = admin
            if not can then for _, j in ipairs(st.jobs) do if mine[j] then can = true end end end
            list[#list + 1] = { id = st.id, name = st.name, jobs = st.jobs, blip = st.blip, spots = st.spots, rev = st.rev, canEdit = can }
        end
        table.sort(list, function(a, b) return a.id < b.id end)
        local orgs = ESJ.orgs()
        for _, o in ipairs(orgs) do
            o.mine = mine[o.jobId] == true
            o.ranks = {}
            for _, r in ipairs(WC:GetJobRoles(o.jobId) or {}) do o.ranks[#o.ranks + 1] = { name = r.name, level = r.level or 0 } end
            table.sort(o.ranks, function(a, b) return a.level < b.level end)
        end
        local itemList = {}
        for key, def in pairs(items()) do
            itemList[#itemList + 1] = { key = key, label = def.name or def.label or key, type = def.type, img = def.img }
        end
        table.sort(itemList, function(a, b) return a.label:lower() < b.label:lower() end)
        local deleted = MySQL.query.await([[SELECT h.`id`,h.`stationId`,h.`name`,UNIX_TIMESTAMP(h.`at`) AS `at` FROM `es_jobs_station_history` h
            WHERE h.`action` = 'deleted' AND NOT EXISTS (SELECT 1 FROM `es_jobs_stations` s WHERE s.`id` = h.`stationId`)
            ORDER BY h.`id` DESC LIMIT 20]]) or {}
        return { stations = list, orgs = orgs, types = ESJ.TYPES, items = itemList, phase = ESJ.PHASE, admin = admin, deleted = deleted,
            pedList = (Config.Stations or {}).pedList or {}, typePeds = ESJ.typePeds(), starter = ESJ.STARTER, limits = L, armoryMax = (Config.Gear or {}).armoryMax or 10,
            blipDefault = { sprite = (Config.Stations or {}).blipSprite or 60, color = (Config.Stations or {}).blipColor or 29 } }
    end)

    cb('whip_jobs:st:save', 700, function(source, d)
        local id = tonumber(d.id)
        local old = id and ESJ.Stations[id]
        if id and not old then return false, 'That station was deleted' end
        if old and not ESJ.canEdit(source, old) then return false, 'That station is not yours to change' end
        if old and tonumber(d.rev) and tonumber(d.rev) ~= old.rev then return false, 'Someone else just changed this station: reopen it to see their changes' end
        local clean, why = cleanStation(source, d, old)
        if not clean then return false, why end
        local cid = WC:GetCharId(source)
        local st
        if old then
            snapshot(old, 'before ' .. (ESJ.trim(d.action) ~= '' and ESJ.trim(d.action):sub(1, 30) or 'edit'), cid)
            old.name, old.jobs, old.blip, old.spots = clean.name, clean.jobs, clean.blip, clean.spots
            if not write(old, cid) then return false, 'Could not save (database error)' end
            st = old
        else
            st = insert(clean, cid)
            if not st then return false, 'Could not save (database error)' end
        end
        WC:LogActivity(source, 'whip_jobs_station', { detail = ('%s: %s (%d spots)'):format(old and 'edit' or 'new', st.name, #st.spots) })
        ESJ.pushStations()
        return { id = st.id, rev = st.rev, spots = st.spots }
    end)

    cb('whip_jobs:st:delete', 1500, function(source, d)
        local st = ESJ.Stations[tonumber(d.id) or 0]
        if not st then return false, 'No such station' end
        if not ESJ.canEdit(source, st) then return false, 'That station is not yours to delete' end
        snapshot(st, 'deleted', WC:GetCharId(source))
        MySQL.update.await('DELETE FROM `es_jobs_stations` WHERE `id` = ?', { st.id })
        ESJ.Stations[st.id] = nil
        WC:LogActivity(source, 'whip_jobs_station', { detail = 'deleted: ' .. st.name })
        ESJ.pushStations()
        return true
    end)

    cb('whip_jobs:st:history', 400, function(source, d)
        local id = tonumber(d.id) or 0
        local st = ESJ.Stations[id]
        if st and not ESJ.canEdit(source, st) then return false, 'Not yours' end
        if not st and not ESJ.isAdmin(source) then return false, 'Only admins can see deleted stations' end
        local rows = MySQL.query.await([[SELECT `id`,`name`,`action`,`byCharId`,UNIX_TIMESTAMP(`at`) AS `at`, `snapshot` FROM `es_jobs_station_history`
            WHERE `stationId` = ? ORDER BY `id` DESC LIMIT 60]], { id }) or {}
        local ids, seen = {}, {}
        for _, r in ipairs(rows) do if r.byCharId and not seen[r.byCharId] then seen[r.byCharId] = true ids[#ids + 1] = r.byCharId end end
        local names = (#ids > 0 and WC:GetCharacterNames(ids)) or {}
        for _, r in ipairs(rows) do
            local s = decode(r.snapshot, {})
            r.spots, r.snapshot = #(s.spots or {}), nil
            r.who = r.byCharId and (names[r.byCharId] or ('#' .. r.byCharId)) or 'WHIP'
        end
        return rows
    end)

    --- put a station back as it was in a history row (also brings a deleted station back, under its old number)
    cb('whip_jobs:st:restore', 1500, function(source, d)
        local h = MySQL.single.await('SELECT `stationId`,`snapshot`,`action` FROM `es_jobs_station_history` WHERE `id` = ?', { tonumber(d.historyId) or 0 })
        if not h then return false, 'That version is gone' end
        local st = ESJ.Stations[h.stationId]
        if st and not ESJ.canEdit(source, st) then return false, 'Not yours' end
        if not st and not ESJ.isAdmin(source) then return false, 'Only admins can bring a deleted station back' end
        local snap = decode(h.snapshot, nil)
        if not snap then return false, 'That version is damaged' end
        -- the departments it listed that still exist; spots that no longer pass the checks are dropped, not refused
        local known = {}
        for _, o in ipairs(ESJ.orgs()) do known[o.jobId] = true end
        local jobs = {}
        for _, j in ipairs(snap.jobs or {}) do if known[j] then jobs[#jobs + 1] = j end end
        local spots = {}
        for i, s in ipairs(snap.spots or {}) do local c = cleanSpot(s, i) if c then spots[#spots + 1] = c end end
        local cid = WC:GetCharId(source)
        if st then
            snapshot(st, 'before restore', cid)
            st.name, st.jobs, st.blip, st.spots = snap.name or st.name, jobs, snap.blip or st.blip, spots
            write(st, cid)
        else
            st = insert({ name = snap.name or 'Station', jobs = jobs, blip = snap.blip or { show = 'everyone' }, spots = spots }, cid, h.stationId)
            if not st then return false, 'Could not bring it back (database error)' end
        end
        ESJ.pushStations()
        return { id = st.id, rev = st.rev }
    end)

    --- undo: the newest history row of this station
    cb('whip_jobs:st:undo', 800, function(source, d)
        local st = ESJ.Stations[tonumber(d.id) or 0]
        if not st then return false, 'No such station' end
        if not ESJ.canEdit(source, st) then return false, 'Not yours' end
        local h = MySQL.single.await([[SELECT `id` FROM `es_jobs_station_history` WHERE `stationId` = ? AND `action` LIKE 'before %' AND `action` <> 'before restore'
            ORDER BY `id` DESC LIMIT 1]], { st.id })
        if not h then return false, 'Nothing to undo' end
        local snap = MySQL.single.await('SELECT `snapshot` FROM `es_jobs_station_history` WHERE `id` = ?', { h.id })
        local s = snap and decode(snap.snapshot, nil)
        if not s then return false, 'Nothing to undo' end
        local spots = {}
        for i, x in ipairs(s.spots or {}) do local c = cleanSpot(x, i) if c then spots[#spots + 1] = c end end
        local known = {}
        for _, o in ipairs(ESJ.orgs()) do known[o.jobId] = true end
        local jobs = {}
        for _, j in ipairs(s.jobs or {}) do if known[j] then jobs[#jobs + 1] = j end end
        st.name, st.jobs, st.blip, st.spots = s.name or st.name, jobs, s.blip or st.blip, spots
        write(st, WC:GetCharId(source))
        MySQL.update.await('DELETE FROM `es_jobs_station_history` WHERE `id` = ?', { h.id })   -- undo again goes one further back
        ESJ.pushStations()
        return { id = st.id, rev = st.rev, spots = st.spots, name = st.name, jobs = st.jobs, blip = st.blip }
    end)

    --- a backup of every station (admins): the page offers it as a file to keep
    cb('whip_jobs:st:export', 3000, function(source)
        if not ESJ.isAdmin(source) then return false, 'Admins only' end
        local out = {}
        for _, st in pairs(ESJ.Stations) do out[#out + 1] = { id = st.id, name = st.name, jobs = st.jobs, blip = st.blip, spots = st.spots } end
        table.sort(out, function(a, b) return a.id < b.id end)
        return { whip_jobs = '0.1', at = os.time(), stations = out }
    end)

    --- bring a backup back (admins). Stations with the same number are replaced (their current version kept in history).
    cb('whip_jobs:st:import', 5000, function(source, d)
        if not ESJ.isAdmin(source) then return false, 'Admins only' end
        local data = type(d.text) == 'string' and #d.text < 2000000 and decode(d.text, nil)
        if type(data) ~= 'table' or type(data.stations) ~= 'table' then return false, 'That is not an whip_jobs station backup' end
        local cid, n, skipped = WC:GetCharId(source), 0, {}
        for _, s in ipairs(data.stations) do
            local clean, why = cleanStation(source, s, nil)
            if not clean then
                -- departments that no longer exist: keep the station, under nobody, for an admin to reassign
                if why and why:find('at least one department') then
                    clean = cleanStation(source, { name = s.name, jobs = {}, blip = s.blip, spots = s.spots }, nil)
                end
            end
            if clean or (s.name and ESJ.trim(s.name) ~= '') then
                clean = clean or { name = ESJ.trim(s.name):sub(1, L.name), jobs = {}, blip = { show = 'none' }, spots = {} }
                local id = tonumber(s.id)
                local old = id and ESJ.Stations[id]
                if old then
                    snapshot(old, 'before import', cid)
                    old.name, old.jobs, old.blip, old.spots = clean.name, clean.jobs, clean.blip, clean.spots
                    write(old, cid)
                else
                    local exists = id and MySQL.scalar.await('SELECT 1 FROM `es_jobs_stations` WHERE `id` = ?', { id })
                    insert(clean, cid, (id and not exists) and id or nil)
                end
                n = n + 1
            else skipped[#skipped + 1] = tostring(s.name or '?') end
        end
        ESJ.pushStations()
        WC:LogActivity(source, 'whip_jobs_station', { detail = ('import: %d stations'):format(n) })
        return { count = n, skipped = skipped }
    end)

    --- the editor's "go there"
    cb('whip_jobs:st:teleport', 800, function(source, d)
        local st = ESJ.Stations[tonumber(d.id) or 0]
        local mine, admin = ESJ.manageable(source)
        if not admin and not (st and ESJ.canEdit(source, st)) and next(mine) == nil then return false, 'Not allowed' end
        local p = ESJ.point(d)
        if not p then return false, 'No point' end
        if not admin then
            -- leaders go only to their own stations' spots
            local ok = false
            if st then for _, s in ipairs(st.spots) do if ESJ.dist(s, p) < 30 then ok = true end end end
            if not ok then return false, 'Leaders can go to their own stations\' spots' end
        end
        local ped = GetPlayerPed(source)
        if not ped or ped == 0 then return false, 'No player' end
        SetEntityCoords(ped, p.x, p.y, p.z, false, false, false, false)
        SetEntityHeading(ped, p.h)
        return true
    end)
end
