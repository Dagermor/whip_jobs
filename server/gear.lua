-- es_jobs: what a station's spots do. Duty (clock on and off), the armory (equipment by rank, free, logged), the fleet
-- (garage / helipad / boat dock: a temporary vehicle by rank, one each, back at a garage or gone at clock off) and the
-- personal locker. Every action checks, here: the spot exists, they stand at it, and they belong (and, for gear, are on
-- duty) at one of the station's departments or businesses.
ESJ = ESJ or {}
local WC = exports.whip_core
local fleet = {}        -- [charId] = { vehicleId, jobId, model, label, plate, station }
local byVeh = {}        -- [vehicleId] = charId

local function near(source, s, extra)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    local c = GetEntityCoords(ped)
    local reach = ((Config.Stations or {}).reach or 2.0) + (extra or 3.0)
    return #(c - vector3(s.x, s.y, s.z)) <= reach
end

--- their standing at a station: which of its jobs they belong to, where they are on duty, their best on-duty level
local function standing(source, st)
    local mine = WC:GetPlayerJobs(source) or {}
    local out = { jobs = {}, onDuty = {}, level = -1, any = false, anyDuty = false }
    for _, j in ipairs(st.jobs) do
        local m = mine[j]
        if m then
            out.any = true
            out.jobs[#out.jobs + 1] = { jobId = j, role = m.roleName, level = m.roleLevel or 0, onDuty = m.clockedOn == true }
            if m.clockedOn then
                out.anyDuty = true
                out.onDuty[j] = true
                if (m.roleLevel or 0) > out.level then out.level, out.dutyJob = m.roleLevel or 0, j end
            end
        end
    end
    return out
end

--- the spot they asked about, checked: returns spot, station, standing (or false, why)
local function at(source, d, needDuty, extra)
    local s, st = ESJ.spot(d.station, d.spot)
    if not s then return false, 'That spot is gone' end
    if not near(source, s, extra) then return false, 'Go to it first' end
    local me = standing(source, st)
    if ESJ.TYPE[s.type] and ESJ.TYPE[s.type].public then return s, st, me end   -- anyone (the impound clerk, the hospital)
    if not me.any then return false, 'This is for ' .. (ESJ.stationOrgNames(st) or 'its members') end
    if needDuty and not me.anyDuty then return false, 'Clock on first' end
    return s, st, me
end

ESJ.at, ESJ.standing, ESJ.near = at, standing, near

function ESJ.stationOrgNames(st)
    local names = {}
    for _, j in ipairs(st.jobs) do local o = ESJ.orgByJob(j) if o then names[#names + 1] = o.short or o.name end end
    return #names > 0 and table.concat(names, ', ') or nil
end

local function itemInfo(key)
    local def = WC:GetItemDef(key) or {}
    return def.name or def.label or key, def.img or def.imageUrl
end

-- ---------------------------------------------------------------- open a spot
local function openSpot(source, d)
    local s, st = ESJ.spot(d.station, d.spot)
    if not s then return false, 'That spot is gone' end
    local T = ESJ.TYPE[s.type]
    local s2, why, me = at(source, d, false, T and T.spawns and 6.0 or 3.0)
    if not s2 then return false, why end
    local out = { type = s.type, label = s.label, station = st.name, stationId = st.id, spot = s.id, level = me.level, onDuty = me.anyDuty }
    local cid = WC:GetCharId(source)
    if s.type == 'duty' then
        out.jobs = {}
        for _, j in ipairs(me.jobs) do
            local o = ESJ.orgByJob(j.jobId)
            local m, every = ESJ.payProgress(cid, j.jobId)
            local role = WC:GetPlayerRole(source, j.jobId)
            out.jobs[#out.jobs + 1] = { jobId = j.jobId, name = o and o.name or ('Job ' .. j.jobId), short = o and o.short, kind = o and o.kind,
                logoVer = o and o.logoVer, orgId = o and o.id, rank = j.role, onDuty = j.onDuty, payMin = m, payEvery = every,
                pay = role and ESJ.payFor(role.roleId, role.level) or 0, payOn = (Config.Pay or {}).enabled ~= false }
        end
    elseif s.type == 'armory' then
        out.items = {}
        for _, it in ipairs(s.stock or {}) do
            local label, img = itemInfo(it.item)
            out.items[#out.items + 1] = { item = it.item, label = label, img = img, min = it.min, max = it.max,
                have = WC:GetItemCount(source, it.item) or 0, allowed = me.anyDuty and me.level >= it.min }
        end
    elseif ESJ.TYPE[s.type] and ESJ.TYPE[s.type].fleet then
        out.vehicles = {}
        local cat = WC:GetVehicleCatalog() or {}
        for _, v in ipairs(s.vehicles or {}) do
            local c = cat[v.model] or cat[v.model:lower()] or {}
            out.vehicles[#out.vehicles + 1] = { model = v.model, label = v.label, min = v.min, img = c.image or false,
                class = c.class, allowed = me.anyDuty and me.level >= v.min }
        end
        local f = cid and fleet[cid]
        out.mine = f and { label = f.label, plate = f.plate } or false
        out.spawns = #(s.spawns or {})
    elseif s.type == 'locker' then
        out.personal = ((Config.Gear or {}).lockerSlots or 0) > 0
    elseif s.type == 'impound' then
        local cars, why = ESJ.impoundCars(source, s)
        if not cars then return false, why end
        out.cars, out.methods, out.spawns = cars, (Config.ImpoundClerk or {}).methods or { 'bank', 'cash' }, #(s.spawns or {})
    elseif s.type == 'hospital' then
        out.hosp = ESJ.hospitalInfo(source, s, st)
    end
    return out
end

-- ---------------------------------------------------------------- duty
local function duty(source, d)
    local s, st, me = at(source, d, false)
    if not s then return false, st end
    if s.type ~= 'duty' then return false, 'Clock on at a duty desk' end
    local jobId = tonumber(d.jobId)
    local ok = false
    for _, j in ipairs(me.jobs) do if j.jobId == jobId then ok = true end end
    if not ok then return false, 'You do not work there' end
    local o = ESJ.orgByJob(jobId)
    if d.on then
        local r, why = WC:ClockOn(source, jobId)
        if not r then return false, why end
        WC:NotifyPlayer(source, ('On duty: %s'):format(o and o.name or 'job'), 'success')
    else
        local r, why = WC:ClockOff(source, jobId)
        if not r then return false, why end
        WC:NotifyPlayer(source, ('Off duty: %s'):format(o and o.name or 'job'), 'info')
    end
    return true
end

-- ---------------------------------------------------------------- armory
local function armoryTake(source, d)
    local s, st, me = at(source, d, true)
    if not s then return false, st end
    if s.type ~= 'armory' then return false, 'That is not an armory' end
    local it
    for _, x in ipairs(s.stock or {}) do if x.item == d.item then it = x end end
    if not it then return false, 'This armory does not stock that' end
    if me.level < it.min then return false, 'Your rank cannot take that' end
    local have = WC:GetItemCount(source, it.item) or 0
    local n = ESJ.int(d.n, 1, it.max, 1)
    if have + n > it.max then n = it.max - have end
    if n <= 0 then return false, ('You already carry %d (the most is %d)'):format(have, it.max) end
    local fits, why = WC:CanFitItem(source, it.item, n)
    if not fits then return false, why or 'No room' end
    local o = ESJ.orgByJob(me.dutyJob)
    local where, err = WC:AddItem(source, it.item, n, nil, { reason = ('armory %s (%s)'):format(st.name, o and o.short or ''), noDrop = true })
    if not where then return false, err end
    return { have = have + n }
end

local function armoryReturn(source, d)
    local s, st = at(source, d, false)
    if not s then return false, st end
    if s.type ~= 'armory' then return false, 'That is not an armory' end
    local stocked = false
    for _, x in ipairs(s.stock or {}) do if x.item == d.item then stocked = true end end
    if not stocked then return false, 'This armory does not take that' end
    local have = WC:GetItemCount(source, d.item) or 0
    local n = math.min(have, ESJ.int(d.n, 1, 1000, 1))
    if n <= 0 then return false, 'You have none' end
    local ok, why = WC:RemoveItem(source, d.item, n, nil, { reason = 'armory return ' .. st.name })
    if not ok then return false, why end
    return { have = have - n }
end

-- ---------------------------------------------------------------- fleet
local function forget(cid)
    local f = fleet[cid]
    if f then byVeh[f.vehicleId] = nil fleet[cid] = nil end
end

local function freeSpawn(s)
    local cars = GetAllVehicles()
    for _, p in ipairs(s.spawns or {}) do
        local clear = true
        for _, v in ipairs(cars) do
            if DoesEntityExist(v) and #(GetEntityCoords(v) - vector3(p.x, p.y, p.z)) < 3.5 then clear = false break end
        end
        if clear then
            for _, pid in ipairs(GetPlayers()) do
                local ped = GetPlayerPed(pid)
                if ped ~= 0 and #(GetEntityCoords(ped) - vector3(p.x, p.y, p.z)) < 1.6 then clear = false break end
            end
        end
        if clear then return p end
    end
    return nil
end

ESJ.freeSpawn = freeSpawn

local function fleetTake(source, d)
    local s, st, me = at(source, d, true, 6.0)
    if not s then return false, st end
    if not (ESJ.TYPE[s.type] and ESJ.TYPE[s.type].fleet) then return false, 'No vehicles here' end
    local v
    for _, x in ipairs(s.vehicles or {}) do if x.model == d.model then v = x end end
    if not v then return false, 'This garage does not have that' end
    if me.level < v.min then return false, 'Your rank cannot take that' end
    local cid = WC:GetCharId(source)
    if fleet[cid] and (Config.Gear or {}).fleetOne ~= false then return false, ('Put your %s back first'):format(fleet[cid].label) end
    if #(s.spawns or {}) == 0 then return false, 'This garage has no parking spots yet: ask a leader to add some' end
    local p = freeSpawn(s)
    if not p then return false, 'Every parking spot is taken: wait for one to clear' end
    local o = ESJ.orgByJob(me.dutyJob)
    local plate = ((o and o.short or 'FLEET'):gsub('[^%w]', ''):upper():sub(1, 4)) .. tostring(math.random(1000, 9999))
    local mins = (Config.Gear or {}).fleetDespawnMinutes or 0
    local id, why = WC:SpawnTempVehicle(v.model, { x = p.x, y = p.y, z = p.z, heading = p.h }, { forSource = source, giveKey = true,
        plate = plate:sub(1, 8), tag = 'es_jobs_fleet', locked = false, idleDespawn = true, secure = true,
        despawnAfter = mins > 0 and mins * 60 or nil })
    if not id then return false, why or 'It could not be brought out' end
    fleet[cid] = { vehicleId = id, jobId = me.dutyJob, model = v.model, label = v.label, plate = plate, station = st.id }
    byVeh[id] = cid
    WC:LogActivity(source, 'es_jobs_fleet', { detail = ('%s %s (%s) at %s'):format(o and o.short or '', v.label, plate, st.name) })
    TriggerClientEvent('es_jobs:client:fleetOut', source, { x = p.x, y = p.y, z = p.z, livery = v.livery, plate = plate })
    return { plate = plate, label = v.label }
end

local function fleetReturn(source, d)
    local s, st = ESJ.spot(d.station, d.spot)
    if not s then return false, 'That spot is gone' end
    local cid = WC:GetCharId(source)
    local f = cid and fleet[cid]
    if not f then return false, 'You have no fleet vehicle out' end
    local pos = WC:GetVehiclePosition(f.vehicleId)
    local range = (Config.Gear or {}).fleetReturnRange or 40.0
    if not near(source, s, 8.0) then return false, 'Go to the garage first' end
    if pos and #(vector3(pos.x, pos.y, pos.z) - vector3(s.x, s.y, s.z)) > range then
        return false, ('Bring the %s back to the garage first'):format(f.label)
    end
    local ok, why = WC:DespawnVehicle(f.vehicleId)
    if not ok then return false, why end
    forget(cid)
    return true
end

AddEventHandler('whip_core:vehicle:released', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' then return end
    local cid = byVeh[e.vehicleId]
    if cid then forget(cid) end
end)

AddEventHandler('whip_core:job:clockedOff', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' then return end
    local f = e.charId and fleet[e.charId]
    if f and f.jobId == e.jobId and (Config.Gear or {}).fleetReturnOnClockOff ~= false then
        CreateThread(function()
            WC:DespawnVehicle(f.vehicleId)
            forget(e.charId)
            if e.source then WC:NotifyPlayer(e.source, ('Your %s went back to the fleet'):format(f.label), 'info') end
        end)
    end
end)

-- ---------------------------------------------------------------- personal locker
local lockerIds = {}
local function lockerOpen(source, d)
    local s, st = at(source, d, false)
    if not s then return false, st end
    if s.type ~= 'locker' then return false, 'That is not a locker room' end
    local G = Config.Gear or {}
    if (G.lockerSlots or 0) <= 0 then return false, 'Personal lockers are off' end
    local cid = WC:GetCharId(source)
    local id = lockerIds[cid]
    if not id then
        -- one locker per character, the same at every station; it has no place of its own (opened from here only)
        local c, why = WC:EnsureContainer('es_jobs:locker:' .. cid, { x = 0.0, y = 0.0, z = -190.0, name = 'Personal locker',
            slots = G.lockerSlots, maxWeight = G.lockerWeight or 40.0, prop = false, requirements = { charIds = { cid } } })
        if not c then return false, why or 'Your locker could not be opened' end
        id = c.containerId or c.id
        lockerIds[cid] = id
        MySQL.insert('INSERT IGNORE INTO `es_jobs_lockers` (`charId`,`containerId`) VALUES (?,?)', { cid, id })
    end
    local ok, why = WC:OpenStore(source, { kind = 'container', id = id }, { skipDistance = true })
    if not ok then return false, why end
    return true
end

function ESJ.fleetOf(cid) return fleet[cid] end

function ESJ.registerGear(cb)
    cb('es_jobs:spot:open', 400, function(source, d) return openSpot(source, d) end)
    cb('es_jobs:duty', 1200, function(source, d) return duty(source, d) end)
    cb('es_jobs:armory:take', 350, function(source, d) return armoryTake(source, d) end)
    cb('es_jobs:armory:return', 350, function(source, d) return armoryReturn(source, d) end)
    cb('es_jobs:fleet:take', 2500, function(source, d) return fleetTake(source, d) end)
    cb('es_jobs:fleet:return', 1500, function(source, d) return fleetReturn(source, d) end)
    cb('es_jobs:locker:open', 1000, function(source, d) return lockerOpen(source, d) end)
end

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    fleet, byVeh = {}, {}   -- WHIP removes our temporary vehicles itself
end)
