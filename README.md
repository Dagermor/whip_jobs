# whip_jobs: the job pack for WHIP

> **Community resource.** whip_jobs is made by the community for [WHIP](https://whipfx.net) servers. It is **not an official WHIPFX resource** and is not made, endorsed or supported by the WHIPFX team. Questions and bugs go to this repository's issues, not to WHIPFX.
>
> **Renamed:** this was **es_jobs** up to 0.4.0. Old links to `Dagermor/es_jobs` redirect here. Upgrading: see [Upgrading from es_jobs](#upgrading-from-es_jobs).

Everything a job does in the world on a [WHIP](https://whipfx.net) FiveM server: stations with peds, duty and pay by rank, the armory, fleet vehicles, lockers and uniforms, police tools, EMS down states and the hospital, the impound clerk, the courthouse desks, and player-owned businesses.

It works with **[es_mdt](https://github.com/Dagermor/es_mdt)** (departments, ranks, dispatch, tickets, impound, the DOJ) and **es_jail** (cuffs). es_mdt keeps the paperwork and computer side; whip_jobs does what happens in the world.

> **Status: public test release (0.6.0).**

## Features

- **Stations** (`/w` → Stations with WHIP developer mode on, or `/departments` → a department → Locations):
  - A station is shared by any departments and businesses, with an optional blip (everyone, members or hidden).
  - Spots: duty desk, armory, locker room, garage, helipad, boat dock, impound clerk, hospital check-in, and the courthouse (court clerk window, courtroom, judge's chambers / bench, District Attorney's office, public defender's office).
  - Placed with WHIP's ghost ped or car (move, turn, **E / A** to place), "use my position", or typed in. "Add the usual spots" adds the standard set for a department type and walks you through placing each one.
  - Default peds by department type (police, sheriff, state, ranger, fire, EMS, DOJ) and per courthouse spot, each changeable from a picture grid or any model name.
  - History, undo, restore deleted stations, export and import.
- **Duty and pay:** clock on and off at the duty desk. Paychecks by rank on an on-duty timer, paid from the job's own bank account; leaders set pay per rank.
- **Armory and fleet:** equipment and vehicles by rank, free and logged; one fleet vehicle per person, put back at the garage or gone at clock-off.
- **Lockers and uniforms:** personal lockers; uniforms built in WHIP's character editor (add-on clothing works), limited by rank, with a live preview. Change them during a shift; your own clothes come back at clock-off or logout.
- **Police:** with es_jail's cuffs, put a cuffed person in a car and take them out into an escort; breathalyzer, drug swab and spike strips.
- **EMS:** wounded (yellow, 3 min, shorter after a headshot; crawl, Call EMS, auto-call after 60 s; first aid kits) and down (red, needs EMS, the same call upgraded to P1). Respawn waits while EMS units are on the call. Examine, treat and revive with a medical bag, medical records, and bills paid into the EMS account. Hospital check-in desk.
- **Impound clerk:** owners pay es_mdt's impound fees by bank or cash and get their car brought out.
- **Courthouse:** the clerk window and public defender's office open es_mdt's `/court` portal (court services, pay a fine or fee, lawyers); DOJ staff open the DOJ tablet. No bail.
- **Businesses** (`/business`): player-owned jobs made like `/departments`, with a name, colour and logo (upload with live preview), ranks and pay, staff, and a bank account with a ledger.

## Requirements

| Resource | Needed | What for |
|---|---|---|
| whip_core (WHIP 1.0+) | **required** | players, jobs, money, items, the ghost placer, the UI kit |
| oxmysql | **required** | database (tables are made on first start) |
| [es_mdt](https://github.com/Dagermor/es_mdt) 2.4.2+ (2.4.0+ while the folder is still named es_jobs) | recommended | departments and ranks, dispatch, impound and the court. Without it only businesses exist |
| es_jail | optional | cuffs for the police actions |
| whip_phone | optional | texts |

## Install

1. Put the `whip_jobs` folder in your resources (for example `resources/[es]/whip_jobs`).
2. In `server.cfg`, start it **after** its dependencies:
   ```
   ensure oxmysql
   ensure whip_core
   ensure es_jail
   ensure es_mdt
   ensure whip_jobs
   ```
3. Optional: give a group full access to every station and business: `add_ace group.admin whip_jobs.admin allow` (WHIP admins always have it).
4. Restart. Then set up stations in `/w` → Stations, or from `/departments` → Locations. With es_mdt, the old courthouse clerk desk is moved into a "Courthouse" station once.

## Controller support

Every whip_jobs screen works with a controller: the D-pad or left stick moves a focus ring, **A** selects, **B** goes back, bumpers switch tabs, and text fields open WHIP's on-screen keyboard. The ghost placer, the locker preview, the wounded Call EMS button (G or D-pad left) and the prompts work the same way.

## Configuration

- **Live settings:** `/whip` → Settings → Jobs (stations, default peds, pay, gear, police, EMS timers and prices, businesses). They are saved by WHIP and override `config.lua`.
- **`config.lua`:** the defaults: `Config.Stations` (ped distance, reach, blips, default peds, the ped picture list), `Config.Pay`, `Config.Gear`, `Config.Business` (`playerCreate`, price, ranks), `Config.Police`, `Config.ImpoundClerk`, `Config.EMS`.
- **Commands:** `/business` (`Config.BusinessCommand`). Stations are in WHIP's admin menu, not a command.

## Upgrading from es_jobs

whip_jobs 0.5.0 is es_jobs with a new name. Your stations, uniforms, pay, businesses, medical records and lockers stay: the database tables keep their `es_jobs_` names.

1. Stop the server. Back up the database and the old `es_jobs` folder.
2. Settings saved in `/whip` → Settings → Jobs are stored under the resource name. Move them over once (whip_core's own table; nothing else changes):
   ```sql
   UPDATE whip_settings SET owner = 'whip_jobs' WHERE owner = 'es_jobs';
   UPDATE whip_settings_log SET owner = 'whip_jobs' WHERE owner = 'es_jobs';
   ```
3. Delete the `es_jobs` folder, put `whip_jobs` in its place, and change `ensure es_jobs` to `ensure whip_jobs` in `server.cfg`. Update es_mdt to 2.4.2 (it finds the job pack under either name). whip_jobs refuses to start while an `es_jobs` is still running.
4. The `es_jobs.admin` ace still works; `whip_jobs.admin` is the new one.
5. The items are now `whip_jobs_breathalyzer`, `whip_jobs_drug_test`, `whip_jobs_spike_strip`, `whip_jobs_first_aid` and `whip_jobs_medbag`. If players already hold the old `es_jobs_*` items, set the item names in `config.lua` (`Config.Police`, `Config.EMS`) back to the old ones, or give out the new ones.
6. Other scripts that call `exports.es_jobs:...` change to `exports.whip_jobs:...`; callbacks and events are now `whip_jobs:*`.

## Exports

- Client: `OpenStations({ jobId, stationId, new, starter })`, `OpenBusiness()`, `GetStarter(type)`, `IsOpen()`.
- Server: `GetStations(jobId)`, `GetSpots(type)`, `HasSpotType(type)`, `GetBusinesses()`, `GetFleetVehicle(...)`, `RecordIncome(...)`, `GetHurtState(...)`, `HandlesDowns()`.
- Server, for es_mdt's EMS side (0.6.0): `GetMedical(charId, limit)`, `LastTreatment(charId, days)`, `GetMedicalBills(opts)`, `WaiveMedicalBill(billId, by, note)`, `GetMedicalStats(days, jobIds)`. es_mdt 2.5.0 shows treatments, bills and EMS stats with them.

## Tests

`tests/` has Lua sims that load the real server and client files against an in-memory whip_core, es_mdt and MySQL:

```
lua5.4 tests/server_test.lua .
lua5.4 tests/client_test.lua .
lua5.4 tests/ems_test.lua .
lua5.4 tests/doj_test.lua .
```

## License

MIT, see [LICENSE](LICENSE).
