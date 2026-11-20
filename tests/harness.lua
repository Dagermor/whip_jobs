-- whip_jobs sims: load the resource's server files in manifest order against an in-memory whip_core, es_mdt and MySQL.
local H = {}
local ROOT = arg[1]
H.fails = 0
function H.ok(c, m) if c then print('PASS ' .. m) else H.fails = H.fails + 1 print('FAIL ' .. m) end end

-- ---------------------------------------------------------------- json (enough for our tables)
local function enc(v)
  local t = type(v)
  if t == 'nil' then return 'null' elseif t == 'boolean' then return tostring(v)
  elseif t == 'number' then return (v == math.floor(v) and string.format('%d', v)) or string.format('%.14g', v)
  elseif t == 'string' then return '"' .. v:gsub('[%c"\\]', function(c) return string.format('\\u%04x', c:byte()) end) .. '"'
  elseif t == 'table' then
    if #v > 0 or next(v) == nil then local o = {} for i = 1, #v do o[i] = enc(v[i]) end return '[' .. table.concat(o, ',') .. ']' end
    local o = {} for k, x in pairs(v) do o[#o + 1] = enc(tostring(k)) .. ':' .. enc(x) end table.sort(o) return '{' .. table.concat(o, ',') .. '}'
  end
  error('cannot encode ' .. t)
end
local function dec(s)
  local i = 1
  local function ws() i = s:find('[^%s]', i) or #s + 1 end
  local val
  local function str()
    local out, j = {}, i + 1
    while true do
      local c = s:sub(j, j)
      if c == '"' then i = j + 1 return table.concat(out) end
      if c == '\\' then
        local n = s:sub(j + 1, j + 1)
        if n == 'u' then out[#out + 1] = string.char(tonumber(s:sub(j + 2, j + 5), 16) % 256) j = j + 6
        else out[#out + 1] = ({ n = '\n', t = '\t', r = '\r', b = '\b', f = '\f' })[n] or n j = j + 2 end
      else out[#out + 1] = c j = j + 1 end
      if j > #s then error('bad string') end
    end
  end
  function val()
    ws()
    local c = s:sub(i, i)
    if c == '{' then
      local o = {} i = i + 1 ws()
      if s:sub(i, i) == '}' then i = i + 1 return o end
      while true do ws() local k = str() ws() i = i + 1 o[k] = val() ws() local d = s:sub(i, i) i = i + 1 if d == '}' then return o end end
    elseif c == '[' then
      local o = {} i = i + 1 ws()
      if s:sub(i, i) == ']' then i = i + 1 return o end
      while true do o[#o + 1] = val() ws() local d = s:sub(i, i) i = i + 1 if d == ']' then return o end end
    elseif c == '"' then return str()
    elseif s:sub(i, i + 3) == 'true' then i = i + 4 return true
    elseif s:sub(i, i + 4) == 'false' then i = i + 5 return false
    elseif s:sub(i, i + 3) == 'null' then i = i + 4 return nil
    else local n = s:match('^-?[%d%.eE+-]+', i) i = i + #n return tonumber(n) end
  end
  local ok, r = pcall(val)
  if not ok then error(r) end
  return r
end
json = { encode = enc, decode = dec }

-- ---------------------------------------------------------------- FiveM bits
local vmt = {}
vmt.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmt) end
vmt.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vmt) end
H.handlers = {}
function AddEventHandler(n, fn) H.handlers[n] = H.handlers[n] or {} table.insert(H.handlers[n], fn) end
function TriggerEvent(n, ...) for _, fn in ipairs(H.handlers[n] or {}) do fn(...) end end
H.client = {}
function TriggerClientEvent(n, to, ...) H.client[#H.client + 1] = { n = n, to = to, args = { ... } } end
function GetInvokingResource() return 'whip_core' end
function GetCurrentResourceName() return 'whip_jobs' end
H.states = { es_mdt = 'started', whip_core = 'started' }
function GetResourceState(n) return H.states[n] or 'missing' end
H.kvp = {}
function GetResourceKvpString(k) return H.kvp[k] end
function SetResourceKvp(k, v) H.kvp[k] = v end
H.now = 100000
function GetGameTimer() return H.now end
-- threads are coroutines: they run until their first Wait (a forever loop stays parked there)
function CreateThread(f) local co = coroutine.create(f) local ok, e = coroutine.resume(co) if not ok then error(e) end end
function SetTimeout(_, f) f() end
function Wait() if coroutine.isyieldable() then coroutine.yield() end end
function IsPlayerAceAllowed(src, ace) return H.aces[src] and H.aces[src][ace] or false end
H.aces = {}
H.peds = {}     -- [src] = { x, y, z }
function GetPlayerPed(src) return H.peds[src] and src or 0 end
function GetEntityCoords(e) local p = H.peds[e] or H.vehPos[e] return vector3(p.x, p.y, p.z) end
function SetEntityCoords(e, x, y, z) H.peds[e] = { x = x, y = y, z = z } end
function SetEntityHeading() end
H.vehPos = {}
function GetAllVehicles() local o = {} for e in pairs(H.vehPos) do o[#o + 1] = e end return o end
function DoesEntityExist(e) return H.vehPos[e] ~= nil end
function GetPlayers() local o = {} for s in pairs(H.peds) do o[#o + 1] = tostring(s) end return o end
H.exports = {}
exports = setmetatable({}, {
  __index = function(_, res) return setmetatable({}, { __index = function(_, k)
    local f = (H.ext[res] or {})[k]
    if not f then error('No such export ' .. k .. ' in ' .. res, 2) end
    return function(self, ...) return f(self, ...) end end }) end,
  __call = function(_, name, fn) H.exports[name] = fn end,
})
H.ext = {}
H.pstate = {}
local sbm = { __index = { set = function(self, k, v) rawset(self, k, v) end } }
function Player(src) H.pstate[src] = H.pstate[src] or setmetatable({}, sbm) return { state = H.pstate[src] } end
H.inVeh = {}   -- [src] = vehicle entity
function GetVehiclePedIsIn(ped) return H.inVeh[ped] or 0 end
H.netEnt = {}
function NetworkGetEntityFromNetworkId(n) return H.netEnt[n] or 0 end
function NetworkGetNetworkIdFromEntity(e) return e end
function GetEntityType(e) if H.vehPos[e] then return 2 end if H.peds[e] then return 1 end return 0 end
H.seats = {}
function GetPedInVehicleSeat(v, s) return (H.seats[v] or {})[s] or 0 end
function joaat(s) return #s end
H.objs, H.nextObj = {}, 7000
function CreateObjectNoOffset(m, x, y, z) H.nextObj = H.nextObj + 1 H.objs[H.nextObj] = { m = m, x = x, y = y, z = z } H.vehPos[H.nextObj] = { x = x, y = y, z = z } return H.nextObj end
function FreezeEntityPosition() end
function DeleteEntity(e) H.objs[e] = nil H.vehPos[e] = nil end
function GetPlayerRoutingBucket() return 0 end

-- ---------------------------------------------------------------- whip_core
H.jobs = {}          -- [jobId] = { jobId, key, name, roles = { roleId -> role }, owner, members = { [charId] = roleId } }
H.players = {}       -- [src] = { charId, name, duty = { [jobId] = true } }
H.accounts = {}      -- [id] = { accountId, balance, jobId?, charId?, frozen }
H.log = {}
local nextJob, nextRole, nextAcct, nextVeh = 10, 100, 50, 900
local function cidOf(who)
  if type(who) == 'table' then return who.charId end
  return H.players[who] and H.players[who].charId
end
local function srcOf(cid) for s, p in pairs(H.players) do if p.charId == cid then return s end end end
local function jobOf(j) if type(j) == 'number' then return H.jobs[j] end for _, x in pairs(H.jobs) do if x.key == j then return x end end end
function H.addJob(key, name, roles)
  nextJob = nextJob + 1
  local j = { jobId = nextJob, key = key, name = name, roles = {}, members = {} }
  for _, r in ipairs(roles or {}) do nextRole = nextRole + 1 j.roles[nextRole] = { roleId = nextRole, name = r.name, level = r.level, permissions = r.permissions or {} } end
  H.jobs[j.jobId] = j
  return j
end
function H.roleByName(j, n) for _, r in pairs(j.roles) do if r.name == n then return r end end end
function H.addAccount(t)
  nextAcct = nextAcct + 1
  t.accountId = nextAcct t.accountNumber = 'WB-' .. nextAcct t.balance = t.balance or 0
  H.accounts[nextAcct] = t
  return t
end
H.spawned = {}
local WC = {}
function WC:GetPlayerRole(who, job)
  local j, cid = jobOf(job), cidOf(who)
  local rid = j and cid and j.members[cid]
  return rid and j.roles[rid] or nil
end
function WC:IsPlayerClockedOn(who, job) local p = H.players[who] local j = jobOf(job) return p and j and p.duty[j.jobId] == true or false end
function WC:HasJobPermission(who, job, perm) local r = WC:GetPlayerRole(who, job) return r ~= nil and (r.permissions[perm] == true or r.level >= 100) end
function WC:GetPlayerJobs(who)
  local cid, out = cidOf(who), {}
  local p = H.players[who]
  for id, j in pairs(H.jobs) do
    local rid = j.members[cid]
    if rid then out[id] = { jobId = id, key = j.key, name = j.name, roleId = rid, roleName = j.roles[rid].name, roleLevel = j.roles[rid].level,
      clockedOn = p and p.duty[id] == true, permissions = j.roles[rid].permissions } end
  end
  return out
end
function WC:GetJobRoles(job) local j = jobOf(job) if not j then return false end local o = {} for _, r in pairs(j.roles) do o[#o + 1] = r end table.sort(o, function(a, b) return a.roleId < b.roleId end) return o end
function WC:GetJob(job) return jobOf(job) end
function WC:GetJobEmployees(job)
  local j = jobOf(job) if not j then return false end
  local o = {} for cid, rid in pairs(j.members) do o[cid] = { charId = cid, roleId = rid, roleName = j.roles[rid].name, roleLevel = j.roles[rid].level } end return o
end
function WC:GetJobBankAccounts(job) local j = jobOf(job) local o = {} for _, a in pairs(H.accounts) do if j and a.jobId == j.jobId then o[#o + 1] = a end end return o end
function WC:GetDefaultBankAccount(who) local cid = cidOf(who) for _, a in pairs(H.accounts) do if a.charId == cid and a.default then return a end end end
function WC:BankSystemTransfer(from, to, amount, o)
  local a, b = H.accounts[from], H.accounts[to]
  if not a or not b then return false, 'no account' end
  if a.balance < amount then return false, 'Insufficient funds' end
  a.balance = a.balance - amount b.balance = b.balance + amount
  H.log[#H.log + 1] = { 'transfer', from, to, amount, o and o.reason }
  return true
end
function WC:BankSystemDeposit(id, amount) H.accounts[id].balance = H.accounts[id].balance + amount return true end
function WC:GetCharId(src) return H.players[src] and H.players[src].charId end
function WC:GetPlayers() local o = {} for s, p in pairs(H.players) do o[s] = { charId = p.charId } end return o end
function WC:GetPlayerFullName(src) return H.players[src] and H.players[src].name end
function WC:GetCharacterNames(ids) local o = {} for _, c in ipairs(ids) do local s = srcOf(c) o[c] = s and H.players[s].name or ('Char ' .. c) end return o end
H.notes = {}
function WC:NotifyPlayer(src, text, kind) H.notes[#H.notes + 1] = { src = src, text = text, kind = kind } return true end
function WC:HasDevTools() return false end
function WC:LogActivity() return true end
function WC:GetItemDefs() return { handcuffs = { name = 'Handcuffs' }, radio = { name = 'Radio' }, weapon_stungun = { name = 'Taser' } } end
function WC:GetItemDef(k) return WC:GetItemDefs()[k] end
H.inv = {}   -- [src] = { item = n }
function WC:GetItemCount(src, item) return (H.inv[src] or {})[item] or 0 end
function WC:CanFitItem(src, item, n) return (H.full ~= src), 'No room' end
function WC:AddItem(src, item, n) H.inv[src] = H.inv[src] or {} H.inv[src][item] = (H.inv[src][item] or 0) + n return 'inventory' end
function WC:RemoveItem(src, item, n) H.inv[src][item] = H.inv[src][item] - n return true end
function WC:ClockOn(src, job) local j = jobOf(job) if not j.members[cidOf(src)] then return false, 'They do not work there' end H.players[src].duty[j.jobId] = true return true end
function WC:ClockOff(src, job) local j = jobOf(job) H.players[src].duty[j.jobId] = nil
  TriggerEvent('whip_core:job:clockedOff', { jobId = j.jobId, key = j.key, charId = cidOf(src), source = src }) return true end
function WC:GetVehicleCatalog() return { police3 = { displayName = 'Police Cruiser', class = 'Emergency' } } end
function WC:SpawnTempVehicle(model, c, o)
  nextVeh = nextVeh + 1
  H.spawned[nextVeh] = { model = model, c = c, o = o }
  H.vehPos[nextVeh + 5000] = { x = c.x, y = c.y, z = c.z }
  H.spawned[nextVeh].ent = nextVeh + 5000
  return nextVeh
end
function WC:GetVehiclePosition(id) local s = H.spawned[id] return s and H.vehPos[s.ent] end
function WC:DespawnVehicle(id) local s = H.spawned[id] if s then H.vehPos[s.ent] = nil H.spawned[id] = nil end TriggerEvent('whip_core:vehicle:released', { vehicleId = id, reason = 'despawned', temp = true }) return true end
H.charged = {}
function WC:ChargePlayer(src, amount, o) local a = WC:GetDefaultBankAccount(src) if not a or a.balance < amount then return false, 'Not enough money' end a.balance = a.balance - amount H.charged[#H.charged + 1] = amount return { id = #H.charged, amount = amount, acct = a.accountId } end
function WC:RefundPlayer(r) H.accounts[r.acct].balance = H.accounts[r.acct].balance + r.amount H.refunded = (H.refunded or 0) + r.amount return true end
function WC:EnsureJob(key, def)
  if H.failEnsure then return false, 'nope' end
  local j = H.addJob(key, def.name, def.roles)
  local top for _, r in pairs(j.roles) do if not top or r.level > top.level then top = r end end
  j.members[def.owner.charId] = top.roleId j.owner = def.owner.charId
  return { jobId = j.jobId, key = key }
end
function WC:UpdateJob(job, p) local j = jobOf(job) if p.name then j.name = p.name end if p.owner then j.owner = p.owner.charId end return true end
function WC:DeleteJob(job) H.jobs[jobOf(job).jobId] = nil return true end
function WC:CreateBankAccount(owner, label, o) return H.addAccount({ jobId = o.job, label = label }) end
function WC:CreateJobRole(job, d, o) local j = jobOf(job) nextRole = nextRole + 1 j.roles[nextRole] = { roleId = nextRole, name = d.name, level = d.level, permissions = d.permissions } return j.roles[nextRole] end
function WC:UpdateJobRole(job, rid, p) local r = jobOf(job).roles[rid] for k, v in pairs(p) do r[k] = v end return true end
function WC:DeleteJobRole(job, rid) jobOf(job).roles[rid] = nil return true end
function WC:GetPlayersInRange(c, r) local o = {} for s, p in pairs(H.peds) do if #(vector3(p.x, p.y, p.z) - c) <= r then o[#o + 1] = s end end return o end
function WC:HirePlayer(t, job, rid) jobOf(job).members[cidOf(t)] = rid or H.lowRole(jobOf(job)) return true end
function H.lowRole(j) local low for _, r in pairs(j.roles) do if not low or r.level < low.level then low = r end end return low.roleId end
function WC:SetPlayerRole(who, job, rid) jobOf(job).members[cidOf(who)] = rid return true end
function WC:FirePlayer(who, job) jobOf(job).members[cidOf(who)] = nil return true end
function WC:EnsureContainer(key, d) H.container = { key = key, d = d } return { containerId = 77 } end
function WC:OpenStore(src, addr, o) H.opened = { src = src, addr = addr, o = o } return true end
function WC:EnsureTable() return true end
-- appearance (uniforms)
H.looks = {}   -- [src] = look
function WC:GetPlayerMetadata(src, key) if key == 'appearance' then return H.looks[src] end end
local function deepc(v) return json.decode(json.encode(v)) end
function WC:SanitizeAppearance(look) if type(look) ~= 'table' or not look.model then return false, 'bad' end return true, deepc(look) end
function WC:SetPlayerAppearance(src, look, o)
  local from = H.looks[src]
  if not from then return false, 'That character has no look saved yet' end
  if look.model ~= from.model then return false, 'That look is another body' end
  local out = deepc(from)
  out.components, out.props = deepc(look.components or {}), deepc(look.props or {})
  H.looks[src] = out
  H.setLooks = (H.setLooks or 0) + 1
  return true, out
end
-- items, stats, effects, bars
H.items = {}
function WC:RegisterItem(k, d) H.items[k] = d return true end
H.use = {}
function WC:RegisterUseHandler(k, f) H.use[k] = f return true end
function WC:HasItem(src, item, n) return ((H.inv[src] or {})[item] or 0) >= (n or 1) end
H.stats, H.effects = {}, {}
function WC:GetStat(src, n) return (H.stats[src] or {})[n] end
function WC:GetEffects(src) return H.effects[src] or {} end
H.deadSet = {}
function WC:IsPlayerDead(src) return H.dead == src or H.deadSet[src] == true end
H.revived, H.holds = {}, {}
function WC:RevivePlayer(src, why) if not WC:IsPlayerDead(src) then return false, 'not down' end H.deadSet[src] = nil if H.dead == src then H.dead = nil end H.revived[#H.revived + 1] = { src = src, why = why }
  TriggerEvent('whip_core:player:revived', { source = src, charId = WC:GetCharId(src), how = 'revived', reason = why }) return true end
function WC:HoldRespawn(src, key, label) H.holds[src] = label return true end
function WC:ReleaseRespawn(src, key) local had = H.holds[src] ~= nil H.holds[src] = nil return had end
H.health = {}
function GetEntityHealth(e) return H.health[e] or 200 end
function WC:Progress(src, o) H.bars = (H.bars or 0) + 1 return H.barResult == nil and true or H.barResult end
-- owned vehicles (impound)
H.veh = {}
function WC:GetVehicle(id) return H.veh[id] end
function WC:GetVehicleImage(m) return 'https://img/' .. tostring(m) end
function WC:RetrieveVehicle(id, g) local v = H.veh[id] if not v or v.state ~= 'garaged' then return false, 'Vehicle is not garaged' end if v.garage ~= g then return false, 'Wrong garage' end v.state = 'out' return true end
function WC:SpawnVehicle(id, c) local v = H.veh[id] v.spawnedAt = c return 4242 end
H.WC = WC
H.ext.whip_core = WC
H.cbs = {}
Whip = {
  register = function(fn) H.registerFn = fn end, command = function(n, o, fn) H.cmds = H.cmds or {} H.cmds[n] = fn end,
  sayStarted = function() end, startProblem = function(...) print('startProblem', ...) H.problem = true end, ready = function() return true end,
  core = setmetatable({}, { __index = function(_, k)
    if k == 'SecureCallback' then return function(_, name, o, fn) H.cbs[name] = fn end end
    if k == 'SecureEvent' then return function(_, name, o, fn) H.sevents = H.sevents or {} H.sevents[name] = { o = o, fn = fn } end end
    return function(_, ...) return WC[k](WC, ...) end end }),
}
function H.call(src, name, d)
  local f = H.cbs[name] assert(f, 'no callback ' .. name)
  debug.sethook(function() error('LOOP in ' .. name .. ': ' .. debug.traceback()) end, '', 20000000)
  local r = table.pack(pcall(f, src, nil, d or {}))
  debug.sethook()
  if not r[1] then print('ERROR in ' .. name .. ': ' .. tostring(r[2])) H.fails = H.fails + 1 return false, 'error' end
  return table.unpack(r, 2, r.n)
end

-- ---------------------------------------------------------------- es_mdt (departments)
H.depts = {}
H.impounds = {}
H.ext.es_mdt = {
  GetImpounds = function(_, cid) local o = {} for _, r in ipairs(H.impounds) do if r.ownerCharId == cid then o[#o + 1] = r end end return o end,
  PayImpound = function(_, src, id, method) for _, r in ipairs(H.impounds) do if r.id == id and r.ownerCharId == WC:GetCharId(src) and r.status == 'held' and not r.held then r.status = 'released' r.paidWith = method return { amount = r.owe.total } end end return false, 'Not your vehicle' end,
  GetDepartments = function() return H.depts end,
  IsStaff = function(_, src) return H.staff == src end,
  AddCall = function(_, d) H.calls = H.calls or {} local id = #H.calls + 1 H.calls[id] = { id = id, d = d, active = true, units = {}, notes = {} } return id end,
  UpdateCall = function(_, id, d) local c = (H.calls or {})[id] if not c or not c.active then return false, 'closed' end c.updated = d c.d.priority = d.priority or c.d.priority c.d.title = d.title or c.d.title return true end,
  GetCallUnits = function(_, id) local c = (H.calls or {})[id] if not c then return nil end return { active = c.active, units = c.units } end,
  CloseCall = function(_, id, outcome) local c = (H.calls or {})[id] if c then c.active = false c.outcome = outcome end return true end,
}

-- ---------------------------------------------------------------- MySQL (the queries whip_jobs uses)
local T = { biz = {}, st = {}, hist = {}, pay = {}, ledger = {}, lockers = {}, uni = {}, ward = {} }
H.T = T
local seq = { biz = 0, st = 0, hist = 0, ledger = 0, uni = 0 }
local function q(sql, p)
  p = p or {}
  local s = sql:gsub('%s+', ' ')
  local function has(x) return s:find(x, 1, true) ~= nil end
  -- businesses
  if has('FROM `es_jobs_businesses`') and has('SELECT') then local o = {} for _, r in pairs(T.biz) do local c = {} for k, v in pairs(r) do c[k] = v end o[#o + 1] = c end return o end
  if has('INSERT INTO `es_jobs_businesses`') then seq.biz = seq.biz + 1 T.biz[seq.biz] = { id = seq.biz, jobId = p[1], name = p[2], short = p[3], color = p[4], blurb = p[5], logo = p[6], logoVer = p[7], ownerCharId = p[8] } return seq.biz end
  if has('UPDATE `es_jobs_businesses` SET `name`') then local r = T.biz[p[5]] r.name, r.short, r.color, r.blurb = p[1], p[2], p[3], p[4] return 1 end
  if has('UPDATE `es_jobs_businesses` SET `logo`') then T.biz[p[3]].logo, T.biz[p[3]].logoVer = p[1], p[2] return 1 end
  if has('UPDATE `es_jobs_businesses` SET `ownerCharId`') then T.biz[p[2]].ownerCharId = p[1] return 1 end
  if has('DELETE FROM `es_jobs_businesses`') then T.biz[p[1]] = nil return 1 end
  -- stations
  if has("h.`action` = 'deleted'") then local o = {} for _, h in pairs(T.hist) do if h.action == 'deleted' and not T.st[h.stationId] then o[#o + 1] = { id = h.id, stationId = h.stationId, name = h.name, at = h.at } end end return o end
  if has('SELECT `id`,`name`,`jobs`,`blip`,`spots`,`rev` FROM `es_jobs_stations`') then local o = {} for _, r in pairs(T.st) do o[#o + 1] = r end return o end
  if has('UPDATE `es_jobs_stations`') then local r = T.st[p[6]] if not r then return 0 end r.name, r.jobs, r.blip, r.spots, r.rev = p[1], p[2], p[3], p[4], r.rev + 1 return 1 end
  if has('INSERT INTO `es_jobs_stations` (`id`') then T.st[p[1]] = { id = p[1], name = p[2], jobs = p[3], blip = p[4], spots = p[5], rev = 1 } if p[1] > seq.st then seq.st = p[1] end return p[1] end
  if has('INSERT INTO `es_jobs_stations`') then seq.st = seq.st + 1 T.st[seq.st] = { id = seq.st, name = p[1], jobs = p[2], blip = p[3], spots = p[4], rev = 1 } return seq.st end
  if has('DELETE FROM `es_jobs_stations`') then T.st[p[1]] = nil return 1 end
  if has('SELECT 1 FROM `es_jobs_stations`') then return T.st[p[1]] and 1 or nil end
  -- history
  if has('INSERT INTO `es_jobs_station_history`') then seq.hist = seq.hist + 1 T.hist[seq.hist] = { id = seq.hist, stationId = p[1], name = p[2], snapshot = p[3], action = p[4], byCharId = p[5], at = seq.hist } return seq.hist end
  if has('DELETE FROM `es_jobs_station_history` WHERE `stationId`') then return 0 end
  if has('DELETE FROM `es_jobs_station_history` WHERE `id`') then T.hist[p[1]] = nil return 1 end
  if has("`action` LIKE 'before %'") then local best for _, h in pairs(T.hist) do if h.stationId == p[1] and h.action:sub(1, 7) == 'before ' and h.action ~= 'before restore' and (not best or h.id > best.id) then best = h end end return best and { id = best.id } or nil end
  if has('SELECT `snapshot` FROM `es_jobs_station_history`') then local h = T.hist[p[1]] return h and { snapshot = h.snapshot } or nil end
  if has('SELECT `stationId`,`snapshot`,`action`') then local h = T.hist[p[1]] return h and { stationId = h.stationId, snapshot = h.snapshot, action = h.action } or nil end
  if has('FROM `es_jobs_station_history` WHERE `stationId` = ? ORDER BY') then local o = {} for _, h in pairs(T.hist) do if h.stationId == p[1] then o[#o + 1] = { id = h.id, name = h.name, action = h.action, byCharId = h.byCharId, at = h.at, snapshot = h.snapshot } end end table.sort(o, function(a, b) return a.id > b.id end) return o end
  -- pay, ledger, lockers
  if has('SELECT') and has('FROM `es_jobs_pay`') then local o = {} for rid, a in pairs(T.pay) do o[#o + 1] = { roleId = rid, amount = a } end return o end
  if has('DELETE FROM `es_jobs_pay`') then T.pay[p[1]] = nil return 1 end
  if has('INSERT INTO `es_jobs_pay`') then T.pay[p[1]] = p[3] return 1 end
  if has('INSERT INTO `es_jobs_ledger`') then seq.ledger = seq.ledger + 1 T.ledger[seq.ledger] = { id = seq.ledger, jobId = p[1], kind = p[2], amount = p[3], charId = p[4], note = p[5], at = 0 } return seq.ledger end
  if has('SUM(') then local o, i, m = 0, 0, 0 for _, l in pairs(T.ledger) do if l.jobId == p[1] then if l.amount < 0 then o = o - l.amount elseif l.kind ~= 'open' then i = i + l.amount end if l.kind == 'pay_missed' then m = m + 1 end end end return { out = o, inn = i, missed = m } end
  if has('FROM `es_jobs_ledger`') then local o = {} for _, l in pairs(T.ledger) do if l.jobId == p[1] then o[#o + 1] = { id = l.id, kind = l.kind, amount = l.amount, charId = l.charId, note = l.note, at = 0 } end end table.sort(o, function(a, b) return a.id > b.id end) return o end
  -- uniforms, wardrobe
  if has('SELECT * FROM `es_jobs_uniforms`') then local o = {} for _, r in pairs(T.uni) do o[#o + 1] = r end return o end
  if has('SELECT * FROM `es_jobs_wardrobe`') then local o = {} for _, r in pairs(T.ward) do o[#o + 1] = r end return o end
  if has('INSERT INTO `es_jobs_uniforms`') then seq.uni = seq.uni + 1 T.uni[seq.uni] = { id = seq.uni, jobId = p[1], name = p[2], body = p[3], minLevel = p[4], parts = p[5], sort = p[6] } return seq.uni end
  if has('UPDATE `es_jobs_uniforms` SET `name`') then local r = T.uni[p[6]] r.name, r.minLevel, r.parts, r.body = p[1], p[2], p[3], p[4] return 1 end
  if has('UPDATE `es_jobs_uniforms` SET `sort`') then T.uni[p[2]].sort = p[1] return 1 end
  if has('DELETE FROM `es_jobs_uniforms`') then T.uni[p[1]] = nil return 1 end
  if has('INSERT INTO `es_jobs_wardrobe`') then T.ward[p[1]] = T.ward[p[1]] or { charId = p[1], own = p[2] } T.ward[p[1]].uniformId, T.ward[p[1]].jobId = p[3], p[4] return 1 end
  if has('UPDATE `es_jobs_wardrobe`') then local r = T.ward[p[3]] if r then r.uniformId, r.jobId = p[1], p[2] end return 1 end
  if has('DELETE FROM `es_jobs_wardrobe`') then T.ward[p[1]] = nil return 1 end
  if has('es_jobs_lockers') then T.lockers[p[1]] = p[2] return 1 end
  -- medical (0.3.0)
  T.med, T.bills = T.med or {}, T.bills or {}
  if has('INSERT INTO `es_jobs_medical`') then local id = #T.med + 1 T.med[id] = { id = id, charId = p[1], name = p[2], kind = p[3], injury = p[4], treatment = p[5], notes = p[6], jobId = p[7], bill = p[8], byCharId = p[9], byName = p[10], place = p[11], at = 1 } return id end
  if has('INSERT INTO `es_jobs_med_bills`') then local id = #T.bills + 1
    local paid = has("'paid'")
    T.bills[id] = { id = id, charId = p[1], jobId = p[2], amount = p[3], reason = p[4], status = paid and 'paid' or p[5], recordId = (not paid) and p[6] or nil, at = 1 } return id end
  if has('FROM `es_jobs_med_bills`') and has("`status` = 'unpaid' ORDER") then local o = {} for i = #T.bills, 1, -1 do local b = T.bills[i] if b.charId == p[1] and b.status == 'unpaid' then o[#o + 1] = { id = b.id, jobId = b.jobId, amount = b.amount, reason = b.reason, at = 1 } end end return o end
  if has('SELECT * FROM `es_jobs_med_bills` WHERE `id` = ? AND `charId` = ?') then local b = T.bills[p[1]] return (b and b.charId == p[2]) and { b } or {} end
  if has('SELECT * FROM `es_jobs_med_bills` WHERE `id` = ?') then local b = T.bills[p[1]] return b and { b } or {} end
  if has("SET `status` = 'paying'") then local b = T.bills[p[1]] if b and b.status == 'unpaid' then b.status = 'paying' return 1 end return 0 end
  if has('UPDATE `es_jobs_med_bills` SET `status` = ?, `paidAt`') then T.bills[p[3]].status = p[1] return 1 end
  if has("SET `status` = 'waived'") then T.bills[p[1]].status = 'waived' return 1 end
  if has('FROM `es_jobs_medical` m') and not has('es_jobs_med_bills') then local by = {} local o = {}
    for _, r in ipairs(T.med) do if not p[1] or r.name:lower():find(p[1]:gsub('%%', ''):lower(), 1, true) or r.charId == p[2] then
      if not by[r.charId] then by[r.charId] = { charId = r.charId, name = r.name, n = 0, last = 1 } o[#o + 1] = by[r.charId] end by[r.charId].n = by[r.charId].n + 1 end end return o end
  if has('FROM `es_jobs_medical` ORDER BY `id` DESC LIMIT 12') then local o = {} for i = #T.med, math.max(1, #T.med - 11), -1 do o[#o + 1] = T.med[i] end return o end
  if has('FROM `es_jobs_medical` WHERE `charId` = ? ORDER BY `id` DESC LIMIT 60') then local o = {} for i = #T.med, 1, -1 do if T.med[i].charId == p[1] then o[#o + 1] = T.med[i] end end return o end
  if has('SELECT `name` FROM `es_jobs_medical` WHERE `charId` = ?') then for i = #T.med, 1, -1 do if T.med[i].charId == p[1] then return { T.med[i] } end end return {} end
  -- 0.6.0: es_mdt's EMS side
  if has('FROM `es_jobs_medical` WHERE `charId` = ? ORDER BY `id` DESC LIMIT ?') then local o = {} for i = #T.med, 1, -1 do if T.med[i].charId == p[1] and #o < p[2] then o[#o + 1] = T.med[i] end end return o end
  if has("FROM `es_jobs_medical` WHERE `charId` = ? AND `kind` <> 'note'") then for i = #T.med, 1, -1 do local r = T.med[i] if r.charId == p[1] and r.kind ~= 'note' then return { r } end end return {} end
  if has('FROM `es_jobs_med_bills` b') then
    local i, st, cid = 1, nil, nil
    if has('b.`status` = ?') then st = p[i] i = i + 1 end
    local jobs = s:match('b%.`jobId` IN %(([%d,]+)%)')
    if has('b.`charId` = ?') then cid = p[i] i = i + 1 end
    local lim, o = p[i], {}
    for k = #T.bills, 1, -1 do local b = T.bills[k]
      local inJ = not jobs or (',' .. jobs .. ','):find(',' .. b.jobId .. ',', 1, true)
      if (not st or b.status == st) and (not cid or b.charId == cid) and inJ and #o < lim then
        local name for j = #T.med, 1, -1 do if T.med[j].charId == b.charId then name = T.med[j].name break end end
        o[#o + 1] = { id = b.id, charId = b.charId, jobId = b.jobId, amount = b.amount, reason = b.reason, status = b.status, recordId = b.recordId, at = 1, name = name } end end
    return o end
  if has('SELECT `byCharId`, `kind`, COUNT(*)') then
    local jobs = s:match('`jobId` IN %(([%d,]+)%)')
    local agg, o = {}, {}
    for _, r in ipairs(T.med) do if r.byCharId and (not jobs or (',' .. jobs .. ','):find(',' .. tostring(r.jobId) .. ',', 1, true)) then
      local k = r.byCharId .. '|' .. r.kind agg[k] = agg[k] or { byCharId = r.byCharId, kind = r.kind, n = 0 } agg[k].n = agg[k].n + 1 end end
    for _, v in pairs(agg) do o[#o + 1] = v end return o end
  error('unhandled SQL: ' .. s)
end
local function single(sql, p) local r = q(sql, p) if type(r) == 'table' and r[1] then return r[1] end return r end
MySQL = { query = { await = q }, single = { await = single }, scalar = { await = function(s, p) return q(s, p) end },
  insert = setmetatable({ await = q }, { __call = function(_, s, p) return q(s, p) end }),
  update = setmetatable({ await = q }, { __call = function(_, s, p) return q(s, p) end }) }

-- ---------------------------------------------------------------- load
function H.load()
  local man = io.open(ROOT .. '/fxmanifest.lua'):read('a'):gsub('%-%-[^\n]*', '')
  local files = {}
  local function list(key) local b = man:match(key .. '%s*(%b{})') for f in b:gmatch("'([^']+)'") do if f:sub(1, 1) ~= '@' then files[#files + 1] = f end end end
  list('shared_scripts') list('server_scripts')
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(ROOT .. '/' .. f))
    local ok, e = pcall(chunk)
    if not ok then print('LOADERR ' .. f .. ': ' .. tostring(e)) H.fails = H.fails + 1 end
  end
  H.registerFn()
end
return H
