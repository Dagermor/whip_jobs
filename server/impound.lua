-- es_jobs: the impound clerk. A station spot anyone may use: the owner sees their impounded cars (es_mdt keeps the
-- impound: fees, holds, the lot), pays at the counter, and takes a released car out at the clerk's parking spaces.
ESJ = ESJ or {}
local WC = exports.whip_core
local function mdtOn() return GetResourceState('es_mdt') == 'started' end

local function picture(model)
    local ok, url = pcall(function() return WC:GetVehicleImage(model) end)
    return ok and url or nil
end

--- their cars for the clerk's screen: impounded (owed, held, pending) and released ones still at a lot
function ESJ.impoundCars(source, s)
    if not mdtOn() then return false, 'The impound (es_mdt) is not running' end
    local cid = WC:GetCharId(source)
    local ok, rows = pcall(function() return exports.es_mdt:GetImpounds(cid) end)
    if not ok or type(rows) ~= 'table' then return false, 'The impound records could not be read' end
    local out, seen = {}, {}
    for _, r in ipairs(rows) do
        if not seen[r.vehicleId] then
            seen[r.vehicleId] = true
            local v = WC:GetVehicle(r.vehicleId)
            local atLot = v and v.state == 'garaged' and v.garage == r.lot and not v.reservation
            if r.status == 'held' or r.status == 'pending' or (r.status == 'released' and atLot) then
                out[#out + 1] = { id = r.id, plate = r.plate, label = r.vehicleLabel or (v and v.displayName) or 'Vehicle', model = v and v.model,
                    img = v and picture(v.model) or nil, status = r.status, reason = r.reason, dept = r.dept, lot = r.lotLabel,
                    owe = r.owe and r.owe.total or 0, fee = r.owe and r.owe.fee or 0, storage = r.owe and r.owe.storage or 0, days = r.owe and r.owe.days or 0,
                    held = r.held == true, holdUntil = r.holdUntilTs, canPay = r.status == 'held' and not r.held,
                    canTake = r.status == 'released' and atLot and #(s.spawns or {}) > 0 }
            end
        end
    end
    return out
end

local function clerk(source, d)
    local s, st = ESJ.at(source, d, false, 6.0)
    if not s then return false, st end
    if s.type ~= 'impound' then return false, 'Ask at the impound clerk' end
    return s, st
end

local function pay(source, d)
    local s, st = clerk(source, d)
    if not s then return false, st end
    if not mdtOn() then return false, 'The impound (es_mdt) is not running' end
    local method = d.method == 'cash' and 'cash' or 'bank'
    local okM = false
    for _, m in ipairs((Config.ImpoundClerk or {}).methods or { 'bank', 'cash' }) do if m == method then okM = true end end
    if not okM then return false, 'The clerk does not take that' end
    local ok, r, why = pcall(function() return exports.es_mdt:PayImpound(source, tonumber(d.id), method) end)
    if not ok then return false, 'The impound needs es_mdt 2.2.1 or newer' end
    if not r then return false, why or 'The payment failed' end
    return r
end

local function take(source, d)
    local s, st = clerk(source, d)
    if not s then return false, st end
    local cars, why = ESJ.impoundCars(source, s)
    if not cars then return false, why end
    local car
    for _, c in ipairs(cars) do if c.id == tonumber(d.id) then car = c end end
    if not car then return false, 'That is not one of your impounded cars' end
    if not car.canTake then return false, car.status == 'released' and 'This clerk has no parking spaces' or 'Pay the fees first' end
    local ok2, rows = pcall(function() return exports.es_mdt:GetImpounds(WC:GetCharId(source)) end)
    local row
    for _, r in ipairs(ok2 and rows or {}) do if r.id == car.id then row = r end end
    if not row then return false, 'That record is gone' end
    local p = ESJ.freeSpawn(s)
    if not p then return false, 'Every parking space is taken: wait for one to clear' end
    local okR, whyR = WC:RetrieveVehicle(row.vehicleId, row.lot)
    if not okR then return false, whyR end
    local net, whyS = WC:SpawnVehicle(row.vehicleId, { x = p.x, y = p.y, z = p.z, w = p.h })
    if not net then
        WC:DespawnVehicle(row.vehicleId, { garage = row.lot })
        return false, whyS or 'It could not be brought out'
    end
    WC:LogActivity(source, 'es_jobs_impound', { detail = ('took %s (%s) out of the impound at %s'):format(car.label, car.plate or '?', st.name) })
    return { plate = car.plate, label = car.label }
end

function ESJ.registerImpound(cb)
    cb('es_jobs:imp:pay', 2500, pay)
    cb('es_jobs:imp:take', 2500, take)
end
