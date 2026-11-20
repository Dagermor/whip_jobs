-- whip_jobs: the locker room on this game. A live preview (the uniform on the player's own ped, a camera in front, turn
-- and zoom with the pad or the buttons), WHIP's character editor for leaders who make uniforms and for officers who
-- adjust theirs, and putting parts on when the server says so (wear, own clothes, a load after a crash).
ESJ = ESJ or {}
local WC = Whip.core
local before = nil       -- the ped's clothes before a preview: { c = {}, p = {} }
local cam = { on = false, face = false, h = nil }   -- h: the heading the camera was set up for
local spot = nil         -- { station, spot } of the open locker room
local COMPS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
local PROPS = { 0, 1, 2, 6, 7 }
local FOLDER = { c1 = '01_masks', c3 = '03_arms_gloves', c4 = '04_pants', c5 = '05_bags', c6 = '06_shoes', c7 = '07_accessories',
    c8 = '08_undershirts', c9 = '09_vests_armour', c10 = '10_decals', c11 = '11_tops', p0 = 'p0_hats', p1 = 'p1_glasses',
    p2 = 'p2_ears', p6 = 'p6_watches', p7 = 'p7_bracelets' }

-- ---------------------------------------------------------------- parts on the ped
local function read(ped)
    local o = { c = {}, p = {} }
    for _, i in ipairs(COMPS) do o.c[tostring(i)] = { GetPedDrawableVariation(ped, i), GetPedTextureVariation(ped, i) } end
    for _, i in ipairs(PROPS) do o.p[tostring(i)] = { GetPedPropIndex(ped, i), math.max(0, GetPedPropTextureIndex(ped, i)) } end
    return o
end

--- put parts on a ped: only styles and colours its model has (an add-on pack that is not streamed is skipped)
function ESJ.applyParts(ped, parts)
    if type(parts) ~= 'table' or not DoesEntityExist(ped) then return end
    for k, v in pairs(parts.c or {}) do
        local i, d, t = tonumber(k), tonumber(v[1]), tonumber(v[2]) or 0
        if i and d and d < GetNumberOfPedDrawableVariations(ped, i) and t < math.max(1, GetNumberOfPedTextureVariations(ped, i, d)) then
            SetPedComponentVariation(ped, i, d, t, 0)
        end
    end
    for k, v in pairs(parts.p or {}) do
        local i, d, t = tonumber(k), tonumber(v[1]), tonumber(v[2]) or 0
        if i and d then
            if d < 0 then ClearPedProp(ped, i)
            elseif d < GetNumberOfPedPropDrawableVariations(ped, i) then SetPedPropIndex(ped, i, d, t, true) end
        end
    end
end

RegisterNetEvent('whip_jobs:client:dress', function(parts)
    before = nil   -- what the server put on is what they wear now: no preview to undo
    ESJ.applyParts(PlayerPedId(), parts)
end)

local function undoPreview()
    if before then ESJ.applyParts(PlayerPedId(), before) before = nil end
end

-- ---------------------------------------------------------------- pictures (whip_media_clothing_male / _female)
local function picture(ped, gender, key, d, t)
    if not gender or d < 0 or GetPedCollectionNameFromDrawable == nil then return nil end
    local kind, slot = key:sub(1, 1), tonumber(key:sub(2))
    local base = GetPedCollectionName(ped, 0)
    local name, idx
    if kind == 'c' then
        if d >= GetNumberOfPedDrawableVariations(ped, slot) then return nil end
        name, idx = GetPedCollectionNameFromDrawable(ped, slot, d), GetPedCollectionLocalIndexFromDrawable(ped, slot, d)
    else
        if d >= GetNumberOfPedPropDrawableVariations(ped, slot) then return nil end
        name, idx = GetPedCollectionNameFromProp(ped, slot, d), GetPedCollectionLocalIndexFromProp(ped, slot, d)
    end
    if type(name) ~= 'string' or type(idx) ~= 'number' or idx < 0 then return nil end
    if name == '' or name == base then name = 'base' end
    local tag = kind == 'c' and tostring(slot) or ('prop' .. slot)
    return ('https://cfx-nui-whip_media_clothing_%s/img/clothing/%s/%s/%s_%s_%s_%03d_%02d.webp'):format(gender, gender, FOLDER[key], gender, tag, name, idx, t)
end

--- the list from the server with each uniform's pictures (the player's own body only: the game knows its packs)
local function withPictures(r)
    local ped = PlayerPedId()
    local m = GetEntityModel(ped)
    local gender = (m == joaat('mp_m_freemode_01') and 'male') or (m == joaat('mp_f_freemode_01') and 'female') or nil
    for _, o in ipairs(r.orgs or {}) do
        for _, u in ipairs(o.uniforms or {}) do
            u.pics = {}
            if u.body == gender then
                for k, v in pairs(u.parts.c or {}) do u.pics['c' .. k] = picture(ped, gender, 'c' .. k, v[1], v[2]) end
                for k, v in pairs(u.parts.p or {}) do u.pics['p' .. k] = picture(ped, gender, 'p' .. k, v[1], v[2]) end
            end
        end
    end
    return r
end

-- ---------------------------------------------------------------- camera
local function camShot()
    local ped = PlayerPedId()
    if not cam.h then cam.h = GetEntityHeading(ped) end
    local c, h = GetEntityCoords(ped), math.rad(cam.h)
    local fwd = vector3(-math.sin(h), math.cos(h), 0.0)
    local dist, z = cam.face and 0.9 or 2.6, cam.face and 0.65 or 0.15
    local pos = c + fwd * dist + vector3(0.0, 0.0, z)
    local look = c + vector3(0.0, 0.0, cam.face and 0.62 or 0.05)
    local d = look - pos
    local pitch = math.deg(math.atan(d.z, math.sqrt(d.x * d.x + d.y * d.y)))
    local yaw = math.deg(math.atan(d.y, d.x)) - 90.0
    return pos, vector3(pitch, 0.0, yaw)
end
local function camOn()
    local pos, rot = camShot()
    local ok = pcall(function() WC:PlayCamera({ pos = pos, rot = rot, fov = cam.face and 35.0 or 42.0, async = true, exitKey = false, transitionIn = cam.on and 0 or 400 }) end)
    cam.on = ok
end
local function camOff()
    if cam.on then pcall(function() WC:StopCamera() end) end
    cam.on, cam.face, cam.h = false, false, nil
end

-- ---------------------------------------------------------------- the screen
function ESJ.openLocker(st, s)
    spot = { station = st, spot = s }
    CreateThread(function()
        local ok, r = ESJ.call('whip_jobs:uni:list', spot)
        if not ok then WC:Notify(r, 'error') spot = nil return end
        r.where = spot
        ESJ.openUI('locker', withPictures(r))
        camOn()
    end)
end

local function reopen() if spot then ESJ.openLocker(spot.station, spot.spot) end end

-- the page closed (any way): the preview comes off, the camera goes
local closedBefore = ESJ.onClosed
ESJ.onClosed = function()
    if closedBefore then closedBefore() end
    undoPreview()
    camOff()
end

RegisterNUICallback('esj_preview', function(d, cb)
    d = type(d) == 'table' and d or {}
    local ped = PlayerPedId()
    if type(d.parts) == 'table' then
        if not before then before = read(ped) end
        ESJ.applyParts(ped, d.parts)
    else undoPreview() end
    cb({ ok = true })
end)

RegisterNUICallback('esj_turn', function(d, cb)
    local ped = PlayerPedId()
    local by = (type(d) == 'table' and tonumber(d.by)) or 45
    SetEntityHeading(ped, (GetEntityHeading(ped) + math.max(-180, math.min(180, by))) % 360)
    cb({ ok = true })
end)

RegisterNUICallback('esj_zoom', function(_, cb)
    cam.face = not cam.face
    if cam.on then camOn() end
    cb({ ok = true, face = cam.face })
end)

RegisterNUICallback('esj_personal', function(_, cb)
    cb({ ok = true })
    if not spot then return end
    local where = spot
    ESJ.closeUI()
    CreateThread(function()
        Wait(150)
        local ok, why = ESJ.call('whip_jobs:locker:open', where)
        if not ok then WC:Notify(why, 'error') end
    end)
end)

--- WHIP's own character editor on the clothes and props tabs: a leader making or changing a uniform, or an officer
--- adjusting the one they wear. The page closes for it and comes back after.
local function editor(o)
    local where = spot
    ESJ.closeUI()
    CreateThread(function()
        Wait(250)
        if o.prepare then
            local okp, why = ESJ.call('whip_jobs:uni:tryOn', { station = where.station, spot = where.spot, id = o.id })
            if not okp then WC:Notify(why, 'error') spot = where reopen() return end
            Wait(400)
        end
        local ok, why = WC:EditAppearance({
            only = { 'apparel', 'props' }, title = o.title, sub = o.sub,
            onSave = function(look)
                local data = { station = where.station, spot = where.spot, look = look }
                for k, v in pairs(o.data or {}) do data[k] = v end
                local okS, r = ESJ.call(o.save, data)
                if okS then return true end
                return false, tostring(r):sub(1, 60)
            end,
            onClose = function(saved)
                CreateThread(function()
                    Wait(600)
                    if o.after then o.after(saved, where) end
                    spot = where
                    reopen()
                end)
            end,
        })
        if not ok then WC:Notify(why or 'The editor could not open', 'error') spot = where reopen() end
    end)
end

RegisterNUICallback('esj_design', function(d, cb)
    d = type(d) == 'table' and d or {}
    cb({ ok = true })
    if not spot then return end
    local wasWearing = tonumber(d.wearing)
    editor({
        prepare = d.id ~= nil, id = tonumber(d.id), save = 'whip_jobs:uni:save',
        title = (d.id and 'Uniform: ' or 'New uniform: ') .. tostring(d.name or ''):sub(1, 40), sub = tostring(d.org or ''):sub(1, 60),
        data = { jobId = tonumber(d.jobId), id = tonumber(d.id), name = d.name, minLevel = tonumber(d.minLevel), skip = d.skip },
        after = function(_, where)
            -- back to what they wore before: that uniform (as it is now) or their own clothes
            local w = { station = where.station, spot = where.spot }
            if wasWearing then
                w.id = wasWearing
                local ok = ESJ.call('whip_jobs:uni:wear', w)
                if ok then return end
            end
            ESJ.call('whip_jobs:uni:own', w)
        end,
    })
end)

RegisterNUICallback('esj_adjust', function(_, cb)
    cb({ ok = true })
    if not spot then return end
    editor({ save = 'whip_jobs:uni:adjust', title = 'Adjust your uniform', sub = 'For this shift: your own clothes come back when you clock off' })
end)

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    undoPreview()
    camOff()
end)
