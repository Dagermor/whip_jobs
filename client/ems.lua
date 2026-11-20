-- es_jobs 0.3.0: EMS on this game. Wounded: on the ground, crawl (W / left stick, turn A D / left stick), Call EMS
-- (G / D-pad left), a yellow chip with the timer; down: a red chip over WHIP's death screen. Over hurt people nearby,
-- a small WOUNDED / DOWN tag. "First aid" on a wounded person (with a kit), "EMS" on anyone for EMS on duty.
ESJ = ESJ or {}
local WC = Whip.core
local function E() return Config.EMS or {} end
local H = { state = 'none' }          -- my own state: state, endsAt, autoAt, called, units, health, crawl
local added = {}
local CALL_KEY = 47                   -- G on a keyboard, D-pad left on a controller

-- ---------------------------------------------------------------- the chip (html/ems.js, never takes focus)
local function chip()
    if H.state == 'none' then SendNUIMessage({ action = 'hurt', state = 'none' }) return end
    local t = GetGameTimer()
    SendNUIMessage({ action = 'hurt', state = H.state, left = H.endsAt and math.max(0, math.ceil((H.endsAt - t) / 1000)) or nil,
        autoIn = (H.autoAt and not H.called) and math.max(0, math.ceil((H.autoAt - t) / 1000)) or nil, called = H.called == true,
        units = H.units or 0, pad = not IsUsingKeyboard(0), headshot = H.headshot == true })
end

-- ---------------------------------------------------------------- wounded: on the ground
local IDLE = { 'combat@damage@writhe', 'writhe_loop' }
local CRAWL = { 'move_injured_ground', 'front_loop' }
local function loadDict(d)
    if HasAnimDictLoaded(d) then return true end
    RequestAnimDict(d)
    local t = GetGameTimer() + 3000
    while not HasAnimDictLoaded(d) and GetGameTimer() < t do Wait(10) end
    return HasAnimDictLoaded(d)
end

local function escorted()
    local ok, v = pcall(function() return WC:IsBeingEscorted() end)
    return ok and v == true
end

local function woundedLoop()
    local gen = H.gen
    CreateThread(function()
        -- WHIP stands us up from the death first; then we go back down
        local t = GetGameTimer() + 4000
        while GetGameTimer() < t and IsEntityDead(PlayerPedId()) do Wait(100) end
        Wait(1200)
        if H.gen ~= gen then return end
        loadDict(IDLE[1]) loadDict(CRAWL[1])
        local ped = PlayerPedId()
        SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), H.health or 120))
        local playing, manual, lastPos, lastCheck = nil, false, nil, 0
        local lastChip, lastCall = 0, 0
        while H.gen == gen and H.state == 'wounded' do
            ped = PlayerPedId()
            if IsEntityDead(ped) then break end          -- WHIP has it: the server makes it a down
            DisableAllControlActions(0)
            for _, c in ipairs({ 0, 1, 2, 199, 200, 245, 249, CALL_KEY }) do EnableControlAction(0, c, true) end
            if IsPedInAnyVehicle(ped, false) then EnableControlAction(0, 75, true) end   -- out of the car, at least
            if GetEntityHealth(ped) > (H.health or 120) then SetEntityHealth(ped, H.health or 120) end
            local now = GetGameTimer()
            if not escorted() and not IsPedInAnyVehicle(ped, false) then
                local fwd = -GetDisabledControlNormal(0, 31)          -- W / left stick up
                local turn = GetDisabledControlNormal(0, 30)          -- A D / left stick
                if math.abs(turn) > 0.15 then SetEntityHeading(ped, GetEntityHeading(ped) - turn * 1.6) end
                if fwd > 0.25 then
                    if playing ~= 'crawl' then
                        TaskPlayAnim(ped, CRAWL[1], CRAWL[2], 4.0, -4.0, -1, 1, 0.0, false, false, false)
                        playing, lastPos, lastCheck = 'crawl', GetEntityCoords(ped), now
                    end
                    -- the crawl moves the ped on its own; if it does not here, we move it
                    if not manual and now - lastCheck > 800 then
                        if #(GetEntityCoords(ped) - lastPos) < 0.1 then manual = true end
                        lastCheck, lastPos = now, GetEntityCoords(ped)
                    end
                    if manual then
                        local p = GetEntityCoords(ped) + GetEntityForwardVector(ped) * (0.012 * (H.crawl or 1.0))
                        local okZ, gz = GetGroundZFor_3dCoord(p.x, p.y, p.z + 0.6, false)
                        SetEntityCoordsNoOffset(ped, p.x, p.y, okZ and gz or p.z, false, false, false)
                    end
                elseif playing ~= 'idle' or not IsEntityPlayingAnim(ped, IDLE[1], IDLE[2], 3) then
                    TaskPlayAnim(ped, IDLE[1], IDLE[2], 4.0, -4.0, -1, 1, 0.0, false, false, false)
                    playing = 'idle'
                end
            else playing = nil end
            if IsDisabledControlJustPressed(0, CALL_KEY) or IsControlJustPressed(0, CALL_KEY) then
                if not H.called and now - lastCall > 3000 then
                    lastCall = now
                    CreateThread(function()
                        local ok, r = ESJ.call('es_jobs:ems:call', {})
                        if ok then H.called = true WC:Notify('EMS has been called', 'success') chip()
                        else WC:Notify(r, 'error') end
                    end)
                end
            end
            if now - lastChip > 1000 then lastChip = now chip() end
            Wait(0)
        end
        if H.gen == gen and H.state ~= 'wounded' then ClearPedTasks(PlayerPedId()) end
    end)
end

-- ---------------------------------------------------------------- the server says
RegisterNetEvent('es_jobs:client:hurt', function(d)
    d = type(d) == 'table' and d or {}
    local t = GetGameTimer()
    if d.state == 'wounded' then
        if H.state ~= 'wounded' then
            H = { state = 'wounded', gen = (H.gen or 0) + 1, endsAt = d.left and (t + d.left * 1000) or nil,
                autoAt = d.auto and (t + d.auto * 1000) or nil, called = false, units = 0, health = d.health or 120,
                crawl = d.crawl or 1.0, headshot = d.headshot }
            woundedLoop()
            WC:Notify(d.headshot and 'You are badly wounded (head). Call EMS before you bleed out.' or 'You are wounded. Call EMS, or get first aid.', 'error', 8000)
        else
            if d.called ~= nil then H.called = d.called end
            if d.units then H.units = d.units end
            if d.auto and d.called then WC:Notify('EMS has been called for you', 'info') end
        end
    elseif d.state == 'down' then
        if H.state ~= 'down' then
            H = { state = 'down', gen = (H.gen or 0) + 1, called = d.called == true, units = 0 }
        else
            if d.called ~= nil then H.called = d.called end
            if d.units then H.units = d.units end
        end
    else
        local was = H.state
        H = { state = 'none', gen = (H.gen or 0) + 1 }
        if was == 'wounded' then
            local ped = PlayerPedId()
            ClearPedTasks(ped)
            if d.health then SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), d.health)) end
        elseif d.health then
            local ped = PlayerPedId()
            if not IsEntityDead(ped) then SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), d.health)) end
        end
    end
    chip()
end)

RegisterNetEvent('es_jobs:client:bleedOut', function()
    if H.state ~= 'wounded' then return end
    WC:Notify('You bled out', 'error')
    SetEntityHealth(PlayerPedId(), 0)
end)

-- the chip keeps counting while down (WHIP's own screen does the respawn)
CreateThread(function()
    while true do
        Wait(1000)
        if H.state == 'down' then chip() end
    end
end)

-- my own death: what killed me, as my game saw it (a headshot shortens the wounded timer)
local H_GROUP_MELEE, H_GROUP_THROWN, H_GROUP_UNARMED, H_WEAPON_DROWNING, H_WEAPON_DROWNING_IN_VEHICLE, H_WEAPON_EXPLOSION, H_WEAPON_FALL, H_WEAPON_FIRE, H_WEAPON_RAMMED_BY_CAR, H_WEAPON_RUN_OVER_BY_CAR =
    GetHashKey('GROUP_MELEE'), GetHashKey('GROUP_THROWN'), GetHashKey('GROUP_UNARMED'), GetHashKey('WEAPON_DROWNING'), GetHashKey('WEAPON_DROWNING_IN_VEHICLE'), GetHashKey('WEAPON_EXPLOSION'), GetHashKey('WEAPON_FALL'), GetHashKey('WEAPON_FIRE'), GetHashKey('WEAPON_RAMMED_BY_CAR'), GetHashKey('WEAPON_RUN_OVER_BY_CAR')
local function streetHere()
    local c = GetEntityCoords(PlayerPedId())
    local s1, s2 = GetStreetNameAtCoord(c.x, c.y, c.z)
    local a, b = GetStreetNameFromHashKey(s1), s2 ~= 0 and GetStreetNameFromHashKey(s2) or nil
    return (b and b ~= '') and (a .. ' / ' .. b) or a
end
AddEventHandler('whip_core:player:died', function(e)
    if type(e) == 'table' and (e.reconnected or e.respawnRefused) then return end
    if E().enabled == false then return end
    local ped = PlayerPedId()
    local okB, bone = GetPedLastDamageBone(ped)
    local headshot = okB and (bone == 31086 or bone == 39317 or bone == 12844 or bone == 65068) or false
    local w = GetPedCauseOfDeath(ped)
    local cause = nil
    if w == H_WEAPON_RUN_OVER_BY_CAR or w == H_WEAPON_RAMMED_BY_CAR then cause = 'hit by a vehicle'
    elseif w == H_WEAPON_FALL then cause = 'fall injuries'
    elseif w == H_WEAPON_DROWNING or w == H_WEAPON_DROWNING_IN_VEHICLE then cause = 'drowning'
    elseif w == H_WEAPON_FIRE then cause = 'burns'
    elseif w == H_WEAPON_EXPLOSION then cause = 'explosion'
    elseif w and w ~= 0 and IsWeaponValid(w) then
        local g = GetWeapontypeGroup(w)
        if g == H_GROUP_MELEE or g == H_GROUP_UNARMED then cause = 'blunt trauma'
        elseif g == H_GROUP_THROWN then cause = 'explosion / burns'
        elseif g ~= 0 then cause = 'gunshot wound' end
    end
    if IsPedInAnyVehicle(ped, true) and not cause then cause = 'vehicle crash' end
    TriggerServerEvent('es_jobs:ems:info', { headshot = headshot, cause = cause, street = streetHere() })
end)

-- after a resource restart (or a reconnect), pick up where the server is
CreateThread(function()
    Whip.ready()
    Wait(3000)
    local ok, r = ESJ.call('es_jobs:ems:me', {})
    if ok and type(r) == 'table' and r.state ~= 'none' then
        TriggerEvent('es_jobs:client:hurt', { state = r.state, left = r.left, auto = r.auto, health = r.health })
        TriggerEvent('es_jobs:client:hurt', { state = r.state, called = r.called, units = r.units })
    end
end)

-- ---------------------------------------------------------------- tags over hurt people nearby
local near = {}
CreateThread(function()
    while true do
        Wait(600)
        local list = {}
        local me = GetEntityCoords(PlayerPedId())
        for _, p in ipairs(GetActivePlayers()) do
            if p ~= PlayerId() then
                local ped = GetPlayerPed(p)
                local st = Player(GetPlayerServerId(p)).state.esHurt
                if (st == 'wounded' or st == 'down') and ped ~= 0 and #(GetEntityCoords(ped) - me) < 20.0 then list[#list + 1] = { ped = ped, st = st } end
            end
        end
        near = list
    end
end)
local function tag3d(x, y, z, text, r, g, b)
    local on, sx, sy = World3dToScreen2d(x, y, z)
    if not on then return end
    SetTextScale(0.0, 0.32) SetTextFont(4) SetTextCentre(true) SetTextOutline()
    SetTextColour(r, g, b, 235)
    BeginTextCommandDisplayText('STRING') AddTextComponentSubstringPlayerName(text) EndTextCommandDisplayText(sx, sy)
end
CreateThread(function()
    while true do
        if #near == 0 then Wait(500)
        else
            for _, n in ipairs(near) do
                if DoesEntityExist(n.ped) then
                    local c = GetEntityCoords(n.ped)
                    if n.st == 'down' then tag3d(c.x, c.y, c.z + 0.45, '✚ DOWN', 239, 68, 68)
                    else tag3d(c.x, c.y, c.z + 0.45, '✚ WOUNDED', 250, 204, 21) end
                end
            end
            Wait(0)
        end
    end
end)

-- ---------------------------------------------------------------- prompts: first aid (anyone with a kit), EMS
local function hurtOf(ctx)
    local sid = ctx.player and ctx.player.serverId
    return sid and Player(sid).state.esHurt or nil, sid
end
local function run(name)
    return function(ctx)
        local sid = ctx.player and ctx.player.serverId
        if not sid then return end
        local ok, r = ESJ.call(name, { target = sid })
        if not ok then WC:Notify(r, 'error') end
        return ok, r
    end
end

local function emsJobs()
    local out = {}
    for jid, o in pairs(ESJ.ORGS or {}) do
        if o.kind == 'dept' and (E().types or {})[o.type] then out[#out + 1] = tonumber(jid) end
    end
    for _, j in ipairs(E().jobs or {}) do out[#out + 1] = j end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

local function rebuild()
    for id in pairs(added) do WC:RemoveAction(id) end
    added = {}
    if E().enabled == false then return end
    local F = E().firstAid or {}
    local ok = WC:AddAction({ id = 'esj_ems_aid', at = { aimBox = 'ped' }, label = 'First aid', icon = 'heart', reach = 3.0,
        require = { item = F.item or 'es_jobs_first_aid' },
        canInteract = function(ctx) return hurtOf(ctx) == 'wounded' and not (ctx.player and ctx.player.isDead) end,
        onSelect = run('es_jobs:ems:aid') })
    if ok then added.esj_ems_aid = true end
    local jobs = emsJobs()
    if #jobs == 0 then return end
    local bag = (E().medbag or {}).item or 'es_jobs_medbag'
    local ok2 = WC:AddAction({ id = 'esj_ems_person', at = { aimBox = 'ped' }, label = 'EMS', icon = 'heart', reach = 3.0,
        require = { job = jobs, onDuty = true },
        canInteract = function(ctx) return ctx.player ~= nil end,
        options = {
            { id = 'examine', label = 'Examine', onSelect = function(ctx)
                local sid = ctx.player and ctx.player.serverId
                if not sid then return end
                local okc, r = ESJ.call('es_jobs:ems:examine', { target = sid })
                if not okc then WC:Notify(r, 'error') return end
                local STATE = { down = 'Not breathing (down)', wounded = 'Wounded', ok = 'Conscious' }
                local lines = { ('%s · %s'):format(r.name or '?', STATE[r.state] or r.state) }
                if r.state ~= 'down' then lines[#lines + 1] = ('Health %d%%'):format(math.floor(r.health or 0)) end
                if r.headshot then lines[#lines + 1] = 'Head wound' end
                if r.cause and r.cause ~= '' then lines[#lines + 1] = r.cause end
                if r.minutes then lines[#lines + 1] = ('Hurt %d min ago'):format(r.minutes) end
                if r.left then lines[#lines + 1] = ('Bleeding out in about %d s'):format(r.left) end
                WC:Notify(table.concat(lines, ' · '), r.state == 'ok' and 'info' or 'error', 10000)
            end },
            { id = 'treat', label = 'Treat', require = { item = bag },
                canInteract = function(ctx) return ctx.player and not ctx.player.isDead end, onSelect = run('es_jobs:ems:treat') },
            { id = 'revive', label = 'Revive', require = { item = bag },
                canInteract = function(ctx) return ctx.player and ctx.player.isDead end, onSelect = run('es_jobs:ems:revive') },
        } })
    if ok2 then added.esj_ems_person = true end
end

local lastSig = nil
local prevOnOrgs = ESJ.onOrgs
ESJ.onOrgs = function()
    if prevOnOrgs then prevOnOrgs() end
    local sig = table.concat((function() local t = {} for _, j in ipairs(emsJobs()) do t[#t + 1] = tostring(j) end return t end)(), ',')
        .. (E().enabled == false and ':off' or '')
    if sig == lastSig then return end
    lastSig = sig
    rebuild()
end

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    for id in pairs(added) do pcall(function() WC:RemoveAction(id) end) end
end)
