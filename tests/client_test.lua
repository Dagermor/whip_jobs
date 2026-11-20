-- whip_jobs 0.1.0 client: loads, NUI callbacks, prompts per spot (job-gated), blips by audience, the call whitelist
local ROOT = arg[1]
local fails = 0
local function ok(c, m) if c then print('PASS ' .. m) else fails = fails + 1 print('FAIL ' .. m) end end
local stubmt = {}
local function stub(n) return setmetatable({ __n = n }, stubmt) end
stubmt.__index = function(t, k) return stub(t.__n .. '.' .. k) end
stubmt.__call = function() return 0 end
local handlers, NUICB, NUIMSG, EXP = {}, {}, {}, {}
function AddEventHandler(n, fn) handlers[n] = handlers[n] or {} table.insert(handlers[n], fn) end
function RegisterNetEvent(n, fn) if fn then AddEventHandler(n, fn) end end
function TriggerEvent(n, ...) for _, f in ipairs(handlers[n] or {}) do f(...) end end
function RegisterNUICallback(n, f) NUICB[n] = f end
function SendNUIMessage(m) NUIMSG[#NUIMSG + 1] = m end
function SetNuiFocus() end
function CreateThread(f) local co = coroutine.create(f) coroutine.resume(co) end
function Wait() if coroutine.isyieldable() then coroutine.yield() end end
function GetResourceState() return 'started' end
function GetCurrentResourceName() return 'whip_jobs' end
function GetGameTimer() return 0 end
json = { encode = function() return '{}' end, decode = function() return {} end }
function vector3(x, y, z) return { x = x, y = y, z = z } end
local actions, removed, blips, myJobs, calls = {}, {}, {}, {}, {}
local nextBlip = 0
function AddBlipForCoord() nextBlip = nextBlip + 1 blips[nextBlip] = true return nextBlip end
function DoesBlipExist(b) return blips[b] end
function RemoveBlip(b) blips[b] = nil end
local WC = {
  AddAction = function(_, d) actions[d.id] = d return d.id end, RemoveAction = function(_, id) actions[id] = nil removed[#removed + 1] = id return true end,
  GetPlayerJobs = function() return myJobs end, SetBlipLabel = function() return true end, Notify = function() end,
  Callback = function(_, name, d) calls[#calls + 1] = name return { ok = true } end,
  SetScreenOpen = function() return true end,
  OpenPortal = function(_, o) rawset(_G, 'PORTAL', o) end, OpenTablet = function() rawset(_G, 'TABLET', true) end,
  RegisterDevPage = function(_, id, def) local t = rawget(_G, 'DEVPAGES') or {} rawset(_G, 'DEVPAGES', t) t[id] = def return true end,
  RefreshDevPage = function() return true end,
}
exports = setmetatable({}, { __index = function(_, r) return setmetatable({}, { __index = function(_, k) return function(_, ...) return WC[k](WC, ...) end end }) end,
  __call = function(_, n, f) EXP[n] = f end })
Whip = { core = setmetatable({}, { __index = function(_, k) return function(_, ...) return WC[k](WC, ...) end end }), ready = function() return true end,
  padScreen = function() return { open = function() end, close = function() end, pause = function() end, isPad = function() return false end } end,
  configPage = function() end, register = function(fn) local t = rawget(_G, 'REGS') or {} rawset(_G, 'REGS', t) t[#t + 1] = fn end }
setmetatable(_G, { __index = function(_, k) return stub(k) end })
local man = io.open(ROOT .. '/fxmanifest.lua'):read('a'):gsub('%-%-[^\n]*', '')
local files = {}
for _, key in ipairs({ 'shared_scripts', 'client_scripts' }) do local b = man:match(key .. '%s*(%b{})') for f in b:gmatch("'([^']+)'") do if f:sub(1, 1) ~= '@' then files[#files + 1] = f end end end
for _, f in ipairs(files) do local c = assert(loadfile(ROOT .. '/' .. f)) local o, e = pcall(c) if not o then print('LOADERR', f, e) fails = fails + 1 end end
for _, fn in ipairs(rawget(_G, 'REGS') or {}) do fn() end
for _, n in ipairs({ 'esj_call', 'esj_close', 'esj_place', 'esj_myPos', 'esj_teleport', 'esj_checkSpawn', 'esj_deptLogo', 'esui_padKeyboard', 'esui_padState' }) do
  ok(NUICB[n] ~= nil, 'NUI callback ' .. n) end
ok(EXP.OpenStations and EXP.OpenBusiness and EXP.IsOpen, 'client exports')
-- stations arrive: LSPD (job 11) station with a duty desk, an armory and a garage; a hidden-blip business station
TriggerEvent('whip_jobs:client:stations', {
  { id = 1, name = 'Mission Row', jobs = { 11, 12 }, blip = { show = 'everyone', sprite = 60, color = 29 }, spots = {
    { id = 'duty', type = 'duty', label = 'Duty', x = 1, y = 0, z = 0, h = 0, ped = 's_m_y_cop_01' },
    { id = 'arm', type = 'armory', label = 'Armory', x = 2, y = 0, z = 0, h = 0, ped = false },
    { id = 'gar', type = 'garage', label = 'Garage', x = 3, y = 0, z = 0, h = 0, ped = 's_m_y_cop_01' } } },
  { id = 2, name = 'Bean Machine', jobs = { 20 }, blip = { show = 'members' }, spots = { { id = 'd', type = 'duty', label = 'Clock in', x = 9, y = 0, z = 0, h = 0, ped = false } } },
  { id = 3, name = 'Orphan', jobs = {}, blip = { show = 'everyone' }, spots = { { id = 'd', type = 'duty', label = 'x', x = 0, y = 0, z = 0, h = 0 } } },
}, { ['11'] = { short = 'LSPD' }, ['12'] = { short = 'BCSO' } })
do
  local pg = rawget(_G, 'DEVPAGES') and DEVPAGES.stations
  ok(pg and pg.label == 'Stations', 'admin menu (/w) has a Stations page')
  local v = pg.rows()
  local names = {}
  for _, r in ipairs(v.rows) do names[#names + 1] = r.label end
  ok(v.rows[1].id == 'open' and v.rows[1].close, '/w Stations: open the editor first')
  ok(table.concat(names, '|'):find('Mission Row', 1, true), '/w Stations lists the stations')
  local opened
  local real = ESJ.openEditor
  ESJ.openEditor = function(o) opened = o end
  pg.onSelect('st:1'); local v2 = pg.rows()
  ok(v2.title == 'Mission Row' and v2.back == 'Stations', '/w Stations: a station opens a level')
  pg.onSelect('edit'); ok(opened and opened.stationId == 1, '/w Stations: open that station in the editor')
  pg.onBack(); ok(pg.rows().rows[1].id == 'open', '/w Stations: back to the list')
  pg.onSelect('new'); ok(opened and opened.new == true, '/w Stations: new station')
  ESJ.openEditor = real
end
local duty, arm, gar, ret = actions['st1_duty'], actions['st1_arm'], actions['st1_gar'], actions['st1_gar_ret']
ok(duty and duty.require.job[1] == 11 and duty.require.job[2] == 12 and not duty.require.onDuty, 'duty prompt: members of LSPD or BCSO, on or off duty')
ok(arm and arm.require.onDuty == true, 'armory prompt: on duty only')
ok(gar and ret and ret.require.vehicle == 'in' and gar.require.vehicle == 'out', 'garage: on foot to take, in a car to put back')
ok(duty.description == 'LSPD / BCSO', 'prompt names the departments')
ok(actions['st3_d'] == nil, 'a station nobody shares has no prompts')
local nb = 0 for _ in pairs(blips) do nb = nb + 1 end
ok(nb == 2, 'blips: Mission Row (everyone) and Orphan; not Bean Machine (members only, not one)')
myJobs = { [20] = { roleName = 'Barista' } }
TriggerEvent('whip_core:job:listChanged', {})
nb = 0 for _ in pairs(blips) do nb = nb + 1 end
ok(nb == 3, 'hired at Bean Machine: its members-only blip appears')
-- 0.4.0: the DOJ's spots
TriggerEvent('whip_jobs:client:stations', {
  { id = 7, name = 'Courthouse', jobs = { 30 }, blip = { show = 'everyone' }, spots = {
    { id = 'ck', type = 'court_clerk', label = 'Court clerk', x = 1, y = 0, z = 0, h = 0, ped = 'a_f_y_business_01' },
    { id = 'cr', type = 'courtroom', label = 'Courtroom 1', x = 2, y = 0, z = 0, h = 0, ped = 's_m_m_highsec_01' },
    { id = 'ch', type = 'chambers', label = 'Chambers', x = 3, y = 0, z = 0, h = 0, ped = 'a_m_m_business_01' },
    { id = 'da', type = 'da_office', label = 'DA', x = 4, y = 0, z = 0, h = 0, ped = false },
    { id = 'pd', type = 'pd_office', label = 'PD', x = 5, y = 0, z = 0, h = 0, ped = false } } },
}, { ['30'] = { short = 'DOJ' } })
do
  local ck, cr, ch, da, pd = actions.st7_ck, actions.st7_cr, actions.st7_ch, actions.st7_da, actions.st7_pd
  ok(ck and not ck.require.job and ck.options and #ck.options == 2 and ck.options[2].label == 'Pay a fine or fee', 'DOJ clerk window: anyone, court services and pay a fine or fee (no bail)')
  ok(ck.description == 'Courthouse', 'clerk window prompt names the courthouse')
  ck.options[2].onSelect(); ok(PORTAL and PORTAL.desk == true and PORTAL.view == 'pay', 'clerk window: pay opens the portal on Payments, at the window')
  ok(cr and not cr.require.job and cr.options[2].require.job[1] == 30, 'courtroom: anyone sees their cases; only DOJ staff get the tablet')
  cr.options[1].onSelect(); ok(PORTAL.view == 'mycases' and not PORTAL.desk, 'courtroom: My cases')
  ok(ch and ch.require.job[1] == 30 and da and da.require.job[1] == 30, "judge's chambers and DA office: DOJ staff only")
  ch.options[1].onSelect(); ok(TABLET == true, 'chambers opens the DOJ tablet')
  ok(pd and not pd.require.job and pd.options[1].label:find('public defender'), 'public defender office: anyone can ask for a lawyer')
  local ex = EXP.GetStarter('doj')
  local keys = {} for _, x in ipairs(ex) do keys[#keys + 1] = x.key .. '=' .. tostring(x.ped) end
  ok(#ex == 7 and table.concat(keys, ','):find('court_clerk=a_f_y_business_01', 1, true) and table.concat(keys, ','):find('chambers=a_m_m_business_01', 1, true),
    'GetStarter(doj): the full DOJ set with their own default peds (' .. table.concat(keys, ',') .. ')')
  ok(#EXP.GetStarter('police') == 4 and #EXP.GetStarter('nothing') == 0, 'GetStarter: police set; unknown type empty')
end
-- updating the list replaces the prompts
TriggerEvent('whip_jobs:client:stations', {}, {})
local leftover = nil for k in pairs(actions) do if k ~= 'esj_ems_aid' then leftover = k end end
ok(leftover == nil, 'stations gone: prompts removed (' .. tostring(leftover) .. ')')
ok(actions.esj_ems_aid ~= nil, 'First aid prompt (0.3.0) stays: it is not a station prompt')
-- the page may only call whip_jobs callbacks on the list
local answered
NUICB.esj_call({ name = 'whip_core:admin:giveMoney', data = {} }, function(r) answered = r end)
ok(answered and answered.ok == false and answered.why == 'Unknown call', 'page cannot call anything off the list')
NUICB.esj_call({ name = 'whip_jobs:biz:list', data = {} }, function(r) answered = r end)
ok(calls[#calls] == 'whip_jobs:biz:list', 'listed call goes to the server')
print(fails == 0 and '== whip_jobs client: all passed' or ('== whip_jobs client: ' .. fails .. ' FAILED'))
