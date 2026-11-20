-- whip_jobs: police on this game. With es_jail's cuffs: "Put in car" at a car's door (the person you escort, or the
-- cuffed person beside you), "Take out" at the door of the seat a cuffed person sits in (then you hold them: WHIP's
-- escort). "Police" on a person: breathalyzer and drug swab. Spike strips: use the item to lay one ahead of you; a
-- car driven over it loses the tyres that cross it; officers pick it up again at the strip.
ESJ = ESJ or {}
local WC = Whip.core
local P = Config.Police or {}
local JOBS = {}            -- the police jobIds (from the departments' types)
local added = {}
local STRIPS = {}          -- { id, netId, x, y, z, h }

-- ---------------------------------------------------------------- who is police
local function policeJobs()
    local out = {}
    for jid, o in pairs(ESJ.ORGS or {}) do
        if o.kind == 'dept' and (P.types or {})[o.type] then out[#out + 1] = tonumber(jid) end
    end
    for _, j in ipairs(P.jobs or {}) do out[#out + 1] = j end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

local function cuffedSid(sid)
    if not sid then return false end
    local v = Player(sid).state.esCuffed
    return type(v) == 'string' and v ~= ''
end

local function nearestCuffed(range, inCar)
    local me = PlayerPedId()
    local at = GetEntityCoords(me)
    local best, bestD
    for _, p in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(p)
        if ped ~= me and ped ~= 0 then
            local sid = GetPlayerServerId(p)
            local d = #(GetEntityCoords(ped) - at)
            if d <= range and cuffedSid(sid) and (IsPedInAnyVehicle(ped, false) == (inCar == true)) and (not bestD or d < bestD) then
                best, bestD = sid, d
            end
        end
    end
    return best
end

--- who "Put in car" would seat: the person you escort if cuffed, else the cuffed person beside you
local function toSeat()
    local ok, held = pcall(function() return WC:GetEscortTarget() end)
    if ok and held and cuffedSid(held) then return held, true end
    return nearestCuffed(P.reach or 3.0, false), false
end

-- ---------------------------------------------------------------- door prompts
local DOORS = { door_pside_f = 0, door_dside_r = 1, door_pside_r = 2, door_dside_f = -1 }

local function seatedAt(veh, seat)
    local ped = GetPedInVehicleSeat(veh, seat)
    if ped == 0 or not IsPedAPlayer(ped) then return nil end
    local sid = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
    return cuffedSid(sid) and sid or nil
end

local function addDoor(part, seat)
    local req = { job = JOBS, onDuty = true }
    if seat >= 0 then
        local id = 'esj_pol_in_' .. part
        local ok = WC:AddAction({ id = id, at = { vehiclePart = part }, label = 'Put in car', icon = 'car', first = true, require = req,
            canInteract = function(ctx)
                if not ctx.entity or GetVehicleNumberOfPassengers(ctx.entity) >= GetVehicleMaxNumberOfPassengers(ctx.entity) then return false end
                if not IsVehicleSeatFree(ctx.entity, seat) then return false end
                return toSeat() ~= nil
            end,
            onSelect = function(ctx)
                local sid, holding = toSeat()
                if not sid then return end
                if holding then ExecuteCommand('escort_release') Wait(150) end
                local okc, why = ESJ.call('whip_jobs:pol:seat', { target = sid, netId = NetworkGetNetworkIdFromEntity(ctx.entity), seat = seat })
                if not okc then WC:Notify(why, 'error') end
            end })
        if ok then added[id] = true end
    end
    local oid = 'esj_pol_out_' .. part
    local ok2 = WC:AddAction({ id = oid, at = { vehiclePart = part }, label = 'Take out', icon = 'hand', first = true, require = req,
        canInteract = function(ctx) return ctx.entity ~= nil and seatedAt(ctx.entity, seat) ~= nil end,
        onSelect = function(ctx)
            local sid = seatedAt(ctx.entity, seat)
            if not sid then return end
            local okc, why = ESJ.call('whip_jobs:pol:out', { target = sid })
            if not okc then WC:Notify(why, 'error') return end
            -- hold them once they are out (WHIP's escort grabs the nearest person: only when that is them)
            CreateThread(function()
                local t = GetGameTimer() + 4000
                while GetGameTimer() < t do
                    Wait(250)
                    local p = GetPlayerFromServerId(sid)
                    local ped = p ~= -1 and GetPlayerPed(p) or 0
                    if ped ~= 0 and not IsPedInAnyVehicle(ped, false) then
                        Wait(400)
                        local me = GetEntityCoords(PlayerPedId())
                        local d = #(GetEntityCoords(ped) - me)
                        local closer = false
                        for _, q in ipairs(GetActivePlayers()) do
                            local qp = GetPlayerPed(q)
                            if q ~= PlayerId() and qp ~= ped and #(GetEntityCoords(qp) - me) < d then closer = true end
                        end
                        if d < 3.0 and not closer then ExecuteCommand('escort_grab') end
                        return
                    end
                end
            end)
        end })
    if ok2 then added[oid] = true end
end

-- ---------------------------------------------------------------- person prompt: tests
local function addPerson()
    local B, T = P.breathalyzer or {}, P.drugTest or {}
    local function run(name, label)
        return function(ctx)
            local sid = ctx.player and ctx.player.serverId
            if not sid then return end
            local ok, r = ESJ.call(name, { target = sid })
            if not ok then WC:Notify(r, 'error') end
        end
    end
    local ok = WC:AddAction({ id = 'esj_pol_person', at = { aimBox = 'ped' }, label = 'Police', icon = 'search', reach = (P.reach or 3.0),
        require = { job = JOBS, onDuty = true },
        canInteract = function(ctx) return ctx.player ~= nil end,
        options = {
            { id = 'breath', label = 'Breathalyzer', require = { item = B.item or 'whip_jobs_breathalyzer' },
                canInteract = function(ctx) return ctx.player and not ctx.player.isDead end, onSelect = run('whip_jobs:pol:breath') },
            { id = 'drug', label = 'Drug swab', require = { item = T.item or 'whip_jobs_drug_test' }, onSelect = run('whip_jobs:pol:drug') },
        } })
    if ok then added.esj_pol_person = true end
end

-- ---------------------------------------------------------------- spike strips
local function stripEntity(s)
    if not NetworkDoesNetworkIdExist(s.netId) then return nil end
    local e = NetworkGetEntityFromNetworkId(s.netId)
    return (e ~= 0 and DoesEntityExist(e)) and e or nil
end

local function stripNear(c, range)
    local best, bd
    for _, s in ipairs(STRIPS) do
        local d = #(vector3(s.x, s.y, s.z) - c)
        if d <= range and (not bd or d < bd) then best, bd = s, d end
    end
    return best
end

local function addSpikes()
    local S = P.spikes or {}
    local ok = WC:AddAction({ id = 'esj_pol_spike', at = { model = S.model or 'p_ld_stinger_s' }, label = 'Pick up spike strip', icon = 'hand',
        require = { job = JOBS, onDuty = true },
        onSelect = function(ctx)
            local s = stripNear(ctx.coords or GetEntityCoords(PlayerPedId()), 6.0)
            if not s then WC:Notify('That strip is not one of ours', 'error') return end
            local okc, why = ESJ.call('whip_jobs:pol:unspike', { id = s.id })
            if not okc then WC:Notify(why, 'error') end
        end })
    if ok then added.esj_pol_spike = true end
end

local function rebuild()
    for id in pairs(added) do WC:RemoveAction(id) end
    added = {}
    JOBS = policeJobs()
    if #JOBS == 0 then return end
    for part, seat in pairs(DOORS) do addDoor(part, seat) end
    addPerson()
    addSpikes()
end

local lastSig = nil
ESJ.onOrgs = function()
    local sig = table.concat((function() local t = {} for _, j in ipairs(policeJobs()) do t[#t + 1] = tostring(j) end return t end)(), ',')
    if sig == lastSig then return end
    lastSig = sig
    rebuild()
end

-- ---------------------------------------------------------------- the cuffed person's own game
RegisterNetEvent('whip_jobs:client:seat', function(netId, seat)
    CreateThread(function()
        local t = GetGameTimer() + 2000
        while GetGameTimer() < t and (WC:IsBeingEscorted() == true) do Wait(50) end
        if not NetworkDoesNetworkIdExist(netId) then return end
        local veh = NetworkGetEntityFromNetworkId(netId)
        if veh == 0 or not IsVehicleSeatFree(veh, seat) then return end
        local ped = PlayerPedId()
        ClearPedTasksImmediately(ped)
        TaskWarpPedIntoVehicle(ped, veh, seat)
    end)
end)

RegisterNetEvent('whip_jobs:client:out', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return end
    TaskLeaveVehicle(ped, veh, 0)
    CreateThread(function()
        Wait(2500)
        if GetVehiclePedIsIn(ped, false) == veh then TaskLeaveVehicle(ped, veh, 16) end
    end)
end)

-- ---------------------------------------------------------------- laying a strip, and driving over one
RegisterNetEvent('whip_jobs:client:laySpike', function()
    CreateThread(function()
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then WC:Notify('Get out first', 'error') return end
        local S = P.spikes or {}
        local model = joaat(S.model or 'p_ld_stinger_s')
        RequestModel(model)
        local t = GetGameTimer() + 3000
        while not HasModelLoaded(model) and GetGameTimer() < t do Wait(20) end
        -- across the road ahead: the strip's long side square to where you face
        local mn, mx = GetModelDimensions(model)
        local alongX = (mx.x - mn.x) >= (mx.y - mn.y)
        local h = GetEntityHeading(ped)
        local fwd = GetEntityForwardVector(ped)
        local c = GetEntityCoords(ped) + fwd * 3.0
        local okg, gz = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.5, false)
        local z = okg and gz or (c.z - 0.95)
        SetModelAsNoLongerNeeded(model)
        local okP = WC:Progress('Laying the spike strip...', 1600, { anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
            disable = { move = true, combat = true } })
        if okP ~= true then return end
        local okc, why = ESJ.call('whip_jobs:pol:spike', { x = c.x, y = c.y, z = z, h = alongX and h or (h + 90.0) })
        if not okc then WC:Notify(why, 'error') else WC:Notify('Spike strip down', 'success') end
    end)
end)

RegisterNetEvent('whip_jobs:client:spikes', function(list) STRIPS = type(list) == 'table' and list or {} end)

local WHEELS = { { 'wheel_lf', 0 }, { 'wheel_rf', 1 }, { 'wheel_lm1', 2 }, { 'wheel_rm1', 3 }, { 'wheel_lr', 4 }, { 'wheel_rr', 5 } }
local function segDist(p, a, b)
    local ab, ap = b - a, p - a
    local l2 = ab.x * ab.x + ab.y * ab.y
    local t = l2 > 0 and math.max(0, math.min(1, (ap.x * ab.x + ap.y * ab.y) / l2)) or 0
    local q = a + ab * t
    return math.sqrt((p.x - q.x) ^ 2 + (p.y - q.y) ^ 2), q
end
--- did the move p1 -> p2 cross the strip a -> b (seen from above)
local function crosses(p1, p2, a, b)
    local function side(o, x, y) return (x.x - o.x) * (y.y - o.y) - (x.y - o.y) * (y.x - o.x) end
    local d1, d2 = side(a, b, p1), side(a, b, p2)
    local d3, d4 = side(p1, p2, a), side(p1, p2, b)
    return ((d1 > 0) ~= (d2 > 0)) and ((d3 > 0) ~= (d4 > 0)) and #(p2 - p1) < 6.0
end
local prevWheel = {}
local ends = {}   -- [netId] = { a, b }
local function stripEnds(s, e)
    local k = ends[s.netId]
    if k and k.e == e then return k.a, k.b end
    local mn, mx = GetModelDimensions(GetEntityModel(e))
    local a, b
    if (mx.x - mn.x) >= (mx.y - mn.y) then
        a, b = GetOffsetFromEntityInWorldCoords(e, mn.x, 0.0, 0.0), GetOffsetFromEntityInWorldCoords(e, mx.x, 0.0, 0.0)
    else
        a, b = GetOffsetFromEntityInWorldCoords(e, 0.0, mn.y, 0.0), GetOffsetFromEntityInWorldCoords(e, 0.0, mx.y, 0.0)
    end
    ends[s.netId] = { e = e, a = a, b = b }
    return a, b
end

CreateThread(function()
    while true do
        local wait = 1000
        if #STRIPS > 0 then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
                local c = GetEntityCoords(veh)
                local nearAny = false
                local before, now = prevWheel, {}
                for _, s in ipairs(STRIPS) do
                    if #(vector3(s.x, s.y, s.z) - c) < 40.0 then
                        nearAny = true
                        local e = stripEntity(s)
                        if e then
                            local a, b = stripEnds(s, e)
                            for _, w in ipairs(WHEELS) do
                                local bone = GetEntityBoneIndexByName(veh, w[1])
                                if bone ~= -1 and not IsVehicleTyreBurst(veh, w[2], false) then
                                    local wp = GetWorldPositionOfEntityBone(veh, bone)
                                    local d, q = segDist(wp, a, b)
                                    local last = before[w[1]]
                                    -- on it now, or crossed it since the last frame (a fast car moves further than the strip is wide)
                                    if math.abs(wp.z - q.z) < 1.2 and (d < 0.45 or (last and crosses(last, wp, a, b))) then
                                        SetVehicleTyreBurst(veh, w[2], true, 1000.0)
                                    end
                                    now[w[1]] = wp
                                end
                            end
                        end
                    end
                end
                if nearAny then wait = 0 prevWheel = now else prevWheel = {} end
            else prevWheel = {} end
        end
        Wait(wait)
    end
end)

CreateThread(function()
    Whip.ready()
    Wait(4000)
    ESJ.call('whip_jobs:pol:spikes', {})
end)

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    for id in pairs(added) do pcall(function() WC:RemoveAction(id) end) end
end)
