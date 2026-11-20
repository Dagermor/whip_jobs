-- es_jobs 0.1.0: the job pack. Stations (shared by departments), their peds and spots, pay by rank,
-- the armory, the fleet garage and lockers, and businesses. Stations are made in the admin menu (/w -> Stations) or Departments -> Locations, businesses with /business:
-- they live in the database, not here. Everything below is a default; /whip > Settings > Jobs changes it live.
Config = Config or {}

Config.BusinessCommand = 'business'     -- opens Businesses (owners and managers; admins see them all)
Config.AdminAce = 'es_jobs.admin'       -- may edit every station and business (server.cfg add_ace); WHIP admins always may

Config.Stations = {
    pedDistance = 45.0,                  -- metres: a station's peds appear within this, and go past it + 10
    reach = 2.0,                         -- metres: how close to use a ped or spot
    seeFrom = 8.0,                       -- metres: prompts appear from
    blips = true,                        -- show station blips at all
    blipSprite = 60,                     -- the default blip (60 = police star), per station in the editor
    blipColor = 29,
    historyKeep = 30,                    -- undo steps kept per station
    -- The ped a new spot gets, by the department type (then by name: "Fire" / "FD" and "Ranger" / "Park" get their own)
    peds = {
        police = 's_m_y_cop_01', sheriff = 's_m_y_sheriff_01', state = 's_m_y_hwaycop_01', ranger = 's_m_y_ranger_01',
        ems = 's_m_m_paramedic_01', fire = 's_m_y_fireman_01', doj = 's_m_m_highsec_01', none = 's_m_m_security_01',
        -- 0.4.0: DOJ spots get their own (any department's spot of that type)
        court_clerk = 'a_f_y_business_01', courtroom = 's_m_m_highsec_01', chambers = 'a_m_m_business_01',
        da_office = 'a_f_y_business_02', pd_office = 'a_m_y_business_02',
    },
    -- The ped list in the editor (any other model can be typed in)
    pedList = {
        { model = 's_m_y_cop_01', label = 'Police officer' }, { model = 's_f_y_cop_01', label = 'Police officer (female)' },
        { model = 's_m_y_sheriff_01', label = 'Sheriff deputy' }, { model = 's_f_y_sheriff_01', label = 'Sheriff deputy (female)' },
        { model = 's_m_y_hwaycop_01', label = 'Highway patrol' }, { model = 's_m_y_ranger_01', label = 'Park ranger' },
        { model = 's_f_y_ranger_01', label = 'Park ranger (female)' }, { model = 's_m_m_paramedic_01', label = 'Paramedic' },
        { model = 's_m_y_fireman_01', label = 'Firefighter' }, { model = 's_m_m_doctor_01', label = 'Doctor' },
        { model = 's_f_y_scrubs_01', label = 'Nurse' }, { model = 's_m_m_highsec_01', label = 'Court security' },
        { model = 's_m_m_security_01', label = 'Security guard' }, { model = 'cs_prolsec_02', label = 'Prison guard' },
        { model = 's_m_y_swat_01', label = 'SWAT' }, { model = 's_m_m_ciasec_01', label = 'Agent' },
        { model = 'a_f_y_business_01', label = 'Clerk (female)' }, { model = 'a_m_y_business_01', label = 'Clerk' },
        { model = 'a_m_m_business_01', label = 'Judge / senior counsel' }, { model = 'a_f_y_business_02', label = 'Receptionist' },
        { model = 'a_m_y_business_02', label = 'Lawyer' }, { model = 'a_f_y_business_04', label = 'Lawyer (female)' },
    },
}

-- Pay by rank, from each department's or business's own bank account (its WHIP job account), while on duty.
Config.Pay = {
    enabled = true,
    intervalMinutes = 15,                -- on-duty minutes per paycheck
    base = 150,                          -- a rank with no pay set: base + level x perLevel per paycheck
    perLevel = 3,
    maxPay = 5000,                       -- the most one paycheck can be (the Pay tab refuses more)
    bossNotice = true,                   -- tell the department's leaders (and staff) when the account can't pay
}

-- The armory, the fleet and the locker
Config.Gear = {
    armoryMax = 10,                      -- the most of one item someone may carry from the armory
    fleetOne = true,                     -- one fleet vehicle per person at a time
    fleetReturnOnClockOff = true,        -- their fleet vehicle goes away when they clock off
    fleetReturnRange = 40.0,             -- metres from a garage spot to put the vehicle back
    fleetDespawnMinutes = 0,             -- 0 = it stays while they are on duty (WHIP still removes it after 10 min with nobody near)
    uniformsOnlyOnDuty = true,           -- the uniform locker is for people on duty at one of the station's departments
    adjust = true,                       -- officers may adjust a uniform (hat, vest, gloves...) in the locker, for their shift
    restoreOnClockOff = true,            -- clocking off puts their own clothes back on
    lockerSlots = 20,                    -- a personal locker's slots (0: no personal locker)
    lockerWeight = 40.0,
}

-- Player-owned businesses (/business). An admin makes one for its owner; with playerCreate a player may start their own.
Config.Business = {
    playerCreate = false,                -- players may start a business themselves
    createPrice = 25000,                 -- what that costs them (from their bank)
    maxPerOwner = 2,                     -- businesses one character may own
    startBalance = 0,                    -- put into a new business account when an admin makes it
    ped = 'a_m_y_business_01',           -- a new business spot's ped
    ranks = {                            -- a new business's ranks (the owner takes the top one)
        { name = 'Owner', level = 100 }, { name = 'Manager', level = 80, permissions = { canHire = true, canFire = true, canPromote = true, canDemote = true } },
        { name = 'Supervisor', level = 50, permissions = { canHire = true } }, { name = 'Employee', level = 20 }, { name = 'Trainee', level = 1 },
    },
}

-- Police: with es_jail's cuffs. Officers on duty at a police-type department (es_mdt's type) put a cuffed person in a
-- car at its door and take them out again, test for alcohol and drugs, and lay spike strips.
Config.Police = {
    types = { police = true, sheriff = true, state = true },   -- es_mdt department types that are police
    jobs = {},                           -- more jobs that are police (job keys or ids), e.g. a business security firm
    reach = 3.0,                         -- metres to the person you test or seat
    breathalyzer = {
        item = 'es_jobs_breathalyzer',           -- a tool: kept
        seconds = 5,
        stat = 'drunk',                  -- a WHIP stat another script keeps (0-100); none on this server reads 0.000
        perPoint = 0.004,                -- BAC per point of the stat (100 = 0.40)
        limit = 0.08,                    -- over this reads as over the limit
    },
    drugTest = {
        item = 'es_jobs_drug_test',          -- one used per test
        seconds = 6,
        -- WHIP effects (ApplyEffect names) another script puts on, by a word in their name -> what the test shows
        effects = { weed = 'Cannabis', cannabis = 'Cannabis', joint = 'Cannabis', stoned = 'Cannabis',
            coke = 'Cocaine', cocaine = 'Cocaine', crack = 'Cocaine', meth = 'Methamphetamine', heroin = 'Opiates', opioid = 'Opiates',
            oxy = 'Opiates', lsd = 'LSD', acid = 'LSD', ecstasy = 'MDMA', mdma = 'MDMA', drug = 'Drugs' },
        stats = {},                      -- WHIP stats too: { stoned = 'Cannabis' } (above 0 is positive)
    },
    spikes = {
        item = 'es_jobs_spike_strip',
        model = 'p_ld_stinger_s',
        perOfficer = 2,                  -- strips one officer may have down at once
        minutes = 10,                    -- a strip left down goes after this (0: until picked up)
    },
}

-- The impound clerk (a station spot anyone may use): owners pay their es_mdt impound fees and take the car back out here.
Config.ImpoundClerk = {
    methods = { 'bank', 'cash' },
}

-- EMS (0.3.0): wounded and down, calls to EMS through es_mdt, treatment, the hospital desk, medical records and bills.
-- Dying first makes you WOUNDED (yellow): on the ground, you can crawl, a timer runs (shorter for a headshot). Call EMS
-- yourself (G / D-pad left), or the call goes out on its own after autoCallAfter. Someone with a first aid kit can help you
-- up; EMS treat you. If the timer runs out, or you are hurt again, you are DOWN (red): WHIP's death screen, a P1 call
-- (the same es_mdt call, upgraded), and the respawn timer is held while EMS units are on the call.
Config.EMS = {
    enabled = true,
    types = { ems = true, fire = true },     -- es_mdt department types that are EMS
    jobs = {},                               -- other WHIP jobs that are EMS (job names or ids)
    wounded = {
        seconds = 180,                       -- how long you stay wounded before you go down
        headshotSeconds = 60,                -- after a headshot
        headshotDown = false,                -- true: a headshot puts you straight down
        health = 120,                        -- your health while wounded (out of 200; 100 = dead)
        autoCallAfter = 60,                  -- seconds wounded before EMS is called for you (0 = never on its own)
        crawlSpeed = 1.0,
    },
    calls = {
        woundedPriority = 2,
        downPriority = 1,
        downCritical = false,                -- the down call in es_mdt's critical tier (above P1)
        holdRespawn = true,                  -- the respawn waits while EMS units are on the call
    },
    firstAid = { item = 'es_jobs_first_aid', seconds = 7, health = 150 },
    medbag = { item = 'es_jobs_medbag' },
    treat = { seconds = 6, revive = 8 },
    -- what the patient pays the EMS department (from their bank; what they can't pay stays a bill, paid at a hospital desk)
    bills = { treat = 250, revive = 500, respawn = 750, desk = 400 },
    billMethods = { 'bank', 'cash' },        -- how a bill is paid at a hospital desk
    desk = {
        staffedAt = 1,                       -- with this many EMS on duty, the desk calls them instead of treating you itself
        seconds = 8,
    },
}
