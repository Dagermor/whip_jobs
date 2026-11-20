-- whip_jobs (named es_jobs before 0.5.0): the job pack for WHIP. A community resource, not an official WHIPFX one. Stations shared by departments and businesses (peds, duty, armory, fleet garage,
-- lockers), pay by rank from each job's own bank account, and player-owned businesses made like /departments.
-- Works with es_mdt (departments, ranks, dispatch, fines and impound money) and es_jail (cuffs); neither is required.
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'whip_jobs'
description 'Job pack for WHIP: stations, peds, duty, armory, fleet, uniforms, police tools, impound clerk, EMS (wounded/down, hospital, medical records), pay by rank, businesses'
author 'Rob'
version '0.6.0'
whip_requires '1.0'

dependencies { 'oxmysql', 'whip_core' }   -- optional: es_mdt (departments), es_jail (cuffs), whip_phone

shared_scripts {
    '@whip_core/lib/satellite.lua',
    'config.lua',
    'shared/settings.lua',      -- /whip > Settings > Jobs
    'shared/util.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@whip_core/server/db_guard.lua',
    'server/tables.lua',
    'server/orgs.lua',          -- departments (es_mdt) and businesses (ours): who belongs where, at what level
    'server/business.lua',      -- /business: make and run a business
    'server/stations.lua',      -- stations and their spots: the editor, history, backup
    'server/gear.lua',          -- duty, armory, fleet garage, personal locker
    'server/uniforms.lua',      -- uniforms: made in WHIP's editor, worn from the locker room, own clothes back at clock-off
    'server/police.lua',        -- police: put in / take out of a car (es_jail cuffs), breathalyzer, drug test, spike strips
    'server/impound.lua',       -- the impound clerk: pay es_mdt's impound fees, take the car out
    'server/ems.lua',           -- EMS: wounded and down, calls, first aid, treatment, hospital desk, medical records and bills
    'server/pay.lua',           -- paychecks from each job's account, the ledger
    'server/main.lua',
}

client_scripts {
    'client/pad.lua',           -- controller support for every whip_jobs screen
    'client/main.lua',          -- the screen (NUI) and its callbacks
    'client/stations.lua',      -- peds, prompts and blips near the player
    'client/editor.lua',        -- placing: ghost peds and cars, use my position, teleport, ped pictures
    'client/uniforms.lua',      -- the locker room: live preview, camera, WHIP's editor for uniforms
    'client/police.lua',        -- police prompts, seating, spike strips
    'client/ems.lua',           -- wounded (crawl, Call EMS), the HUD chip, first aid and EMS prompts
    'client/admin.lua',         -- the editor's page in WHIP's admin menu (/w -> Stations)
}

ui_page 'html/index.html'
nui_callback_strict_mode 'true'

files {
    'html/index.html',
    'html/app.css',
    'html/app.js',
    'html/editor.js',
    'html/business.js',
    'html/gear.js',
    'html/locker.js',
    'html/ems.js',
    'html/pad.js',
    'html/pad.css',
    'html/img/items/*.webp',
}
