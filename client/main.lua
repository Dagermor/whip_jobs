-- whip_jobs: the screen. One NUI page (html/) with three views: a station spot (duty, armory, garage, locker), the station
-- editor (admin menu / Departments -> Locations) and Businesses (/business). The page asks the server through `call` (a SecureCallback each).
ESJ = ESJ or {}
ESJ.ui = { open = false, view = nil }

local ALLOWED = {
    ['whip_jobs:biz:list'] = true, ['whip_jobs:org:get'] = true, ['whip_jobs:biz:create'] = true, ['whip_jobs:biz:update'] = true,
    ['whip_jobs:biz:logoPart'] = true, ['whip_jobs:biz:logo'] = true, ['whip_jobs:biz:rank'] = true, ['whip_jobs:biz:rankDelete'] = true,
    ['whip_jobs:biz:nearby'] = true, ['whip_jobs:biz:hire'] = true, ['whip_jobs:biz:setRank'] = true, ['whip_jobs:biz:fire'] = true,
    ['whip_jobs:biz:delete'] = true, ['whip_jobs:pay:set'] = true,
    ['whip_jobs:st:list'] = true, ['whip_jobs:st:save'] = true, ['whip_jobs:st:delete'] = true, ['whip_jobs:st:history'] = true,
    ['whip_jobs:st:restore'] = true, ['whip_jobs:st:undo'] = true, ['whip_jobs:st:export'] = true, ['whip_jobs:st:import'] = true,
    ['whip_jobs:st:teleport'] = true,
    ['whip_jobs:spot:open'] = true, ['whip_jobs:duty'] = true, ['whip_jobs:armory:take'] = true, ['whip_jobs:armory:return'] = true,
    ['whip_jobs:fleet:take'] = true, ['whip_jobs:fleet:return'] = true, ['whip_jobs:locker:open'] = true,
    ['whip_jobs:uni:list'] = true, ['whip_jobs:uni:wear'] = true, ['whip_jobs:uni:own'] = true, ['whip_jobs:uni:save'] = true,
    ['whip_jobs:uni:delete'] = true, ['whip_jobs:uni:order'] = true, ['whip_jobs:imp:pay'] = true, ['whip_jobs:imp:take'] = true,
    ['whip_jobs:hosp:treat'] = true, ['whip_jobs:hosp:pay'] = true, ['whip_jobs:med:list'] = true, ['whip_jobs:med:patient'] = true,
    ['whip_jobs:med:note'] = true, ['whip_jobs:med:waive'] = true,
}

--- ask the server; returns ok, data|why
function ESJ.call(name, d)
    local ok, a, b = pcall(function() return Whip.core:Callback(name, d or {}) end)
    if not ok then return false, 'The server did not answer' end
    if a == false or a == nil then return false, b or 'Refused' end
    return true, a
end

function ESJ.openUI(view, data)
    ESJ.ui.open, ESJ.ui.view = true, view
    SendNUIMessage({ action = 'open', view = view, data = data or {}, me = { serverId = GetPlayerServerId(PlayerId()) } })
    pcall(function() exports.whip_core:SetScreenOpen(true) end)
    ESJPAD.open()
end

function ESJ.closeUI()
    if not ESJ.ui.open then return end
    ESJ.ui.open, ESJ.ui.view = false, nil
    SendNUIMessage({ action = 'close' })
    ESJPAD.close()
    pcall(function() exports.whip_core:SetScreenOpen(false) end)
    if ESJ.onClosed then ESJ.onClosed() end
end

RegisterNUICallback('esj_close', function(_, cb) ESJ.closeUI() cb({}) end)

-- the page's calls: only the names above, one table each
RegisterNUICallback('esj_call', function(d, cb)
    d = type(d) == 'table' and d or {}
    local name = d.name
    if type(name) ~= 'string' or not ALLOWED[name] then return cb({ ok = false, why = 'Unknown call' }) end
    CreateThread(function()
        local ok, r = ESJ.call(name, type(d.data) == 'table' and d.data or {})
        cb({ ok = ok, data = ok and r or nil, why = (not ok) and tostring(r) or nil })
    end)
end)

-- a department's logo comes from es_mdt (its own cache, client side); a business's from us
RegisterNUICallback('esj_deptLogo', function(d, cb)
    d = type(d) == 'table' and d or {}
    if GetResourceState('es_mdt') ~= 'started' then return cb({ ok = false }) end
    CreateThread(function()
        local ok, url = pcall(function() return exports.es_mdt:GetLogo(tonumber(d.id), tonumber(d.ver)) end)
        cb({ ok = ok and type(url) == 'string', url = ok and type(url) == 'string' and url or nil })
    end)
end)

RegisterNetEvent('whip_jobs:client:open', function(o)
    o = type(o) == 'table' and o or {}
    if o.view == 'stations' then
        if ESJ.openEditor then ESJ.openEditor() end
    elseif o.view == 'business' then
        ESJ.openUI('business', {})
    end
end)

RegisterNetEvent('whip_jobs:client:bizChanged', function(id)
    if ESJ.ui.open then SendNUIMessage({ action = 'bizChanged', id = id }) end
end)

-- other resources (es_mdt's Departments wizard: "Set up locations") open our screens
exports('OpenStations', function(opts)
    if ESJ.openEditor then ESJ.openEditor(type(opts) == 'table' and opts or {}) end
end)
exports('OpenBusiness', function() ESJ.openUI('business', {}) end)
exports('IsOpen', function() return ESJ.ui.open end)

AddEventHandler('onResourceStop', function(r)
    if r == GetCurrentResourceName() and ESJ.ui.open then SetNuiFocus(false, false) end
end)
