-- es_jobs: the station editor's place in WHIP's admin menu. whip_core's /whip panel has no way for another resource to
-- add a section of its own (its sections are built into whip_core), so the editor lives in WHIP's admin menu, /w, as a
-- page: "Stations" (shown to WHIP admins with developer mode on). /whip -> Settings -> Jobs holds the stations'
-- settings and says where the editor is. Department leaders still open the same editor from Departments -> Locations,
-- and business owners from /business. The server checks every save (admin, or a leader of the station's job).
ESJ = ESJ or {}
local level = 'top'   -- 'top' or a station id

local function orgNames(st)
    local n = {}
    for _, j in ipairs(st.jobs or {}) do
        local o = (ESJ.ORGS or {})[tostring(j)]
        n[#n + 1] = o and (o.short or o.name) or ('#' .. j)
    end
    return #n > 0 and table.concat(n, ' / ') or 'nobody'
end

local function stationById(id)
    for _, st in ipairs(ESJ.STATIONS or {}) do if st.id == id then return st end end
end

local function rows()
    if level ~= 'top' then
        local st = stationById(level)
        if not st then level = 'top' return rows() end
        local r = {
            { id = 'edit', label = 'Open in the editor', icon = 'target', close = true, desc = 'Spots, peds, blip, who shares it, history and undo.' },
        }
        local first = st.spots and st.spots[1]
        if first then r[#r + 1] = { id = 'tp', label = 'Teleport here', icon = 'car', desc = ('%s: %.1f, %.1f, %.1f'):format(first.label or first.type, first.x, first.y, first.z) } end
        r[#r + 1] = { sep = 'Spots' }
        for _, s in ipairs(st.spots or {}) do
            r[#r + 1] = { label = (s.label or s.type) .. ' (' .. s.type .. ')', kind = 'note' }
        end
        if #(st.spots or {}) == 0 then r[#r + 1] = { label = 'No spots yet', kind = 'note' } end
        return { title = st.name, back = 'Stations', rows = r }
    end
    local r = {
        { id = 'open', label = 'Open the station editor', icon = 'target', close = true, desc = 'Every station of every department and business.' },
        { id = 'new', label = 'New station here', icon = 'target', close = true, desc = 'Opens the editor on a new station; place its spots where you stand.' },
        { sep = 'Stations' },
    }
    local list = ESJ.STATIONS or {}
    for _, st in ipairs(list) do
        r[#r + 1] = { id = 'st:' .. st.id, label = st.name, kind = 'open',
            desc = ('%d spot%s · %s'):format(#(st.spots or {}), #(st.spots or {}) == 1 and '' or 's', orgNames(st)) }
    end
    if #list == 0 then r[#r + 1] = { label = 'No stations yet', kind = 'note' } end
    return { rows = r }
end

local function select(id)
    if id == 'open' then ESJ.openEditor({})
    elseif id == 'new' then ESJ.openEditor({ new = true })
    elseif type(id) == 'string' and id:sub(1, 3) == 'st:' then level = tonumber(id:sub(4)) or 'top'
    elseif id == 'edit' then ESJ.openEditor({ stationId = level })
    elseif id == 'tp' then
        local st = stationById(level)
        local s = st and st.spots and st.spots[1]
        if s then
            CreateThread(function()
                local ped = PlayerPedId()
                RequestCollisionAtCoord(s.x, s.y, s.z)
                SetEntityCoords(ped, s.x, s.y, s.z + 0.5, false, false, false, false)
                SetEntityHeading(ped, (s.h or 0.0) + 0.0)
            end)
        end
    end
    Whip.core:RefreshDevPage('stations')
end

--- the station list changed (client/stations.lua): redraw the page if it is on screen
function ESJ.devRefresh() pcall(function() Whip.core:RefreshDevPage('stations') end) end

Whip.register(function()
    local ok, why = Whip.core:RegisterDevPage('stations', {
        label = 'Stations',
        desc = 'The job pack\'s station editor: duty desks, armories, garages, lockers and their peds.',
        rows = rows,
        onSelect = select,
        onBack = function() level = 'top' end,
        onOpen = function() level = 'top' end,
    })
    if not ok then print(('^3[es_jobs] the Stations page in /w was refused: %s^7'):format(tostring(why))) end
end)
