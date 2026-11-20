-- whip_jobs 0.2.0 server: stations, gear, pay, businesses, against an in-memory whip_core / es_mdt / MySQL
package.path = arg[0]:gsub('[^/]+$', '') .. '?.lua;' .. package.path
local H = require('harness')
local ok, WC = H.ok, H.WC

-- the city: LSPD and BCSO (es_mdt departments), two officers, a civilian, an admin
local lspd = H.addJob('police', 'LSPD', { { name = 'Officer', level = 30 }, { name = 'Sergeant', level = 60 }, { name = 'Chief', level = 100, permissions = { canManage = true } } })
local bcso = H.addJob('bcso', 'BCSO', { { name = 'Deputy', level = 30 }, { name = 'Sheriff', level = 100, permissions = { canManage = true } } })
H.depts = { { id = 1, jobId = lspd.jobId, short = 'LSPD', name = 'Los Santos Police', type = 'police', color1 = '#1b2a5c', logoVer = 1 },
            { id = 2, jobId = bcso.jobId, short = 'BCSO', name = 'Blaine County Sheriff', type = 'sheriff', logoVer = 0 } }
H.players[1] = { charId = 101, name = 'Officer Lee', duty = {} }    -- LSPD officer
H.players[2] = { charId = 102, name = 'Chief Hale', duty = {} }     -- LSPD chief (leader)
H.players[3] = { charId = 103, name = 'Civ Bob', duty = {} }
H.players[4] = { charId = 104, name = 'Admin Ann', duty = {} }
H.players[5] = { charId = 105, name = 'Deputy Ray', duty = {} }     -- BCSO
lspd.members[101] = H.roleByName(lspd, 'Officer').roleId
lspd.members[102] = H.roleByName(lspd, 'Chief').roleId
bcso.members[105] = H.roleByName(bcso, 'Deputy').roleId
H.aces[4] = { ['whip_jobs.admin'] = true }
for s = 1, 5 do H.peds[s] = { x = 0, y = 0, z = 0 } end
local acctL = H.addAccount({ jobId = lspd.jobId, balance = 1000 })
for s = 1, 5 do H.addAccount({ charId = 100 + s, default = true, balance = (s == 3) and 30000 or 0 }) end
local function acctOf(cid) for _, a in pairs(H.accounts) do if a.charId == cid then return a end end end

debug.sethook(function() error('LOOP in load: ' .. debug.traceback()) end, '', 20000000)
H.load()
debug.sethook()
ok(not H.problem, 'started without start problems')
ok(H.cbs['whip_jobs:st:save'] and H.cbs['whip_jobs:biz:create'] and H.cbs['whip_jobs:spot:open'] and H.cbs['whip_jobs:pay:set'], 'callbacks registered')
ok(H.exports.GetStations and H.exports.GetSpots and H.exports.RecordIncome, 'exports')

-- ---------------------------------------------------------------- stations
local function spot(t, x, extra) local s = { id = t, type = t, label = t, x = x, y = 0, z = 0, h = 90, ped = 's_m_y_cop_01' } for k, v in pairs(extra or {}) do s[k] = v end return s end
local r, why = H.call(3, 'whip_jobs:st:list')
ok(r == false, 'a civilian cannot open the editor: ' .. tostring(why))
r = H.call(2, 'whip_jobs:st:list')
ok(r and #r.orgs == 2 and r.orgs[1].ped == 's_m_y_cop_01' and r.orgs[2].ped == 's_m_y_sheriff_01', 'leader sees orgs with default peds by type')
r, why = H.call(2, 'whip_jobs:st:save', { name = 'Mission Row', jobs = { lspd.jobId, bcso.jobId }, spots = {} })
ok(r == false and why:find('only add departments you lead'), 'leader cannot add a department they do not lead')
r, why = H.call(2, 'whip_jobs:st:save', { name = 'Mission Row', jobs = { lspd.jobId }, spots = { { type = 'duty', label = 'Duty' } } })
ok(r == false and why:find('not placed'), 'an unplaced spot is refused: ' .. tostring(why))
r, why = H.call(2, 'whip_jobs:st:save', { name = 'Mission Row', jobs = { lspd.jobId }, spots = { spot('armory', 2, { stock = { { item = 'nukes', min = 0, max = 1 } } }) } })
ok(r == false and why:find('not an item'), 'an unknown item is refused')
ESJ.PHASE = 3   -- as before 0.4.0: the DOJ spots were not built yet
r, why = H.call(2, 'whip_jobs:st:save', { name = 'Mission Row', jobs = { lspd.jobId }, spots = { spot('court_clerk', 2) } })
ESJ.PHASE = 4
ok(r == false and why:find('later update'), 'a later-phase spot type is refused')
r, why = H.call(2, 'whip_jobs:st:save', { name = 'Mission Row', jobs = { lspd.jobId }, spots = {
  spot('duty', 1), spot('armory', 2, { stock = { { item = 'handcuffs', min = 0, max = 2 }, { item = 'weapon_stungun', min = 60, max = 1 } } }),
  spot('garage', 3, { vehicles = { { model = 'police3', label = 'Cruiser', min = 0 } }, spawns = { { x = 10, y = 0, z = 0, h = 0 }, { x = 20, y = 0, z = 0, h = 0 } } }),
  spot('locker', 4, { ped = false }) } })
ok(r and r.id == 1 and r.rev == 1 and #r.spots == 4, 'leader saves a station with 4 spots')
local st = H.T.st[1]
ok(json.decode(st.jobs)[1] == lspd.jobId, 'stored the jobs')
ok(H.client[#H.client].n == 'whip_jobs:client:stations' and H.client[#H.client].to == -1, 'stations pushed to everyone')
local pub = H.exports.GetStations()
ok(#pub == 1 and pub[1].spots[2].stock == nil, 'public view has no stock lists')
ok(#H.exports.GetSpots('garage', lspd.jobId) == 1 and #H.exports.GetSpots('garage', bcso.jobId) == 0, 'GetSpots by type and job')
-- conflicts and the admin sharing it
r, why = H.call(4, 'whip_jobs:st:save', { id = 1, rev = 0, name = 'X', jobs = { lspd.jobId }, spots = {} })
ok(r == false and why:find('Someone else'), 'stale rev refused')
local full = H.call(4, 'whip_jobs:st:list').stations[1]
full.jobs = { lspd.jobId, bcso.jobId }
r = H.call(4, 'whip_jobs:st:save', { id = 1, rev = full.rev, name = full.name, jobs = full.jobs, blip = full.blip, spots = full.spots })
ok(r and r.rev == 2, 'admin shares it with BCSO')
-- the LSPD chief edits: BCSO (not theirs) stays on it
full = H.call(2, 'whip_jobs:st:list').stations[1]
r = H.call(2, 'whip_jobs:st:save', { id = 1, rev = full.rev, name = 'Mission Row PD', jobs = { lspd.jobId }, blip = full.blip, spots = full.spots })
ok(r and #json.decode(H.T.st[1].jobs) == 2, 'a leader removing a department they do not lead: it stays')
-- undo goes back one save
r = H.call(2, 'whip_jobs:st:undo', { id = 1 })
ok(r and r.name == 'Mission Row', 'undo: back to the name before the last save')
local hist = H.call(2, 'whip_jobs:st:history', { id = 1 })
ok(#hist >= 1 and hist[1].who, 'history lists versions with who')

-- ---------------------------------------------------------------- duty, armory
local function at(src, x) H.peds[src] = { x = x, y = 0, z = 0 } end
at(1, 1)
r = H.call(1, 'whip_jobs:spot:open', { station = 1, spot = 'duty' })
ok(r and r.type == 'duty' and #r.jobs == 1 and r.jobs[1].onDuty == false and r.jobs[1].pay == 240, 'duty desk: LSPD, off duty, $240 for a level 30 (150 + 30x3)')
at(3, 1)
r, why = H.call(3, 'whip_jobs:spot:open', { station = 1, spot = 'duty' })
ok(r == false and why:find('This is for'), 'a civilian is refused at the duty desk')
at(1, 50)
r, why = H.call(1, 'whip_jobs:duty', { station = 1, spot = 'duty', jobId = lspd.jobId, on = true })
ok(r == false and why == 'Go to it first', 'too far from the desk')
at(1, 1)
r = H.call(1, 'whip_jobs:duty', { station = 1, spot = 'duty', jobId = lspd.jobId, on = true })
ok(r == true and H.players[1].duty[lspd.jobId], 'clocked on at the desk')
at(1, 2)
r = H.call(1, 'whip_jobs:spot:open', { station = 1, spot = 'armory' })
ok(r and r.items[1].allowed and not r.items[2].allowed, 'armory: cuffs allowed, taser needs a sergeant')
r, why = H.call(1, 'whip_jobs:armory:take', { station = 1, spot = 'armory', item = 'weapon_stungun' })
ok(r == false and why:find('rank'), 'rank too low for the taser')
H.call(1, 'whip_jobs:armory:take', { station = 1, spot = 'armory', item = 'handcuffs' })
H.call(1, 'whip_jobs:armory:take', { station = 1, spot = 'armory', item = 'handcuffs' })
r, why = H.call(1, 'whip_jobs:armory:take', { station = 1, spot = 'armory', item = 'handcuffs' })
ok(H.inv[1].handcuffs == 2 and r == false and why:find('the most is 2'), 'capped at the stock max')
r = H.call(1, 'whip_jobs:armory:return', { station = 1, spot = 'armory', item = 'handcuffs' })
ok(r and r.have == 1, 'handed one back')
at(5, 2)
r, why = H.call(5, 'whip_jobs:armory:take', { station = 1, spot = 'armory', item = 'handcuffs' })
ok(r == false and why == 'Clock on first', 'BCSO deputy off duty: refused')

-- ---------------------------------------------------------------- fleet
at(1, 3)
r = H.call(1, 'whip_jobs:fleet:take', { station = 1, spot = 'garage', model = 'police3' })
ok(r and r.plate:sub(1, 4) == 'LSPD', 'fleet car out with an LSPD plate')
local vid = next(H.spawned)
ok(H.spawned[vid].o.forSource == 1 and H.spawned[vid].o.tag == 'whip_jobs_fleet' and H.spawned[vid].c.x == 10, 'spawned for them, tagged, at the first space')
r, why = H.call(1, 'whip_jobs:fleet:take', { station = 1, spot = 'garage', model = 'police3' })
ok(r == false and why:find('back first'), 'one each')
ok(H.exports.GetFleetVehicle(101) ~= nil and H.exports.GetFleetVehicle(101).plate:sub(1, 4) == 'LSPD', 'export knows the fleet car')
H.vehPos[H.spawned[vid].ent] = { x = 500, y = 0, z = 0 }
r, why = H.call(1, 'whip_jobs:fleet:return', { station = 1, spot = 'garage' })
ok(r == false and why:find('back to the garage'), 'cannot put it back from far away')
H.vehPos[H.spawned[vid].ent] = { x = 12, y = 0, z = 0 }
r = H.call(1, 'whip_jobs:fleet:return', { station = 1, spot = 'garage' })
ok(r == true and not H.spawned[vid], 'put back at the garage')
-- the second space is used while the first is taken; clocking off sends it back
H.vehPos[9999] = { x = 10, y = 0, z = 0 }
r = H.call(1, 'whip_jobs:fleet:take', { station = 1, spot = 'garage', model = 'police3' })
local vid2 = next(H.spawned)
ok(r and H.spawned[vid2].c.x == 20, 'first space blocked: the second is used')
WC:ClockOff(1, lspd.jobId)
ok(next(H.spawned) == nil and H.exports.GetFleetVehicle(101) == nil, 'clock off: the fleet car goes')
H.vehPos[9999] = nil
-- locker
at(1, 4)
r = H.call(1, 'whip_jobs:locker:open', { station = 1, spot = 'locker' })
ok(r == true and H.container.key == 'es_jobs:locker:101' and H.container.d.requirements.charIds[1] == 101 and H.opened.o.skipDistance, 'personal locker: own container, only them')

-- ---------------------------------------------------------------- pay
H.players[1].duty[lspd.jobId] = true
local mine = acctOf(101)
for _ = 1, 14 do ESJ.payTick() end
ok(mine.balance == 0, 'no paycheck before 15 minutes')
ESJ.payTick()
ok(mine.balance == 240 and acctL.balance == 760, 'paid $240 from the LSPD account at 15 minutes')
r = H.call(2, 'whip_jobs:pay:set', { jobId = lspd.jobId, roleId = H.roleByName(lspd, 'Officer').roleId, amount = 900 })
ok(r and r.amount == 900, 'chief sets Officer pay to $900')
r, why = H.call(1, 'whip_jobs:pay:set', { jobId = lspd.jobId, roleId = H.roleByName(lspd, 'Officer').roleId, amount = 5 })
ok(r == false, 'an officer cannot set pay')
r, why = H.call(2, 'whip_jobs:pay:set', { jobId = lspd.jobId, roleId = H.roleByName(lspd, 'Officer').roleId, amount = 999999 })
ok(r == false and why:find('most'), 'over the max refused')
H.notes = {}
for _ = 1, 15 do ESJ.payTick() end
ok(mine.balance == 240 and acctL.balance == 760, 'account short ($760 < $900): nothing paid')
local told, leader = false, false
for _, n in ipairs(H.notes) do if n.src == 1 and n.text:find('could not pay you') then told = true end if n.src == 2 and n.text:find('could not pay') then leader = true end end
ok(told and leader, 'the officer and the chief are told')
local missed = 0 for _, l in pairs(H.T.ledger) do if l.kind == 'pay_missed' then missed = missed + 1 end end
ok(missed == 1, 'the miss is in the ledger')
H.notes = {}
for _ = 1, 15 do ESJ.payTick() end
leader = false for _, n in ipairs(H.notes) do if n.src == 2 then leader = true end end
ok(not leader, 'leaders are not told again within 10 minutes')
H.call(2, 'whip_jobs:pay:set', { jobId = lspd.jobId, roleId = H.roleByName(lspd, 'Officer').roleId, amount = '' })
ok(H.T.pay[H.roleByName(lspd, 'Officer').roleId] == nil, 'empty pay: back to the default')
-- es_mdt income hook
TriggerEvent('es_mdt:server:deptIncome', lspd.jobId, 350, 'ticket', 'Fine #12', 103)
local week = ESJ.payWeek(lspd.jobId)
ok(week.income == 350 and week.paid == 240 and week.missed >= 1, 'week: income from es_mdt, pay out, misses')
r = H.call(2, 'whip_jobs:org:get', { jobId = lspd.jobId })
ok(r and r.account.balance == 760 and #r.ledger >= 3 and r.ledger[1].who, 'chief sees money and ledger')
r = H.call(1, 'whip_jobs:org:get', { jobId = lspd.jobId })
ok(r == false, 'an officer cannot see department money')

-- ---------------------------------------------------------------- businesses
r, why = H.call(3, 'whip_jobs:biz:create', { name = 'Bean Machine', short = 'BEAN' })
ok(r == false and why:find('admin'), 'players cannot start one while playerCreate is off')
Config.Business.playerCreate = true
r = H.call(3, 'whip_jobs:biz:create', { name = 'Bean Machine', short = 'BEAN', color = '#7c4a2d' })
ok(r and r.id == 1 and H.charged[1] == 25000 and acctOf(103).balance == 5000, 'player pays $25,000 and opens it')
local bj = H.jobs[r.jobId]
ok(bj.members[103] and bj.roles[bj.members[103]].level == 100 and #WC:GetJobBankAccounts(bj.jobId) == 1, 'owner holds the top rank; business account made')
r, why = H.call(3, 'whip_jobs:biz:create', { name = 'bean machine', short = 'BM' })
ok(r == false and why:find('already'), 'duplicate name refused')
H.failEnsure = true
local before = acctOf(103).balance
acctOf(103).balance = 30000
r, why = H.call(3, 'whip_jobs:biz:create', { name = 'Taco Shop', short = 'TACO' })
ok(r == false and acctOf(103).balance == 30000, 'WHIP refuses the job: the licence is refunded')
H.failEnsure = false
local list = H.call(3, 'whip_jobs:biz:list')
ok(#list.list == 1 and list.list[1].kind == 'biz', 'owner sees their business (and no departments)')
list = H.call(2, 'whip_jobs:biz:list')
ok(#list.list == 1 and list.list[1].kind == 'dept', 'LSPD chief sees LSPD (to lead) only')
list = H.call(4, 'whip_jobs:biz:list')
ok(#list.list == 3, 'admin sees every department and business')
-- logo upload in parts
local logo = 'data:image/webp;base64,' .. string.rep('A', 20000)
r = H.call(3, 'whip_jobs:biz:logoPart', { id = 1, i = 1, total = 2, part = logo:sub(1, 15000) })
r = H.call(3, 'whip_jobs:biz:logoPart', { id = 1, i = 2, total = 2, part = logo:sub(15001) })
ok(r and r.done and H.T.biz[1].logo == logo and r.logoVer == 1, 'logo saved from two parts')
r, why = H.call(3, 'whip_jobs:biz:logoPart', { id = 1, i = 1, total = 1, part = 'javascript:alert(1)' })
ok(r == false, 'not a picture: refused')
local got = H.call(1, 'whip_jobs:biz:logo', { id = 1, i = 2 })
ok(got.total == 2 and got.part == logo:sub(15001), 'anyone can read the logo back in parts')
-- hire someone standing near
at(3, 100) at(5, 101)
local near = H.call(3, 'whip_jobs:biz:nearby', { id = 1 })
ok(#near == 1 and near[1].source == 5, 'nearby: the deputy standing next to them')
r = H.call(3, 'whip_jobs:biz:hire', { id = 1, target = 5, roleId = H.roleByName(bj, 'Employee').roleId })
ok(r == true and bj.members[105], 'hired')
at(5, 300)
r, why = H.call(3, 'whip_jobs:biz:hire', { id = 1, target = 1, roleId = H.roleByName(bj, 'Employee').roleId })
ok(r == false and why:find('Stand next'), 'cannot hire someone far away')
r, why = H.call(5, 'whip_jobs:biz:fire', { id = 1, charId = 103 })
ok(r == false, 'an employee cannot let anyone go')
r, why = H.call(3, 'whip_jobs:biz:fire', { id = 1, charId = 103 })
ok(r == false and why:find('owner'), 'the owner cannot be let go')
r = H.call(3, 'whip_jobs:biz:rank', { id = 1, roleId = 0, name = 'Barista', level = 25, perms = { canHire = true } })
ok(type(r) == 'number' and bj.roles[r].permissions.canHire, 'new rank with a permission')
local det = H.call(3, 'whip_jobs:org:get', { jobId = bj.jobId })
ok(det.biz.short == 'BEAN' and #det.roster == 2 and det.rights.manage and det.account, 'owner sees roster, rights and money')
det = H.call(5, 'whip_jobs:org:get', { jobId = bj.jobId })
ok(det and not det.account and det.rights.view and not det.rights.manage, 'employee sees it, without money')
-- stations under a business; deleting it with money refused
r = H.call(3, 'whip_jobs:st:save', { name = 'Bean Machine Vinewood', jobs = { bj.jobId }, spots = { spot('duty', 100, { ped = 'a_m_y_business_01' }) } })
ok(r and r.id, 'owner sets up their own station')
WC:BankSystemDeposit(WC:GetJobBankAccounts(bj.jobId)[1].accountId, 50)
r, why = H.call(4, 'whip_jobs:biz:delete', { id = 1 })
ok(r == false and why:find('still holds'), 'cannot close with money in the account')
WC:GetJobBankAccounts(bj.jobId)[1].balance = 0
r = H.call(4, 'whip_jobs:biz:delete', { id = 1 })
ok(r == true and not H.T.biz[1] and not H.jobs[bj.jobId], 'admin closes it')
local s2 = H.T.st[r and 2 or 0]
ok(s2 and #json.decode(s2.jobs) == 0, 'its station drops it (and stays for an admin)')

-- ---------------------------------------------------------------- a department deleted in /departments
H.depts = { H.depts[1] }
TriggerEvent('es_departments:server:changed')
ok(#json.decode(H.T.st[1].jobs) == 1, 'BCSO deleted: Mission Row keeps only LSPD')
H.states.es_mdt = 'stopped'
TriggerEvent('es_departments:server:changed')
ok(#json.decode(H.T.st[1].jobs) == 1, 'es_mdt stopped: stations are not emptied')
H.states.es_mdt = 'started'
-- delete and bring back
r = H.call(2, 'whip_jobs:st:delete', { id = 1 })
ok(r and not H.T.st[1], 'deleted')
local del = H.call(4, 'whip_jobs:st:list').deleted
ok(#del == 1 and del[1].stationId == 1, 'admin sees it under Deleted')
r = H.call(4, 'whip_jobs:st:restore', { historyId = del[1].id })
ok(r and r.id == 1 and H.T.st[1] and #json.decode(H.T.st[1].spots) == 4, 'brought back under its old number with its spots')
-- backup and import
local bk = H.call(4, 'whip_jobs:st:export')
r = H.call(4, 'whip_jobs:st:import', { text = json.encode(bk) })
ok(r and r.count == #bk.stations, 'backup restores')
r, why = H.call(4, 'whip_jobs:st:import', { text = '{"nope":1}' })
ok(r == false, 'not a backup: refused')
r = H.call(2, 'whip_jobs:st:export')
ok(r == false, 'leaders cannot export')
-- teleport
at(2, 0)
r, why = H.call(2, 'whip_jobs:st:teleport', { id = 1, x = 900, y = 900, z = 0 })
ok(r == false, 'a leader cannot teleport anywhere')
r = H.call(2, 'whip_jobs:st:teleport', { id = 1, x = 2, y = 0, z = 0 })
ok(r == true and H.peds[2].x == 2, 'a leader goes to their own spot')

-- ---------------------------------------------------------------- uniforms (phase 2)
local L = { station = 1, spot = 'locker' }
local function look(c11, c4, p1) return { model = 'mp_m_freemode_01', components = { ['11'] = { drawable = c11, texture = 0 }, ['4'] = { drawable = c4, texture = 0 } }, props = { ['1'] = { drawable = p1, texture = 0 } } } end
H.looks[1], H.looks[2], H.looks[3] = look(5, 1, 3), look(6, 2, 4), look(7, 3, -1)
at(2, 4) at(1, 4) at(3, 4)
local function with(t, x) local o = {} for k, v in pairs(t) do o[k] = v end for k, v in pairs(x) do o[k] = v end return o end
r, why = H.call(1, 'whip_jobs:uni:save', with(L, { jobId = lspd.jobId, name = 'Patrol', look = look(55, 35, 7) }))
ok(r == false and why:find('leaders'), 'an officer cannot make a uniform')
local patrol = { model = 'mp_m_freemode_01', components = { ['11'] = { drawable = 55, texture = 1 }, ['4'] = { drawable = 35, texture = 0 } }, props = { ['0'] = { drawable = 46, texture = 0 }, ['1'] = { drawable = 7, texture = 0 } } }
r = H.call(2, 'whip_jobs:uni:save', with(L, { jobId = lspd.jobId, name = 'Patrol', minLevel = 30, look = patrol, skip = { 'p1' } }))
ok(r and r.id == 1 and H.T.uni[1].body == 'male', 'the chief saves a male uniform from the editor')
local fem = { model = 'mp_f_freemode_01', components = { ['11'] = { drawable = 48, texture = 0 } }, props = {} }
r = H.call(2, 'whip_jobs:uni:save', with(L, { jobId = lspd.jobId, name = 'Patrol F', look = fem }))
ok(r and r.id == 2, 'and a female one')
r = H.call(2, 'whip_jobs:uni:save', with(L, { jobId = lspd.jobId, name = 'Sgt', minLevel = 60, look = patrol }))
H.players[1].duty[lspd.jobId] = nil
local ls = H.call(1, 'whip_jobs:uni:list', L)
ok(ls and ls.body == 'male' and #ls.orgs == 1 and #ls.orgs[1].uniforms == 2 and not ls.orgs[1].uniforms[1].allowed, 'officer sees the 2 male uniforms, off duty: not allowed')
r, why = H.call(1, 'whip_jobs:uni:wear', with(L, { id = 1 }))
ok(r == false and why == 'Clock on first', 'off duty: cannot wear it')
H.players[1].duty[lspd.jobId] = true
r, why = H.call(1, 'whip_jobs:uni:wear', with(L, { id = 3 }))
ok(r == false and why:find('rank'), 'the sergeant uniform is above an officer')
H.client = {}
r = H.call(1, 'whip_jobs:uni:wear', with(L, { id = 1 }))
local lk = H.looks[1]
ok(r and lk.components['11'].drawable == 55 and lk.components['11'].texture == 1 and lk.props['0'].drawable == 46, 'wearing it: top, legs and hat are the uniform')
ok(lk.props['1'].drawable == 3, 'their own glasses stay (left as the wearer\'s own)')
ok(H.T.ward[101] and json.decode(H.T.ward[101].own).c['11'][1] == 5, 'their own clothes are put away')
ok(H.client[#H.client].n == 'whip_jobs:client:dress' and H.client[#H.client].to == 1, 'dressed on their ped now')
r = H.call(1, 'whip_jobs:uni:wear', with(L, { id = 1 }))
ok(json.decode(H.T.ward[101].own).c['11'][1] == 5, 'a second change keeps the first own clothes')
r, why = H.call(3, 'whip_jobs:uni:list', L)
ok(r == false, 'a civilian cannot use the police lockers')
r, why = H.call(1, 'whip_jobs:uni:delete', with(L, { id = 1 }))
ok(r == false, 'an officer cannot delete a uniform')
WC:ClockOff(1, lspd.jobId)
lk = H.looks[1]
ok(lk.components['11'].drawable == 5 and lk.components['4'].drawable == 1 and lk.props['0'].drawable == -1 and lk.props['1'].drawable == 3, 'clocked off: own clothes back (no hat)')
ok(H.T.ward[101] == nil and ESJ.wearing(101) == nil, 'wardrobe row cleared')
r = H.call(2, 'whip_jobs:uni:delete', with(L, { id = 3 }))
ok(r == true and H.T.uni[3] == nil, 'the chief deletes one')
r = H.call(2, 'whip_jobs:uni:save', with(L, { jobId = lspd.jobId, id = 1, name = 'Patrol Class A', minLevel = 30, skip = { 'p0' } }))
ok(r and H.T.uni[1].name == 'Patrol Class A' and not json.decode(H.T.uni[1].parts).p['0'], 'renamed, the hat now left as the wearer\'s own')

-- ---------------------------------------------------------------- police (phase 2)
H.players[1].duty[lspd.jobId] = true
at(1, 500) at(3, 501)
r, why = H.call(3, 'whip_jobs:pol:breath', { target = 1 })
ok(r == false and why:find('police'), 'a civilian cannot breathalyze')
r, why = H.call(1, 'whip_jobs:pol:breath', { target = 3 })
ok(r == false and why:find('breathalyzer'), 'needs a breathalyzer')
WC:AddItem(1, 'whip_jobs_breathalyzer', 1)
H.stats[3] = { drunk = 30 }
r = H.call(1, 'whip_jobs:pol:breath', { target = 3 })
ok(r and math.abs(r.bac - 0.12) < 1e-9 and r.over, 'blew 0.120: over the limit')
H.barResult = false
r, why = H.call(1, 'whip_jobs:pol:breath', { target = 3 })
ok(r == false, 'bar stopped: no reading')
H.barResult = nil
at(3, 520)
r, why = H.call(1, 'whip_jobs:pol:breath', { target = 3 })
ok(r == false and why == 'Get closer', 'too far away')
at(3, 501)
WC:AddItem(1, 'whip_jobs_drug_test', 2)
H.effects[3] = { weed_high = { magnitude = 1 }, speed_boost = {} }
r = H.call(1, 'whip_jobs:pol:drug', { target = 3 })
ok(r and #r.found == 1 and r.found[1] == 'Cannabis' and H.inv[1].whip_jobs_drug_test == 1, 'swab: positive for cannabis, one kit used')
H.effects[3] = {}
r = H.call(1, 'whip_jobs:pol:drug', { target = 3 })
ok(r and #r.found == 0, 'clean: negative')
H.vehPos[600] = { x = 502, y = 0, z = 0 } H.netEnt[600] = 600
r, why = H.call(1, 'whip_jobs:pol:seat', { target = 3, netId = 600, seat = 1 })
ok(r == false and why:find('Cuff'), 'not cuffed: cannot be put in a car')
Player(3).state.esCuffed = 'hard:cuffs'
r, why = H.call(1, 'whip_jobs:pol:seat', { target = 3, netId = 600, seat = -1 })
ok(r == false, 'not the driver seat')
H.seats[600] = { [1] = 99 }
r, why = H.call(1, 'whip_jobs:pol:seat', { target = 3, netId = 600, seat = 1 })
ok(r == false and why:find('taken'), 'a taken seat')
H.client = {}
r = H.call(1, 'whip_jobs:pol:seat', { target = 3, netId = 600, seat = 2 })
ok(r == true and H.client[1].n == 'whip_jobs:client:seat' and H.client[1].to == 3 and H.client[1].args[2] == 2, 'cuffed: seated in the back')
r, why = H.call(5, 'whip_jobs:pol:seat', { target = 3, netId = 600, seat = 2 })
ok(r == false, 'BCSO off duty cannot')
H.inVeh[3] = 600
r = H.call(1, 'whip_jobs:pol:out', { target = 3 })
ok(r == true and H.client[#H.client].n == 'whip_jobs:client:out', 'taken out')
Player(3).state.esCuffed = nil H.inVeh[3] = nil
r, why = H.call(1, 'whip_jobs:pol:spike', { x = 500, y = 2, z = 0, h = 90 })
ok(r == false and why:find('no spike'), 'no strip to lay')
WC:AddItem(1, 'whip_jobs_spike_strip', 3)
local s1 = H.call(1, 'whip_jobs:pol:spike', { x = 500, y = 2, z = 0, h = 90 })
local s2 = H.call(1, 'whip_jobs:pol:spike', { x = 500, y = 4, z = 0, h = 90 })
r, why = H.call(1, 'whip_jobs:pol:spike', { x = 500, y = 5, z = 0, h = 90 })
ok(s1 and s2 and r == false and why:find('2 down'), 'two strips at most per officer')
ok(H.inv[1].whip_jobs_spike_strip == 1 and H.client[#H.client].n == 'whip_jobs:client:spikes' and #H.client[#H.client].args[1] == 2, 'laid two, everyone told')
r, why = H.call(1, 'whip_jobs:pol:spike', { x = 560, y = 0, z = 0, h = 0 })
ok(r == false and why:find('closer'), 'cannot lay one far away')
r = H.call(1, 'whip_jobs:pol:unspike', { id = s1.id })
ok(r == true and H.inv[1].whip_jobs_spike_strip == 2 and #H.client[#H.client].args[1] == 1, 'picked one up')
local okU, whyU = H.use.whip_jobs_spike_strip(3)
ok(okU == false and whyU:find('police'), 'a civilian cannot use a spike strip')
ok(H.items.whip_jobs_breathalyzer and H.items.whip_jobs_drug_test and H.items.whip_jobs_spike_strip.usable, 'items registered')

-- ---------------------------------------------------------------- impound clerk (phase 2)
at(4, 800)
r, why = H.call(4, 'whip_jobs:st:save', { name = 'Impound Lot', jobs = {}, spots = { spot('impound', 800, { spawns = { { x = 810, y = 0, z = 0, h = 0 } } }) } })
ok(r and r.id, 'admin sets up an impound lot with one parking space')
local IMP = { station = r.id, spot = 'impound' }
H.veh[900] = { state = 'garaged', garage = 'lot_a', model = 'sultan', displayName = 'Sultan' }
H.impounds = { { id = 7, vehicleId = 900, ownerCharId = 103, plate = 'ABC123', vehicleLabel = 'Sultan', status = 'held', held = false, lot = 'lot_a', lotLabel = 'Lot A',
  owe = { fee = 500, storage = 100, days = 1, total = 600 }, reason = 'Parking', dept = 'LSPD' } }
at(3, 801)
r = H.call(3, 'whip_jobs:spot:open', IMP)
ok(r and r.type == 'impound' and #r.cars == 1 and r.cars[1].canPay and not r.cars[1].canTake and r.cars[1].owe == 600, 'a civilian sees their impounded car and what is owed')
at(1, 801)
r = H.call(1, 'whip_jobs:spot:open', IMP)
ok(r and #r.cars == 0, 'someone else sees none of it')
r, why = H.call(3, 'whip_jobs:imp:take', with(IMP, { id = 7 }))
ok(r == false and why:find('Pay'), 'cannot take it before paying')
r = H.call(3, 'whip_jobs:imp:pay', with(IMP, { id = 7, method = 'bank' }))
ok(r and r.amount == 600 and H.impounds[1].status == 'released', 'paid at the counter')
at(1, 900)
r = H.call(3, 'whip_jobs:imp:take', with(IMP, { id = 7 }))
ok(r and r.plate == 'ABC123' and H.veh[900].state == 'out' and H.veh[900].spawnedAt.x == 810, 'brought out at the parking space')
r = H.call(3, 'whip_jobs:spot:open', IMP)
ok(r and #r.cars == 0, 'gone from the list once out')
at(3, 1500)
r, why = H.call(3, 'whip_jobs:imp:pay', with(IMP, { id = 7, method = 'bank' }))
ok(r == false and why:find('Go to'), 'must stand at the clerk')
print(H.fails == 0 and '== whip_jobs server: all passed' or ('== whip_jobs server: ' .. H.fails .. ' FAILED'))
