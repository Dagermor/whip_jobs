-- es_jobs: police with es_jail's cuffs. Put a cuffed person in a car and take them out (their own game seats them: WHIP
-- escorts, es_jail cuffs, this moves them), the breathalyzer, the drug test and spike strips. Every action is checked
-- here: an officer on duty at a police department, standing by the person or the car, the person cuffed.
ESJ = ESJ or {}
local WC = exports.whip_core
local strips = {}        -- [id] = { id, entity, netId, x, y, z, h, by, at }
local nextStrip = 0
local function P() return Config.Police or {} end

--- the police jobs: es_mdt departments of a police type, and Config.Police.jobs
function ESJ.policeJobs()
    local out, seen = {}, {}
    for _, o in ipairs(ESJ.orgs()) do
        if o.kind == 'dept' and (P().types or {})[o.type] then out[#out + 1] = o.jobId seen[o.jobId] = true end
    end
    for _, j in ipairs(P().jobs or {}) do
        local job = WC:GetJob(j)
        local id = type(job) == 'table' and job.jobId or tonumber(j)
        if id and not seen[id] then out[#out + 1] = id seen[id] = true end
    end
    return out
end

local function officer(source)
    local mine = WC:GetPlayerJobs(source) or {}
    for _, j in ipairs(ESJ.policeJobs()) do
        if mine[j] and mine[j].clockedOn then return j end
    end
    return nil
end

local function cuffed(target)
    local v = Player(target).state.esCuffed
    return type(v) == 'string' and v ~= ''
end

local function pedOf(src)
    local ped = GetPlayerPed(src)
    return (ped and ped ~= 0) and ped or nil
end

local function dist(a, b) return #(GetEntityCoords(a) - GetEntityCoords(b)) end

local function targetOf(source, d, range)
    local t = tonumber(d.target)
    if not t or t == source or not WC:GetCharId(t) then return nil, 'Nobody there' end
    local me, them = pedOf(source), pedOf(t)
    if not me or not them then return nil, 'Nobody there' end
    if GetPlayerRoutingBucket(t) ~= GetPlayerRoutingBucket(source) then return nil, 'Nobody there' end
    if dist(me, them) > (range or P().reach or 3.0) + 1.0 then return nil, 'Get closer' end
    return t, them
end

local function name(src) return WC:GetPlayerFullName(src) or 'them' end

-- ---------------------------------------------------------------- in and out of the car
local function seat(source, d)
    local job = officer(source)
    if not job then return false, 'Only police on duty' end
    local t, them = targetOf(source, d, 4.0)
    if not t then return false, them end
    if not cuffed(t) then return false, 'Cuff them first' end
    if GetVehiclePedIsIn(them, false) ~= 0 then return false, 'They are in a vehicle already' end
    local veh = NetworkGetEntityFromNetworkId(tonumber(d.netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return false, 'No vehicle there' end
    if dist(pedOf(source), veh) > 7.0 or dist(them, veh) > 8.0 then return false, 'Bring them to the car' end
    local s = ESJ.int(d.seat, -1, 6, 1)
    if s == -1 then return false, 'Not the driver\'s seat' end
    if GetPedInVehicleSeat(veh, s) ~= 0 then return false, 'That seat is taken' end
    TriggerClientEvent('es_jobs:client:seat', t, NetworkGetNetworkIdFromEntity(veh), s)
    WC:NotifyPlayer(t, 'You are put in the car', 'info')
    return true
end

local function out(source, d)
    if not officer(source) then return false, 'Only police on duty' end
    local t, them = targetOf(source, d, 6.0)
    if not t then return false, them end
    if not cuffed(t) then return false, 'Only someone cuffed' end
    local veh = GetVehiclePedIsIn(them, false)
    if veh == 0 then return false, 'They are not in a vehicle' end
    TriggerClientEvent('es_jobs:client:out', t)
    return true
end

-- ---------------------------------------------------------------- tests
-- at most 8 s: it runs inside a SecureCallback, which the client gives up on after 10
local function bar(source, label, seconds, them)
    local ok, why = WC:Progress(source, { label = label, duration = math.floor(math.max(1, math.min(8, seconds or 5)) * 1000), icon = 'search',
        anim = { dict = 'amb@code_human_police_investigate@idle_b', clip = 'idle_f', flag = 49 },
        disable = { move = true, combat = true, car = true }, near = { coords = GetEntityCoords(them), range = 4.0 } })
    if ok ~= true then return false, why == 'too far' and 'They moved away' or 'Stopped' end
    return true
end

local function breath(source, d)
    local B = P().breathalyzer or {}
    if not officer(source) then return false, 'Only police on duty' end
    if not WC:HasItem(source, B.item or 'es_jobs_breathalyzer') then return false, 'You need a breathalyzer' end
    local t, them = targetOf(source, d)
    if not t then return false, them end
    if WC:IsPlayerDead(t) then return false, 'They cannot blow into it now' end
    WC:NotifyPlayer(t, 'An officer has you blow into a breathalyzer', 'info')
    local ok, why = bar(source, 'Breathalyzer...', B.seconds, them)
    if not ok then return false, why end
    local v = tonumber(B.stat and WC:GetStat(t, B.stat)) or 0
    local bac = math.max(0, math.min(0.5, v * (B.perPoint or 0.004)))
    local over = bac > (B.limit or 0.08)
    local text = ('%s blew %.3f%s'):format(name(t), bac, over and ' (over the limit)' or '')
    WC:NotifyPlayer(source, text, over and 'error' or 'success', 9000)
    WC:NotifyPlayer(t, ('You blew %.3f'):format(bac), 'info', 7000)
    WC:LogActivity(source, 'es_jobs_breath', { detail = text })
    return { bac = bac, over = over, name = name(t) }
end

local function drug(source, d)
    local T = P().drugTest or {}
    if not officer(source) then return false, 'Only police on duty' end
    local item = T.item or 'es_jobs_drug_test'
    if not WC:HasItem(source, item) then return false, 'You need a drug test kit' end
    local t, them = targetOf(source, d)
    if not t then return false, them end
    WC:NotifyPlayer(t, 'An officer swabs you for drugs', 'info')
    local ok, why = bar(source, 'Drug swab...', T.seconds, them)
    if not ok then return false, why end
    local used = WC:RemoveItem(source, item, 1, nil, { reason = 'drug test' })
    if not used then return false, 'Your test kit is gone' end
    local found, seen = {}, {}
    for eff in pairs(WC:GetEffects(t) or {}) do
        local n = tostring(eff):lower()
        for word, what in pairs(T.effects or {}) do
            if n:find(word, 1, true) and not seen[what] then seen[what] = true found[#found + 1] = what end
        end
    end
    for stat, what in pairs(T.stats or {}) do
        if (tonumber(WC:GetStat(t, stat)) or 0) > 0 and not seen[what] then seen[what] = true found[#found + 1] = what end
    end
    table.sort(found)
    local text = #found > 0 and ('%s: POSITIVE for %s'):format(name(t), table.concat(found, ', ')) or ('%s: negative'):format(name(t))
    WC:NotifyPlayer(source, text, #found > 0 and 'error' or 'success', 9000)
    WC:NotifyPlayer(t, #found > 0 and 'The swab came back positive' or 'The swab came back negative', 'info', 7000)
    WC:LogActivity(source, 'es_jobs_drugtest', { detail = text })
    return { found = found, name = name(t) }
end

-- ---------------------------------------------------------------- spike strips
local function pushStrips(to)
    local list = {}
    for _, s in pairs(strips) do list[#list + 1] = { id = s.id, netId = s.netId, x = s.x, y = s.y, z = s.z, h = s.h } end
    TriggerClientEvent('es_jobs:client:spikes', to or -1, list)
end

local function removeStrip(s)
    if s.entity and DoesEntityExist(s.entity) then DeleteEntity(s.entity) end
    strips[s.id] = nil
end

local function spike(source, d)
    local S = P().spikes or {}
    if not officer(source) then return false, 'Only police on duty' end
    local item = S.item or 'es_jobs_spike_strip'
    if not WC:HasItem(source, item) then return false, 'You have no spike strip' end
    local p = ESJ.point(d)
    if not p then return false, 'Not there' end
    local me = pedOf(source)
    if not me or #(GetEntityCoords(me) - vector3(p.x, p.y, p.z)) > 6.0 then return false, 'Lay it closer' end
    local cid = WC:GetCharId(source)
    local mine = 0
    for _, s in pairs(strips) do if s.by == cid then mine = mine + 1 end end
    if mine >= (S.perOfficer or 2) then return false, ('You have %d down already: pick one up'):format(mine) end
    local okR = WC:RemoveItem(source, item, 1, nil, { reason = 'spike strip laid' })
    if not okR then return false, 'You have no spike strip' end
    local model = joaat(S.model or 'p_ld_stinger_s')
    local obj = CreateObjectNoOffset(model, p.x, p.y, p.z, true, true, false)
    local t = GetGameTimer() + 3000
    while not DoesEntityExist(obj) and GetGameTimer() < t do Wait(50) end
    if not DoesEntityExist(obj) then WC:AddItem(source, item, 1, nil, { reason = 'spike strip not laid' }) return false, 'It could not be laid' end
    SetEntityHeading(obj, p.h)
    FreezeEntityPosition(obj, true)
    t = GetGameTimer() + 3000
    while NetworkGetNetworkIdFromEntity(obj) == 0 and GetGameTimer() < t do Wait(50) end
    nextStrip = nextStrip + 1
    strips[nextStrip] = { id = nextStrip, entity = obj, netId = NetworkGetNetworkIdFromEntity(obj), x = p.x, y = p.y, z = p.z, h = p.h, by = cid, at = os.time() }
    pushStrips()
    return { id = nextStrip }
end

local function unspike(source, d)
    if not officer(source) then return false, 'Only police on duty' end
    local s = strips[tonumber(d.id) or 0]
    if not s then return false, 'It is gone' end
    local me = pedOf(source)
    if not me or #(GetEntityCoords(me) - vector3(s.x, s.y, s.z)) > 5.0 then return false, 'Get closer' end
    removeStrip(s)
    pushStrips()
    local item = (P().spikes or {}).item or 'es_jobs_spike_strip'
    WC:AddItem(source, item, 1, nil, { reason = 'spike strip picked up' })
    return true
end

CreateThread(function()
    while true do
        Wait(30000)
        local mins = (P().spikes or {}).minutes or 10
        if mins > 0 then
            local gone = false
            for _, s in pairs(strips) do
                if os.time() - s.at > mins * 60 or not DoesEntityExist(s.entity) then removeStrip(s) gone = true end
            end
            if gone then pushStrips() end
        end
    end
end)

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    for _, s in pairs(strips) do if s.entity and DoesEntityExist(s.entity) then DeleteEntity(s.entity) end end
end)

-- ---------------------------------------------------------------- items
local ITEMS = {
    { key = function() return (P().breathalyzer or {}).item or 'es_jobs_breathalyzer' end, def = { name = 'Breathalyzer', weight = 0.3, stack = false,
        desc = 'Police: aim at a person, Police > Breathalyzer.', image = 'html/img/items/breathalyzer.webp' } },
    { key = function() return (P().drugTest or {}).item or 'es_jobs_drug_test' end, def = { name = 'Drug test kit', weight = 0.1, stack = true, maxStack = 20,
        desc = 'Police: aim at a person, Police > Drug swab. One per test.', image = 'html/img/items/drug_test_kit.webp' } },
    { key = function() return (P().spikes or {}).item or 'es_jobs_spike_strip' end, def = { name = 'Spike strip', weight = 4.0, stack = true, maxStack = 3, usable = true,
        desc = 'Police: use it to lay it across the road in front of you. Pick it up again at the strip.', image = 'html/img/items/spike_strip.webp' } },
}

function ESJ.registerPolice(cb)
    for _, it in ipairs(ITEMS) do
        local key = it.key()
        local def = {}
        for k, v in pairs(it.def) do def[k] = v end
        local ok, why = Whip.core:RegisterItem(key, def)
        if not ok then print(('^3[es_jobs] item %s: %s (another script\'s item of that name is used)^7'):format(key, tostring(why))) end
    end
    Whip.core:RegisterUseHandler((P().spikes or {}).item or 'es_jobs_spike_strip', function(source)
        if not officer(source) then return false, 'Only police on duty lay spike strips' end
        TriggerClientEvent('es_jobs:client:laySpike', source)
        return false   -- kept until it is really laid
    end)
    cb('es_jobs:pol:seat', 900, seat)
    cb('es_jobs:pol:out', 900, out)
    cb('es_jobs:pol:breath', 3000, breath)
    cb('es_jobs:pol:drug', 3000, drug)
    cb('es_jobs:pol:spike', 1500, spike)
    cb('es_jobs:pol:unspike', 1000, unspike)
    cb('es_jobs:pol:spikes', 2000, function(source) pushStrips(source) return true end)
end

AddEventHandler('whip_core:player:loaded', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' or not e.source then return end
    if next(strips) then pushStrips(e.source) end
end)
