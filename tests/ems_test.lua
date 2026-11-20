-- whip_jobs 0.3.0 EMS: wounded, down, calls (upgrade in place), respawn hold, first aid, treat / revive, desk, records, bills
package.path = arg[0]:gsub('[^/]+$', '') .. '?.lua;' .. package.path
local H = require('harness')
local ok, WC = H.ok, H.WC

local lspd = H.addJob('police', 'LSPD', { { name = 'Officer', level = 30 } })
local ems = H.addJob('ems', 'LSFD', { { name = 'Paramedic', level = 30 }, { name = 'Chief', level = 100, permissions = { canManage = true } } })
H.depts = { { id = 1, jobId = lspd.jobId, short = 'LSPD', name = 'Los Santos Police', type = 'police', logoVer = 0 },
            { id = 2, jobId = ems.jobId, short = 'LSFD', name = 'Los Santos Fire & EMS', type = 'ems', logoVer = 0 } }
H.players[1] = { charId = 101, name = 'Medic Mia', duty = {} }
H.players[2] = { charId = 102, name = 'Chief Cole', duty = {} }
H.players[3] = { charId = 103, name = 'Civ Bob', duty = {} }
H.players[4] = { charId = 104, name = 'Civ Amy', duty = {} }
H.players[5] = { charId = 105, name = 'Broke Ben', duty = {} }
ems.members[101] = H.roleByName(ems, 'Paramedic').roleId
ems.members[102] = H.roleByName(ems, 'Chief').roleId
for s = 1, 5 do H.peds[s] = { x = 0, y = 0, z = 0 } end
local acctE = H.addAccount({ jobId = ems.jobId, balance = 0 })
for s = 1, 5 do H.addAccount({ charId = 100 + s, default = true, balance = (s == 5) and 0 or 5000 }) end
local function acctOf(cid) for _, a in pairs(H.accounts) do if a.charId == cid then return a end end end

H.load()
ok(not H.problem, 'started')
ok(H.items.whip_jobs_first_aid and H.items.whip_jobs_medbag, 'first aid kit and medical bag registered')
ok(H.sevents['whip_jobs:ems:info'] and H.sevents['whip_jobs:ems:info'].o.whileDead, 'the death report is allowed while dead')
ok(H.exports.HandlesDowns() == true, 'HandlesDowns: es_mdt keeps its own down alert quiet')

-- from here, threads run straight through (no waiting)
CreateThread = function(f) local w = Wait Wait = function() end f() Wait = w end
local function lastTo(src, n) for i = #H.client, 1, -1 do local c = H.client[i] if c.to == src and c.n == n then return c.args[1] end end end
local function die(src, info, reported)
  H.deadSet[src] = true
  if info then H.sevents['whip_jobs:ems:info'].fn(src, nil, info) end
  TriggerEvent('whip_core:player:died', { source = src, charId = WC:GetCharId(src), reported = reported })
end

-- ---------------------------------------------------------------- wounded
die(3, { headshot = false, cause = 'gunshot wound', street = 'Alta St' })
ok(not WC:IsPlayerDead(3) and H.revived[#H.revived].why == 'whip_jobs: wounded', 'a death becomes wounded: WHIP revives them where they lie')
ok(H.pstate[3].esHurt == 'wounded', 'statebag esHurt = wounded')
local m = lastTo(3, 'whip_jobs:client:hurt')
ok(m and m.state == 'wounded' and m.left == 180 and m.auto == 60, 'their game: wounded, 3 min, auto-call in 60 s')
ok(H.exports.GetHurtState(3) == 'wounded', 'GetHurtState')
ok(not H.calls or #H.calls == 0, 'no call yet')

local r = H.call(3, 'whip_jobs:ems:call', {})
ok(r and r.called and #H.calls == 1, 'Call EMS: one call')
local c1 = H.calls[1]
ok(c1.d.kind == 'medical' and c1.d.groups == 'ems' and c1.d.priority == 2 and c1.d.callerName == 'Civ Bob' and c1.d.message:find('gunshot'), 'a P2 medical call to EMS with the caller and the injury')
r = H.call(3, 'whip_jobs:ems:call', {})
ok(r and r.called and #H.calls == 1, 'pressing again files nothing new')

-- headshot: shorter
die(4, { headshot = true, cause = 'gunshot wound' })
m = lastTo(4, 'whip_jobs:client:hurt')
ok(m and m.state == 'wounded' and m.left == 60 and m.headshot, 'a headshot: wounded for 60 s')

-- auto-call
local now0 = os.time
local shift = 0
os.time = function(t) if t then return now0(t) end return now0() + shift end
shift = 61
ESJ.emsTick()
ok(#H.calls == 2 and H.calls[2].d.callerName == nil and H.calls[2].d.message:find('Automatic'), 'auto-call after 60 s (no caller name)')

-- ---------------------------------------------------------------- wounded -> down: the same call upgraded
die(3, nil)
ok(H.pstate[3].esHurt == 'down' and WC:IsPlayerDead(3), 'hurt again while wounded: down (stays dead)')
ok(#H.calls == 2 and c1.updated and c1.updated.priority == 1 and c1.updated.upgraded and c1.d.title:find('down'), 'the same call is upgraded to P1')
m = lastTo(3, 'whip_jobs:client:hurt')
ok(m and m.state == 'down', 'their game: down')

-- the respawn hold follows the units on the call
ESJ.emsTick() ESJ.emsTick()
ok(H.holds[3] == nil, 'no units: no hold')
c1.units = { { charId = 101, name = 'Medic Mia' } }
ESJ.emsTick() ESJ.emsTick()
ok(H.holds[3] and H.holds[3]:find('1 unit'), 'a unit attaches: respawn held (' .. tostring(H.holds[3]) .. ')')
c1.units = {}
ESJ.emsTick() ESJ.emsTick()
ok(H.holds[3] == nil, 'the unit leaves: hold released')
c1.units = { { charId = 101 } }
ESJ.emsTick() ESJ.emsTick()

-- ---------------------------------------------------------------- EMS revive
H.players[1].duty[ems.jobId] = true
r, why = H.call(1, 'whip_jobs:ems:revive', { target = 3 })
ok(r == false and why:find('medical bag'), 'a medic needs a medical bag')
H.inv[1] = { whip_jobs_medbag = 1 }
r, why = H.call(4, 'whip_jobs:ems:revive', { target = 3 })
ok(r == false and why:find('EMS'), 'a civilian cannot revive')
local eBefore, bBefore = acctE.balance, acctOf(103).balance
r = H.call(1, 'whip_jobs:ems:revive', { target = 3 })
ok(r == true and not WC:IsPlayerDead(3) and H.pstate[3].esHurt == nil, 'the medic revives them')
ok(c1.active == false and c1.outcome == 'Patient revived', 'the call closes: Patient revived')
ok(acctE.balance == eBefore + 500 and acctOf(103).balance == bBefore - 500, 'revive bill $500: patient bank -> EMS department account')
ok(H.T.med[#H.T.med].kind == 'revive' and H.T.med[#H.T.med].byName == 'Medic Mia', 'medical record written')
ok(H.T.ledger and next(H.T.ledger) ~= nil, 'department ledger has the income')

-- ---------------------------------------------------------------- first aid (anyone)
r, why = H.call(3, 'whip_jobs:ems:aid', { target = 4 })
ok(r == false and why:find('first aid kit'), 'first aid needs a kit')
H.inv[3] = { whip_jobs_first_aid = 2 }
r = H.call(3, 'whip_jobs:ems:aid', { target = 4 })
ok(r == true and H.pstate[4].esHurt == nil and H.inv[3].whip_jobs_first_aid == 1, 'helped up with a kit (one used)')
m = lastTo(4, 'whip_jobs:client:hurt')
ok(m and m.state == 'none' and m.health == 150, 'their game: up, health 150')
ok(H.calls[2].active == false, 'their call closed')
r, why = H.call(3, 'whip_jobs:ems:aid', { target = 4 })
ok(r == false and why:find('not wounded'), 'first aid only on the wounded')

-- ---------------------------------------------------------------- bleed out, respawn billed
die(5, nil)
ok(H.pstate[5].esHurt == 'wounded', 'Ben is wounded')
shift = shift + 200
ESJ.emsTick()
local bled = false for _, c in ipairs(H.client) do if c.to == 5 and c.n == 'whip_jobs:client:bleedOut' then bled = true end end
ok(bled, 'timer out: their game bleeds out')
die(5, nil)
ok(H.pstate[5].esHurt == 'down', 'bled out: down')
local cBen = H.calls[#H.calls]
ok(cBen.d.priority == 1 and cBen.d.title:find('down'), 'a down call at P1 (the auto-call was before the timer? either way P1 now)')
H.deadSet[5] = nil
TriggerEvent('whip_core:player:revived', { source = 5, charId = 105, how = 'respawned', reason = 'respawn' })
ok(H.pstate[5].esHurt == nil and cBen.active == false and cBen.outcome:find('hospital'), 'respawn: state cleared, call closed')
local bill
for _, b in ipairs(H.T.bills) do if b.charId == 105 then bill = b end end
ok(bill and bill.status == 'unpaid' and bill.amount == 750, 'Ben cannot pay: a $750 bill is left open')

-- ---------------------------------------------------------------- the hospital desk
r = H.call(4, 'whip_jobs:st:save', { name = 'Pillbox', jobs = { ems.jobId }, spots = { { id = 'desk', type = 'hospital', label = 'Front desk', x = 500, y = 0, z = 0, h = 0, ped = 's_m_m_doctor_01' } } })
ok(r == false, 'a civilian cannot make a hospital')
H.aces[2] = { ['whip_jobs.admin'] = true }
r, why = H.call(2, 'whip_jobs:st:save', { name = 'Pillbox', jobs = { ems.jobId }, spots = { { id = 'desk', type = 'hospital', label = 'Front desk', x = 500, y = 0, z = 0, h = 0, ped = 's_m_m_doctor_01' } } })
ok(r and r.id, 'the EMS chief saves a hospital with a desk: ' .. tostring(why))
local D = { station = r.id, spot = 'desk' }
local function with(a, b) local o = {} for k, v in pairs(a) do o[k] = v end for k, v in pairs(b) do o[k] = v end return o end
H.peds[5] = { x = 500, y = 0, z = 0 }
r = H.call(5, 'whip_jobs:spot:open', D)
ok(r and r.type == 'hospital' and r.hosp and #r.hosp.bills == 1 and r.hosp.staffed and r.hosp.medics == 1 and not r.hosp.medic, 'Ben at the desk: one bill, 1 medic on duty, no records tab')
H.health[5] = 150
r = H.call(5, 'whip_jobs:hosp:treat', D)
ok(r and r.called and H.calls[#H.calls].d.title:find('front desk') and H.calls[#H.calls].d.priority == 3, 'medics on duty: the desk calls them (P3)')
H.players[1].duty[ems.jobId] = nil
acctOf(105).balance = 2000
r = H.call(5, 'whip_jobs:hosp:treat', with(D, { method = 'bank' }))
ok(r and r.healed and acctOf(105).balance == 1600, 'nobody on duty: treated at the desk for $400')
m = lastTo(5, 'whip_jobs:client:hurt')
ok(m and m.health == 200, 'their game: full health')
r = H.call(5, 'whip_jobs:hosp:pay', with(D, { id = bill.id, method = 'bank' }))
ok(r and #r.bills == 0 and bill.status == 'paid' and acctOf(105).balance == 850, 'Ben pays the open $750 bill')
r, why = H.call(5, 'whip_jobs:hosp:pay', with(D, { id = bill.id, method = 'bank' }))
ok(r == false and why:find('not open'), 'a paid bill cannot be paid twice')

-- ---------------------------------------------------------------- medical records
r, why = H.call(5, 'whip_jobs:med:list', D)
ok(r == false and why:find('EMS'), 'records are for EMS on duty')
H.players[1].duty[ems.jobId] = true
H.peds[1] = { x = 500, y = 0, z = 0 }
r = H.call(1, 'whip_jobs:med:list', D)
ok(r and #r.patients >= 3 and #r.recent >= 3, 'the medic sees patients and the latest records')
r = H.call(1, 'whip_jobs:med:list', with(D, { q = 'ben' }))
ok(r and #r.patients == 1 and r.patients[1].charId == 105, 'search by name')
r = H.call(1, 'whip_jobs:med:patient', with(D, { charId = 103 }))
ok(r and r.name == 'Civ Bob' and r.records[1].kind == 'revive', "Bob's record: the revive")
r = H.call(1, 'whip_jobs:med:note', with(D, { charId = 103, text = 'Allergic to penicillin' }))
ok(r and r.records[1].kind == 'note' and r.records[1].notes:find('penicillin'), 'a note added')
-- a bill waived by the chief
die(4, nil) H.deadSet[4] = nil
acctOf(104).balance = 0
TriggerEvent('whip_core:player:revived', { source = 4, charId = 104, how = 'respawned', reason = 'respawn' })
local amyBill
for _, b in ipairs(H.T.bills) do if b.charId == 104 and b.status == 'unpaid' then amyBill = b end end
r, why = H.call(1, 'whip_jobs:med:waive', with(D, { id = amyBill.id }))
ok(r == false and why:find('leaders'), 'a paramedic cannot waive a bill')
H.players[2].duty[ems.jobId] = true
H.peds[2] = { x = 500, y = 0, z = 0 }
r = H.call(2, 'whip_jobs:med:waive', with(D, { id = amyBill.id }))
ok(r and amyBill.status == 'waived', 'the chief waives it')

-- ---------------------------------------------------------------- treat (alive), examine
H.peds[3] = { x = 500, y = 0, z = 0 }
H.health[3] = 160
r = H.call(1, 'whip_jobs:ems:examine', { target = 3 })
ok(r and r.state == 'ok' and r.health == 60, 'examine: conscious, 60%')
r = H.call(1, 'whip_jobs:ems:treat', { target = 3 })
ok(r == true and H.T.med[#H.T.med].kind == 'treat', 'treat an injured person (record)')
H.health[3] = 200
r, why = H.call(1, 'whip_jobs:ems:treat', { target = 3 })
ok(r == false and why:find('not hurt'), 'not hurt: nothing to treat')

-- ---------------------------------------------------------------- off: plain WHIP
Config.EMS.enabled = false
ok(H.exports.HandlesDowns() == false, 'EMS off: es_mdt alerts downs again')
local n = #H.revived
die(4, nil)
ok(WC:IsPlayerDead(4) and #H.revived == n and H.pstate[4].esHurt == nil, 'EMS off: a death stays a plain WHIP death')
os.time = now0
print(H.fails == 0 and '== whip_jobs ems: all passed' or ('== whip_jobs ems: ' .. H.fails .. ' FAILED'))
