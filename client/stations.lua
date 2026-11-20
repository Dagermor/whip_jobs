-- whip_jobs: stations near the player. Peds are made on this game only (not networked), only while the player is within
-- Config.Stations.pedDistance, frozen, invincible and deaf to the world. Each spot is a WHIP prompt shown only to the
-- members of the station's departments and businesses (WHIP checks the job; the server checks again on use).
-- Blips: per station, for everyone, its members, or nobody.
ESJ = ESJ or {}
local STATIONS, ORGS = {}, {}
local peds = {}          -- ['station:spot'] = ped handle
local actions = {}       -- action id -> true
local blips = {}         -- stationId -> handle
local WC = Whip.core   -- guarded: false, why while whip_core is not up

local ICON = { duty = 'timer', armory = 'store', locker = 'bag', garage = 'garage', helipad = 'car', boatdock = 'car',
    impound = 'garage', hospital = 'info', court_clerk = 'info', courtroom = 'info', chambers = 'info', da_office = 'info', pd_office = 'info' }
local VERB = { duty = 'Clock on / off', armory = 'Armory', locker = 'Locker', garage = 'Vehicles', helipad = 'Helicopters',
    boatdock = 'Boats', impound = 'Impound', hospital = 'Check in', court_clerk = 'Court clerk', courtroom = 'Courtroom',
    chambers = "Judge's chambers", da_office = "District Attorney", pd_office = 'Public defender' }

local function S() return Config.Stations or {} end
local function orgNames(st)
    local n = {}
    for _, j in ipairs(st.jobs or {}) do local o = ORGS[tostring(j)] if o then n[#n + 1] = o.short or o.name end end
    return table.concat(n, ' / ')
end

-- ---------------------------------------------------------------- peds
local function loadModel(m)
    local h = type(m) == 'number' and m or joaat(m)
    if not IsModelInCdimage(h) or not IsModelAPed(h) then return nil end
    RequestModel(h)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(h) do
        if GetGameTimer() > t then return nil end
        Wait(20)
    end
    return h
end

local function makePed(st, s)
    local h = loadModel(s.ped)
    if not h then return nil end
    local ped = CreatePed(4, h, s.x, s.y, s.z, s.h or 0.0, false, false)   -- spots are stored at the feet
    SetModelAsNoLongerNeeded(h)
    if not ped or ped == 0 then return nil end
    SetEntityAsMissionEntity(ped, true, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedDiesWhenInjured(ped, false)
    SetEntityCanBeDamaged(ped, false)
    SetPedCanBeTargetted(ped, false)
    if s.type == 'duty' or s.type == 'hospital' or s.type == 'impound' then
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    elseif s.type == 'court_clerk' or s.type == 'da_office' or s.type == 'chambers' then
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    elseif s.type == 'armory' or s.type == 'courtroom' or s.type == 'pd_office' then
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_GUARD_STAND', 0, true)
    else
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
    end
    return ped
end

local function dropPed(k)
    local p = peds[k]
    if p and DoesEntityExist(p) then DeleteEntity(p) end
    peds[k] = nil
end

local function clearPeds() for k in pairs(peds) do dropPed(k) end end

CreateThread(function()
    while true do
        local me = GetEntityCoords(PlayerPedId())
        local near, far = (S().pedDistance or 45.0), (S().pedDistance or 45.0) + 10.0
        local want = {}
        for _, st in ipairs(STATIONS) do
            for _, s in ipairs(st.spots) do
                if s.ped then
                    local k = st.id .. ':' .. s.id
                    local d = #(me - vector3(s.x, s.y, s.z))
                    if peds[k] then
                        if d > far or not DoesEntityExist(peds[k]) then dropPed(k) else want[k] = true end
                    elseif d <= near and not (ESJ.editing and ESJ.editing(st.id, s.id)) then
                        local p = makePed(st, s)
                        if p then peds[k] = p want[k] = true end
                    end
                end
            end
        end
        for k in pairs(peds) do if not want[k] then dropPed(k) end end
        Wait(next(peds) and 800 or 1500)
    end
end)

-- ---------------------------------------------------------------- prompts
local function removeActions()
    for id in pairs(actions) do WC:RemoveAction(id) end
    actions = {}
end

local function openSpot(st, s)
    local ok, r = ESJ.call('whip_jobs:spot:open', { station = st.id, spot = s.id })
    if not ok then WC:Notify(r, 'error') return end
    if s.type == 'locker' then return ESJ.openLocker(st.id, s.id) end
    ESJ.openUI('spot', r)
end

-- ---------------------------------------------------------------- 0.4.0: the DOJ's spots open es_mdt's court screens
local function mdtUp() return GetResourceState('es_mdt') == 'started' end
local function portal(o)
    if not mdtUp() then return WC:Notify('The court is closed (es_mdt is not running)', 'error') end
    local ok, why = pcall(function() exports.es_mdt:OpenPortal(o) end)
    if not ok then WC:Notify('The court is closed right now', 'error') end
end
local function tablet()
    if not mdtUp() then return WC:Notify('The DOJ tablet is not available (es_mdt is not running)', 'error') end
    pcall(function() exports.es_mdt:OpenTablet() end)
end
--- the prompt's options for a DOJ spot (nil for every other type)
local function dojOptions(st, s)
    local staff = { job = st.jobs }
    local t = s.type == 'court' and 'court_clerk' or s.type
    if t == 'court_clerk' then
        return {
            { id = 'portal', label = 'Court services (cases, payments, petitions)', onSelect = function() portal({ desk = true }) end },
            { id = 'pay', label = 'Pay a fine or fee', onSelect = function() portal({ desk = true, view = 'pay' }) end },
        }
    elseif t == 'courtroom' then
        return {
            { id = 'cases', label = 'My cases and hearings', onSelect = function() portal({ view = 'mycases' }) end },
            { id = 'tablet', label = 'DOJ tablet (docket)', require = staff, onSelect = tablet },
        }
    elseif t == 'pd_office' then
        return {
            { id = 'lawyers', label = 'Hire a lawyer or ask for a public defender', onSelect = function() portal({ view = 'lawyers' }) end },
            { id = 'tablet', label = 'DOJ tablet', require = staff, onSelect = tablet },
        }
    elseif t == 'chambers' or t == 'da_office' then
        return { { id = 'tablet', label = 'DOJ tablet', onSelect = tablet } }
    end
end

local function addActions()
    removeActions()
    local R = S().reach or 2.0
    for _, st in ipairs(STATIONS) do
        local staffed = #(st.jobs or {}) > 0
        do
            for _, s in ipairs(st.spots) do
                local T = ESJ.TYPE[s.type]
                if T and (T.phase or 1) <= ESJ.PHASE and (staffed or T.public) then
                    local id = ('st%d_%s'):format(st.id, s.id)
                    local z = s.z + (s.ped and 1.15 or 0.9)
                    local label = (s.label ~= '' and s.label) or VERB[s.type]
                    local def = {
                        id = id, group = 'whip_jobs', at = { coords = vector3(s.x, s.y, z) },
                        label = label, icon = ICON[s.type] or 'info', description = T.public and st.name or orgNames(st),
                        require = T.public and { vehicle = 'out' } or { job = st.jobs, vehicle = 'out' },
                        reach = T.spawns and (R + 1.0) or R, seeFrom = S().seeFrom or 8.0, focusMode = 'near',
                        onSelect = function() openSpot(st, s) end,
                    }
                    if s.type == 'armory' then def.require.onDuty = true end
                    if T.doj then def.options = dojOptions(st, s) def.onSelect = nil end
                    local ok = WC:AddAction(def)
                    if ok then actions[id] = true end
                    -- a fleet garage: drive back to it and put the vehicle away from the seat
                    if T.fleet then
                        local rid = id .. '_ret'
                        local ok2 = WC:AddAction({
                            id = rid, group = 'whip_jobs', at = { coords = vector3(s.x, s.y, s.z) }, label = 'Put the vehicle back', icon = ICON[s.type],
                            require = { job = st.jobs, vehicle = 'in' }, reach = 12.0, seeFrom = 25.0, focusMode = 'near',
                            canInteract = function() return ESJ.myFleet ~= nil end,
                            onSelect = function(ctx)
                                local okr, why = ESJ.call('whip_jobs:fleet:return', { station = st.id, spot = s.id })
                                if okr then ESJ.myFleet = nil WC:Notify('Vehicle put back', 'success')
                                elseif ctx.refuse then ctx.refuse(why) else WC:Notify(why, 'error') end
                            end,
                        })
                        if ok2 then actions[rid] = true end
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- blips
local function clearBlips()
    for _, b in pairs(blips) do if DoesBlipExist(b) then pcall(function() WC:SetBlipLabel(b, nil) end) RemoveBlip(b) end end
    blips = {}
end

local function drawBlips()
    clearBlips()
    if S().blips == false then return end
    local mine = WC:GetPlayerJobs() or {}
    for _, st in ipairs(STATIONS) do
        local b = st.blip or {}
        local show = b.show or 'everyone'
        local member = false
        for _, j in ipairs(st.jobs or {}) do if mine[j] then member = true end end
        local first = st.spots[1]
        if first and (show == 'everyone' or (show == 'members' and member)) then
            local h = AddBlipForCoord(first.x, first.y, first.z)
            SetBlipSprite(h, b.sprite or S().blipSprite or 60)
            SetBlipColour(h, b.color or S().blipColor or 29)
            SetBlipScale(h, b.scale or 0.8)
            SetBlipAsShortRange(h, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(st.name)
            EndTextCommandSetBlipName(h)
            pcall(function() WC:SetBlipLabel(h, st.name) end)
            blips[st.id] = h
        end
    end
end

-- ---------------------------------------------------------------- data
local function apply(list, orgs)
    STATIONS, ORGS = type(list) == 'table' and list or {}, type(orgs) == 'table' and orgs or {}
    ESJ.STATIONS, ESJ.ORGS = STATIONS, ORGS
    if ESJ.devRefresh then ESJ.devRefresh() end
    -- a spot that moved or changed ped: its ped is made again
    local keep = {}
    for _, st in ipairs(STATIONS) do for _, s in ipairs(st.spots) do keep[st.id .. ':' .. s.id] = s end end
    for k, p in pairs(peds) do
        local s = keep[k]
        if not s or not s.ped or not DoesEntityExist(p) or #(GetEntityCoords(p).xy - vector2(s.x, s.y)) > 0.4
            or GetEntityModel(p) ~= joaat(s.ped) then dropPed(k) end
    end
    addActions()
    drawBlips()
    if ESJ.onOrgs then ESJ.onOrgs() end
end

RegisterNetEvent('whip_jobs:client:stations', function(list, orgs) apply(list, orgs) end)
AddEventHandler('whip_core:job:listChanged', function() drawBlips() end)

RegisterNetEvent('whip_jobs:client:fleetOut', function(o)
    if type(o) ~= 'table' then return end
    ESJ.myFleet = o
    WC:Notify(('Your vehicle (%s) is out front'):format(o.plate or ''), 'success')
    if not o.livery or o.livery < 0 then return end
    CreateThread(function()
        local t = GetGameTimer() + 8000
        while GetGameTimer() < t do
            for _, v in ipairs(GetGamePool('CVehicle')) do
                if GetVehicleNumberPlateText(v):gsub('%s', '') == o.plate and NetworkHasControlOfEntity(v) then
                    SetVehicleLivery(v, o.livery)
                    return
                end
            end
            Wait(300)
        end
    end)
end)

-- the first list: ask once the character is in (the server also sends it on load)
CreateThread(function()
    Whip.ready()
    Wait(2500)
    local ok, r = ESJ.call('whip_jobs:st:public', {})
    if ok and type(r) == 'table' then apply(r.stations, r.orgs) end
end)

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    clearPeds()
    clearBlips()
end)

--- for the editor: hide a spot's ped while it is being moved (the ghost stands there instead)
function ESJ.refreshPeds(stationId, spotId) dropPed(stationId .. ':' .. spotId) end
