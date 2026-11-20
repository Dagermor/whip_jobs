-- whip_jobs: what both sides agree on. Spot types (what a station's spots can be), and the checks every value from a
-- page goes through on the server.
ESJ = ESJ or {}

-- Spot types. ped: a ped stands there by default. spawns: has spawn points (cars, helicopters, boats). public: anyone may
-- use it (not only the station's members). phase: built in a later update (the editor shows them greyed out until then).
ESJ.TYPES = {
    { key = 'duty',     label = 'Duty: clock on / off',   icon = '⏱', ped = true,  hint = 'Members clock on and off here.' },
    { key = 'armory',   label = 'Armory',                 icon = '🛡', ped = true,  stock = true, hint = 'Equipment by rank, issued free.' },
    { key = 'locker',   label = 'Locker room',            icon = '🗄', ped = false, hint = 'Uniforms by rank (live preview) and personal lockers.' },
    { key = 'garage',   label = 'Garage (vehicles)',      icon = '🚓', ped = true,  spawns = 'car',  fleet = true, hint = 'Fleet vehicles by rank; put them back here.' },
    { key = 'helipad',  label = 'Helipad',                icon = '🚁', ped = false, spawns = 'heli', fleet = true, hint = 'Fleet helicopters by rank.' },
    { key = 'boatdock', label = 'Boat dock',              icon = '⚓', ped = true,  spawns = 'boat', fleet = true, hint = 'Fleet boats by rank.' },
    { key = 'impound',  label = 'Impound clerk',          icon = 'Ⓟ', ped = true,  spawns = 'car', phase = 2, public = true, hint = 'Owners pay and get their impounded cars back.' },
    { key = 'hospital', label = 'Hospital check-in',      icon = '✚', ped = true,  phase = 3, public = true, hint = 'Treatment, medical bills, and medical records for EMS.' },
    -- 0.4.0: the DOJ (es_mdt). `doj` = offered first and in the DOJ set; `pedKey` = its own default ped (Config.Stations.peds)
    { key = 'court_clerk', label = 'Court clerk window',  icon = '⚖', ped = true,  phase = 4, public = true, doj = true, pedKey = 'court_clerk',
      hint = 'Anyone: court services (cases, payments, petitions) and paying a fine or fee.' },
    { key = 'courtroom',   label = 'Courtroom (bailiff)', icon = '🏛', ped = true,  phase = 4, public = true, doj = true, pedKey = 'courtroom',
      hint = 'Anyone: their cases and hearings. DOJ staff: the DOJ tablet.' },
    { key = 'chambers',    label = "Judge's chambers / bench", icon = '🔨', ped = true, phase = 4, doj = true, pedKey = 'chambers',
      hint = 'DOJ staff: the DOJ tablet (docket, cases, warrants).' },
    { key = 'da_office',   label = "District Attorney's office", icon = '📁', ped = true, phase = 4, doj = true, pedKey = 'da_office',
      hint = 'DOJ staff: the DOJ tablet (cases, filings, plea offers).' },
    { key = 'pd_office',   label = "Public defender's office", icon = '⚑', ped = true, phase = 4, public = true, doj = true, pedKey = 'pd_office',
      hint = 'Anyone: hire a lawyer or ask for a public defender. DOJ staff: the DOJ tablet.' },
}
ESJ.TYPE = {}
for _, t in ipairs(ESJ.TYPES) do ESJ.TYPE[t.key] = t end
ESJ.PHASE = 4   -- the spot types built so far (phase <= this)
ESJ.TYPE.court = ESJ.TYPE.court_clerk   -- 0.4.0: the old placeholder key (never placeable) reads as the clerk window

-- 0.4.0: "Add the usual spots" in the editor, by the department type (then a business)
ESJ.STARTER = {
    police = { 'duty', 'armory', 'locker', 'garage' }, sheriff = { 'duty', 'armory', 'locker', 'garage' },
    state = { 'duty', 'armory', 'locker', 'garage' }, ranger = { 'duty', 'armory', 'locker', 'garage' },
    ems = { 'duty', 'locker', 'garage', 'hospital' },
    doj = { 'duty', 'court_clerk', 'courtroom', 'chambers', 'da_office', 'pd_office', 'locker' },
    business = { 'duty' },
}

ESJ.LIMITS = { spots = 40, spawns = 20, stock = 60, vehicles = 40, name = 48, label = 40 }

function ESJ.trim(s) return (type(s) == 'string' and s:gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', '')) or '' end
function ESJ.num(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    if lo and v < lo then return nil end
    if hi and v > hi then return nil end
    return v
end
function ESJ.int(v, lo, hi, def)
    v = ESJ.num(v)
    if not v then return def end
    v = math.floor(v + 0.5)
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end
--- a model or item name: letters, digits, _ (and - for items), 1-48 long
function ESJ.name(s, dash)
    s = ESJ.trim(s)
    if s == '' or #s > 48 then return nil end
    if dash then return s:match('^[%w_%-]+$') and s or nil end
    return s:match('^[%w_]+$') and s or nil
end
--- a point from a page: { x, y, z, h } inside the map
function ESJ.point(p)
    if type(p) ~= 'table' then return nil end
    local x, y, z = ESJ.num(p.x, -9000, 9000), ESJ.num(p.y, -9000, 11000), ESJ.num(p.z, -200, 2500)
    if not (x and y and z) then return nil end
    local h = (ESJ.num(p.h, -720, 720) or 0.0) % 360
    local r = function(n) return math.floor(n * 100 + 0.5) / 100 end
    return { x = r(x), y = r(y), z = r(z), h = r(h) }
end
function ESJ.dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
