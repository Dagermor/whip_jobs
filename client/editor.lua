-- es_jobs: the station editor's game side. Placing a spot or a parking space: WHIP's PlacePoint ghost (a ped, or the
-- vehicle itself when WHIP can show one; otherwise stand or park where it goes and use "my position"). Teleport to a
-- spot, and a check that a parking space is clear and on the ground. Points are stored at the feet / on the ground.
ESJ = ESJ or {}
local placing = nil   -- 'stationId:spotId' while a spot's ghost is out (its real ped steps aside)

function ESJ.editing(stationId, spotId) return placing == (stationId .. ':' .. spotId) end

function ESJ.openEditor(opts)
    opts = type(opts) == 'table' and opts or {}
    CreateThread(function()
        local ok, r = ESJ.call('es_jobs:st:list', {})
        if not ok then Whip.core:Notify(r, 'error') return end
        r.focusJob = tonumber(opts.jobId)
        r.focusStation = tonumber(opts.stationId)
        if opts.new then r.startNew = true end
        if opts.starter then r.startNew, r.startStarter = true, true end   -- 0.4.0: a new department's usual spots, placed in turn
        ESJ.openUI('stations', r)
    end)
end

local function feet()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then
        local c = GetEntityCoords(veh)
        local okg, gz = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
        return { x = c.x, y = c.y, z = okg and gz or (c.z - 0.5), h = GetEntityHeading(veh), vehicle = true }
    end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z - 0.98, h = GetEntityHeading(ped) }
end

local function round(p) local r = function(n) return math.floor(n * 100 + 0.5) / 100 end return { x = r(p.x), y = r(p.y), z = r(p.z), h = r((p.h or p.w or 0.0) % 360) } end

--- hide the page, let WHIP's ghost take the screen, come back with the point
local function placeWith(o)
    SendNUIMessage({ action = 'hide', on = true })
    ESJPAD.pause(true)
    SetNuiFocus(false, false)
    pcall(function() exports.whip_core:SetScreenOpen(false) end)
    local ok, p, why = pcall(function() return exports.whip_core:PlacePoint(o) end)
    pcall(function() exports.whip_core:SetScreenOpen(true) end)
    ESJPAD.pause(false)
    if not ESJPAD.owns or not ESJPAD.owns() then SetNuiFocus(true, true) end
    SendNUIMessage({ action = 'hide', on = false })
    if not ok then return nil, 'WHIP could not place it here' end
    return p, why
end

RegisterNUICallback('esj_place', function(d, cb)
    d = type(d) == 'table' and d or {}
    CreateThread(function()
        local at
        if tonumber(d.x) then at = { x = d.x + 0.0, y = d.y + 0.0, z = d.z + 0.0, w = (tonumber(d.h) or 0.0) + 0.0 } end
        placing = (d.station and d.spot) and (d.station .. ':' .. d.spot) or nil
        if placing then ESJ.refreshPeds(d.station, d.spot) end
        local model = type(d.model) == 'string' and d.model ~= '' and d.model or nil
        local p, why
        if d.vehicle and model then
            p, why = placeWith({ at = at, model = model, ped = false, label = d.label or 'Parking space' })
            if not p and why == 'model' then
                -- WHIP cannot ghost this vehicle: a small marker instead, the player parks the space themselves
                p, why = placeWith({ at = at, label = d.label or 'Parking space' })
            end
        else
            p, why = placeWith({ at = at, model = model, ped = model ~= nil, label = d.label or 'Spot' })
        end
        placing = nil
        if not p then return cb({ ok = false, why = why or 'cancelled' }) end
        cb({ ok = true, point = round(p) })
    end)
end)

RegisterNUICallback('esj_myPos', function(_, cb) cb({ ok = true, point = round(feet()) }) end)

RegisterNUICallback('esj_teleport', function(d, cb)
    d = type(d) == 'table' and d or {}
    CreateThread(function()
        local ok, why = ESJ.call('es_jobs:st:teleport', { id = d.station, x = d.x, y = d.y, z = (tonumber(d.z) or 0) + 0.5, h = d.h })
        cb({ ok = ok, why = (not ok) and why or nil })
    end)
end)

--- is a parking space usable: on the ground, out of the water, and nothing standing in it now
RegisterNUICallback('esj_checkSpawn', function(d, cb)
    d = type(d) == 'table' and d or {}
    local x, y, z = tonumber(d.x), tonumber(d.y), tonumber(d.z)
    if not (x and y and z) then return cb({ ok = false }) end
    local warn = {}
    local me = GetEntityCoords(PlayerPedId())
    if #(me - vector3(x, y, z)) > 300.0 then return cb({ ok = true, far = true, warn = {} }) end
    local okg, gz = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
    if not okg then warn[#warn + 1] = 'No ground under it'
    elseif math.abs(gz - z) > 1.5 then warn[#warn + 1] = ('The ground is %.1f m %s'):format(math.abs(gz - z), gz < z and 'below' or 'above') end
    local water, wz = GetWaterHeight(x, y, z)
    if d.kind ~= 'boat' and water and wz > z then warn[#warn + 1] = 'It is under water' end
    if d.kind == 'boat' and not (water and wz >= z - 1.0) then warn[#warn + 1] = 'A boat needs water here' end
    if IsAnyVehicleNearPoint(x, y, z, 2.5) then warn[#warn + 1] = 'A vehicle is in the space right now' end
    CreateThread(function()
        local ray = StartShapeTestCapsule(x, y, z + 0.6, x, y, z + 2.0, 1.2, 16, PlayerPedId(), 7)
        local status, hit = 1, 0
        local t = GetGameTimer() + 500
        repeat Wait(0) status, hit = GetShapeTestResult(ray) until status ~= 1 or GetGameTimer() > t
        if status == 2 and hit == 1 then warn[#warn + 1] = 'Something solid is in the way' end
        cb({ ok = true, warn = warn })
    end)
end)

--- 0.4.0: what "Add the usual spots" gives a department of this type, for es_mdt's New department page:
--- { { key, label, icon, hint, ped } } (the ped each spot starts with; changed per spot in the station editor)
exports('GetStarter', function(kind)
    local P = (Config.Stations or {}).peds or {}
    local out = {}
    for _, k in ipairs((ESJ.STARTER or {})[kind] or {}) do
        local t = ESJ.TYPE[k]
        if t and (t.phase or 1) <= ESJ.PHASE then
            local ped = false
            if t.ped then ped = (t.pedKey and P[t.pedKey]) or P[kind] or P.none or 's_m_m_security_01' end
            out[#out + 1] = { key = k, label = (t.label:gsub(':.*$', '')), icon = t.icon, hint = t.hint, ped = ped }
        end
    end
    return out
end)
