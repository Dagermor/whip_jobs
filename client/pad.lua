-- es_jobs: a controller in every es_jobs screen, the way es_mdt does it. WHIP reads the pad (Whip.padScreen: the browser
-- cannot see a gamepad inside FiveM); html/pad.js moves the highlight, A picks, B goes back, LB / RB switch tabs, and a
-- text box opens WHIP's on-screen keyboard. Nothing here runs while no es_jobs screen is open.
ESJPAD = {}
local screen, owned, padActive = nil, false, false
local AX = { t = 0, live = false }
local LT, RT = { 207, 25, 72 }, { 208, 24, 71 }

local function dz(v) if v > -0.15 and v < 0.15 then return 0.0 end return math.floor(v * 100 + 0.5) / 100 end
local function trig(list)
    local v = 0.0
    for i = 1, #list do local n = GetDisabledControlNormal(0, list[i]) if n > v then v = n end end
    return v > 0.08 and math.floor(v * 100 + 0.5) / 100 or 0.0
end

local function stateMsg(open)
    return { action = 'padState', open = open, nav = true, keyboard = true, hints = 'xbox', sens = 100,
        pad = (owned and screen and screen:isPad()) or padActive }
end

if Whip and Whip.padScreen then
    screen = Whip.padScreen({
        buttons = { 'up', 'down', 'left', 'right', 'a', 'b', 'x', 'y', 'lb', 'rb', 'menu' },
        stick = false,
        onButton = function(cmd, down, rep) if down then SendNUIMessage({ action = 'pad', cmd = cmd, rep = rep }) end end,
        onDevice = function(pad) padActive = pad SendNUIMessage({ action = 'padDevice', pad = pad, hints = 'xbox' }) end,
        onFrame = function()
            local lx, ly = dz(GetDisabledControlNormal(0, 30)), dz(GetDisabledControlNormal(0, 31))
            local rx, ry = dz(GetDisabledControlNormal(0, 1)), dz(GetDisabledControlNormal(0, 2))
            local lt, rt = trig(LT), trig(RT)
            local any = lx ~= 0 or ly ~= 0 or rx ~= 0 or ry ~= 0 or lt ~= 0 or rt ~= 0
            if not any and not AX.live then return end
            local now = GetGameTimer()
            if any and AX.live and now - AX.t < 50 then return end
            AX.t, AX.live = now, any
            SendNUIMessage({ action = 'padAxes', lx = lx, ly = ly, rx = rx, ry = ry, lt = lt, rt = rt })
        end,
    })
end
AddEventHandler('whip_core:pad:deviceChanged', function(e) padActive = type(e) == 'table' and e.pad == true end)

--- the screen is up: the pad screen takes the NUI focus (or the mouse alone, without whip_core's pad support)
function ESJPAD.open()
    if screen then
        if not owned then owned = true screen:open() end
    else SetNuiFocus(true, true) end
    SendNUIMessage(stateMsg(true))
end
function ESJPAD.close()
    if screen and owned then owned = false AX.live = false screen:close() end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'padState', open = false })
end
--- the editor lets go of the screen while a ghost is being placed (the game needs the pad and keys then)
function ESJPAD.owns() return owned end
function ESJPAD.pause(on) if screen and owned then screen:pause(on) end end

local kbBusy = false
local function gtaKeyboard(o)
    if screen and owned then screen:pause(true) end
    SetNuiFocus(false, false)
    DisplayOnscreenKeyboard(1, 'FMMC_KEY_TIP8', '', o.value or '', '', '', '', o.maxLength or 255)
    local status = 0
    repeat Wait(0) status = UpdateOnscreenKeyboard() until status ~= 0
    local text = status == 1 and GetOnscreenKeyboardResult() or nil
    if screen and owned then screen:pause(false) else SetNuiFocus(true, true) end
    return text
end

RegisterNUICallback('esui_padKeyboard', function(d, cb)
    d = type(d) == 'table' and d or {}
    if kbBusy then return cb({ ok = false, why = 'busy' }) end
    local o = { title = tostring(d.title or 'Type'):sub(1, 80), value = tostring(d.value or ''):sub(1, 2000),
        placeholder = tostring(d.placeholder or ''):sub(1, 120), maxLength = math.max(1, math.min(2000, math.floor(tonumber(d.maxLength) or 255))),
        numeric = d.numeric == true, predict = d.predict ~= false }
    kbBusy = true
    CreateThread(function()
        local text
        local ok, r = pcall(function() return exports.whip_core:OpenKeyboard(o) end)
        if ok then text = r else text = gtaKeyboard(o) end
        kbBusy = false
        cb({ ok = type(text) == 'string', text = type(text) == 'string' and text or nil })
    end)
end)
RegisterNUICallback('esui_padState', function(_, cb) local m = stateMsg(owned) m.action = nil cb(m) end)
