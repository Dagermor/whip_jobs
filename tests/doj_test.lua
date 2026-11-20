-- whip_jobs 0.4.0: the DOJ's spot types, their default peds, and es_mdt's old courthouse desk moved into a station once
package.path = arg[0]:gsub('[^/]+$', '') .. '?.lua;' .. package.path
local H = require('harness')
local ok = H.ok
local doj = H.addJob('doj', 'DOJ', { { name = 'Clerk', level = 20 }, { name = 'Chief Justice', level = 100, permissions = { canManage = true } } })
local lspd = H.addJob('police', 'LSPD', { { name = 'Officer', level = 30 } })
H.depts = { { id = 1, jobId = lspd.jobId, short = 'LSPD', name = 'Los Santos Police', type = 'police' },
            { id = 3, jobId = doj.jobId, short = 'DOJ', name = 'San Andreas Department of Justice', type = 'doj' } }
H.players[1] = { charId = 201, name = 'Judge Judy', duty = {} }
H.players[2] = { charId = 202, name = 'Admin', duty = {} }
doj.members[201] = H.roleByName(doj, 'Chief Justice').roleId
H.aces[2] = { ['whip_jobs.admin'] = true }
for s = 1, 2 do H.peds[s] = { x = 0, y = 0, z = 0 } end
H.ext.es_mdt.GetCourthouse = function() return { label = 'Courthouse', blip = { sprite = 419, color = 5, scale = 0.8 },
  desks = { { label = 'Court clerk', x = -544.85, y = -204.26, z = 38.22, h = 0 } } } end

H.load()
ok(not H.problem, 'started')
local st
for _, s in pairs(ESJ.Stations) do st = s end
ok(st and st.name == 'Courthouse' and st.jobs[1] == doj.jobId and #st.jobs == 1, 'migrated: a Courthouse station of the DOJ')
ok(st and #st.spots == 1 and st.spots[1].type == 'court_clerk' and math.abs(st.spots[1].z - 37.24) < 0.01 and st.spots[1].ped == 'a_f_y_business_01',
  'migrated: the clerk window at the old desk (feet height) with the clerk ped')
ok(st and st.blip.sprite == 419 and st.blip.color == 5 and st.blip.show == 'everyone', 'migrated: the old courthouse blip')
ok(H.kvp['whip_jobs:doj_courthouse_migrated'] == '1', 'migration remembered')
local n = 0 for _ in pairs(ESJ.Stations) do n = n + 1 end
ESJ.migrateCourthouse()
local n2 = 0 for _ in pairs(ESJ.Stations) do n2 = n2 + 1 end
ok(n == 1 and n2 == 1, 'migration runs once')
-- a fresh server that already has a DOJ spot: nothing is made
H.kvp = {}
ESJ.migrateCourthouse()
n2 = 0 for _ in pairs(ESJ.Stations) do n2 = n2 + 1 end
ok(n2 == 1 and H.kvp['whip_jobs:doj_courthouse_migrated'] == '1', 'a DOJ spot already placed: no second courthouse')

-- the editor list: DOJ types are placeable now, with their own peds and the starter sets
local r = H.call(1, 'whip_jobs:st:list')
ok(r and r.phase == 4, 'phase 4: DOJ spots placeable')
local keys = {} for _, t in ipairs(r.types) do if t.doj then keys[#keys + 1] = t.key end end
ok(table.concat(keys, ',') == 'court_clerk,courtroom,chambers,da_office,pd_office', 'DOJ spot types: ' .. table.concat(keys, ','))
ok(r.typePeds.court_clerk == 'a_f_y_business_01' and r.typePeds.courtroom == 's_m_m_highsec_01' and r.typePeds.chambers == 'a_m_m_business_01'
  and r.typePeds.da_office == 'a_f_y_business_02' and r.typePeds.pd_office == 'a_m_y_business_02', 'each DOJ spot has its default ped')
ok(#r.starter.doj == 7 and r.starter.doj[2] == 'court_clerk', 'starter set for a DOJ department')
local dojOrg
for _, o in ipairs(r.orgs) do if o.type == 'doj' then dojOrg = o end end
ok(dojOrg and dojOrg.mine, 'the Chief Justice leads the DOJ (may edit its stations)')

-- the Chief Justice adds the courtroom, chambers, DA and PD offices; the station is shared with LSPD by an admin
local spots = { st.spots[1] }
for i, k in ipairs({ 'courtroom', 'chambers', 'da_office', 'pd_office' }) do spots[#spots + 1] = { id = k, type = k, label = k, x = -540 + i, y = -200, z = 37.2, h = 90, ped = r.typePeds[k] } end
local res, why = H.call(1, 'whip_jobs:st:save', { id = st.id, rev = st.rev, name = 'Courthouse', jobs = { doj.jobId }, blip = st.blip, spots = spots })
ok(res and #res.spots == 5, 'judge saves the full courthouse: ' .. tostring(why))
res, why = H.call(2, 'whip_jobs:st:save', { id = st.id, rev = res and res.rev, name = 'Courthouse', jobs = { doj.jobId, lspd.jobId }, blip = st.blip, spots = spots })
ok(res and #ESJ.Stations[st.id].jobs == 2, 'shared stations allowed (DOJ + LSPD): ' .. tostring(why))
-- an old 'court' placeholder spot reads as the clerk window
res, why = H.call(2, 'whip_jobs:st:save', { name = 'Annex', jobs = { doj.jobId }, spots = { { type = 'court', label = 'Old', x = 1, y = 1, z = 1 } } })
ok(res and res.spots[1].type == 'court_clerk', "the old 'court' type saves as the clerk window: " .. tostring(why))
-- a public DOJ spot works with no department; a staff-only one does not
res, why = H.call(2, 'whip_jobs:st:save', { name = 'Kiosk', jobs = {}, spots = { { type = 'court_clerk', label = 'Kiosk', x = 2, y = 2, z = 2 } } })
ok(res, 'admin: a clerk window station needs no department: ' .. tostring(why))
res, why = H.call(2, 'whip_jobs:st:save', { name = 'Bad', jobs = {}, spots = { { type = 'chambers', label = 'X', x = 2, y = 2, z = 2 } } })
ok(res == false, "judge's chambers need a department: " .. tostring(why))
ok(ESJ.hasSpotType('court_clerk') and not ESJ.hasSpotType('hospital'), 'HasSpotType')

-- no DOJ department yet: wait, do not mark done
H.kvp = {} ESJ.Stations = {} H.depts = { H.depts[1] }
TriggerEvent('es_departments:server:changed')
ESJ.migrateCourthouse()
ok(next(ESJ.Stations) == nil and H.kvp['whip_jobs:doj_courthouse_migrated'] == nil, 'no DOJ department: nothing made, tried again later')
print(H.fails == 0 and '== whip_jobs doj: all passed' or ('== whip_jobs doj: ' .. H.fails .. ' FAILED'))
