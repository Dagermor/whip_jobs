-- es_jobs: start-up, the callback wrapper, commands, exports.
ESJ = ESJ or {}
local WC = exports.whip_core

--- every page call: SecureCallback 'es_jobs:...' with one table argument, rate limited, checked by hand in each handler
local function cb(name, rate, fn, burst)
    Whip.core:SecureCallback(name, { rateLimit = rate or 300, burst = burst or 6, sheet = 'light', params = { { 'd', 'any' } } },
        function(source, _, d)
            if not WC:GetCharId(source) then return false, 'Load a character first' end
            return fn(source, type(d) == 'table' and d or {})
        end)
end

local loaded = false
Whip.register(function()
    local ok, why = ESJ.ensureTables()
    if not ok then Whip.startProblem('tables: %s', tostring(why)) return end
    if not (ESJ.loadBusinesses() and ESJ.loadStations() and ESJ.loadPay() and ESJ.loadUniforms()) then Whip.startProblem('could not read the es_jobs tables') return end
    ESJ.registerBusiness(cb)
    ESJ.registerStations(cb)
    ESJ.registerGear(cb)
    ESJ.registerPay(cb)
    ESJ.registerUniforms(cb)
    ESJ.registerPolice(cb)
    ESJ.registerImpound(cb)
    ESJ.registerEms(cb)
    cb('es_jobs:st:public', 1500, function(source)
        return { stations = ESJ.publicStations(), orgs = ESJ.orgColors() }
    end)
    cb('es_jobs:me', 800, function(source)
        local mine, admin = ESJ.manageable(source)
        return { admin = admin, leads = next(mine) ~= nil }
    end)
    loaded = true
    ESJ.pushStations()
    SetTimeout(5000, ESJ.migrateCourthouse)   -- 0.4.0: es_mdt's old hard-coded clerk window becomes a DOJ station
end)
AddEventHandler('onResourceStart', function(r) if r == 'es_mdt' and loaded then SetTimeout(6000, ESJ.migrateCourthouse) end end)

-- pay: one tick a minute (started once; the tick itself reads Config live)
CreateThread(function()
    while true do
        Wait(60000)
        if loaded then
            local ok, err = pcall(ESJ.payTick)
            if not ok then print(('^3[es_jobs] pay: %s^7'):format(tostring(err))) end
        end
    end
end)

AddEventHandler('whip_core:player:loaded', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' or not e.source then return end
    if loaded then ESJ.pushStations(e.source) end
end)

-- a business's job changed or went away in WHIP itself (/whip admin): keep our row in step
AddEventHandler('whip_core:job:deleted', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' then return end
    for id, b in pairs(ESJ.Biz) do
        if b.jobId == e.jobId then
            MySQL.update('DELETE FROM `es_jobs_businesses` WHERE `id` = ?', { id })
            ESJ.Biz[id], ESJ.BizLogo[id] = nil, nil
            SetTimeout(500, ESJ.onOrgsChanged)
        end
    end
end)
AddEventHandler('whip_core:job:updated', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' then return end
    for _, b in pairs(ESJ.Biz) do
        if b.jobId == e.jobId and e.ownerCharId and e.ownerCharId ~= b.ownerCharId then
            b.ownerCharId = e.ownerCharId
            MySQL.update('UPDATE `es_jobs_businesses` SET `ownerCharId` = ? WHERE `id` = ?', { e.ownerCharId, b.id })
        end
    end
end)

-- ---------------------------------------------------------------- commands
CreateThread(function()
    Whip.ready()
    -- 0.2.0: no /stations for players. Admins open the editor from the WHIP admin menu (/w -> Stations, or /whip ->
    -- Settings -> Jobs says where); department leaders from Departments -> Locations; business owners from /business.
    Whip.command(Config.BusinessCommand or 'business', { console = false }, function(source)
        TriggerClientEvent('es_jobs:client:open', source, { view = 'business' })
    end)
end)

-- ---------------------------------------------------------------- exports
--- every station: { id, name, jobs = { jobId... }, blip, spots = { { id, type, label, x, y, z, h, ped } } }
exports('GetStations', function() return ESJ.publicStations() end)

--- spots of one type ('duty', 'armory', 'garage', ... ), optionally only stations a job uses: { { station, x, y, z, h, label } }
exports('GetSpots', function(spotType, jobId)
    local out = {}
    jobId = tonumber(jobId)
    for _, st in pairs(ESJ.Stations) do
        local ok = not jobId
        if jobId then for _, j in ipairs(st.jobs) do if j == jobId then ok = true end end end
        if ok then
            for _, s in ipairs(st.spots) do
                if not spotType or s.type == spotType then
                    out[#out + 1] = { station = st.id, stationName = st.name, id = s.id, type = s.type, label = s.label, x = s.x, y = s.y, z = s.z, h = s.h,
                        spawns = s.spawns }
                end
            end
        end
    end
    return out
end)

--- the businesses: { { id, jobId, name, short, color, ownerCharId } }
exports('GetBusinesses', function()
    local out = {}
    for _, b in pairs(ESJ.Biz) do out[#out + 1] = { id = b.id, jobId = b.jobId, name = b.name, short = b.short, color = b.color, ownerCharId = b.ownerCharId } end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)

--- record money that came into a department or business account another way (it does not move money)
exports('RecordIncome', function(jobId, amount, kind, note, charId)
    jobId, amount = tonumber(jobId), tonumber(amount)
    if not jobId or not amount then return false end
    ESJ.ledger(jobId, kind or 'income', amount, tonumber(charId), note)
    return true
end)

--- the fleet vehicle a character has out: { vehicleId, jobId, model, label, plate } or nil
exports('GetFleetVehicle', function(charId) local f = ESJ.fleetOf(tonumber(charId)) return f and { vehicleId = f.vehicleId, jobId = f.jobId, model = f.model, label = f.label, plate = f.plate } or nil end)

Whip.sayStarted()
