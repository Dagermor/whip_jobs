# Changelog

## 0.6.0 (2026-11-20)

- **For es_mdt 2.5.0's EMS side** (server exports, read by the MDT): `GetMedical(charId, limit)` (records, open bills, owed), `LastTreatment(charId, days)`, `GetMedicalBills({ status, jobIds, charId, limit })`, `WaiveMedicalBill(billId, by, note)` (logged) and `GetMedicalStats(days, jobIds)` (per medic, per kind).
- es_mdt decides who may see or waive; whip_jobs only reads and writes its own tables. No other changes.

## 0.5.0 (2026-11-20)

- **Renamed es_jobs → whip_jobs** (resource, repository, exports, callbacks, events, page, commands' ace, docs). A community resource, not an official WHIPFX one.
- Data is kept: the database tables keep their `es_jobs_` names, and personal lockers keep their containers. Saved settings move with one SQL line (README → Upgrading from es_jobs).
- The `es_jobs.admin` ace still works next to the new `whip_jobs.admin`.
- Items are now `whip_jobs_*` (breathalyzer, drug test, spike strip, first aid, medical bag); the names are in `config.lua`.
- whip_jobs will not start while the old es_jobs is still running.
- Use with es_mdt 2.4.2, which finds the job pack as whip_jobs or es_jobs.

## 0.4.0 (2026-11-20)

- **Courthouse spots for the DOJ**, set up like the police: court clerk window, courtroom (bailiff), judge's chambers / bench, District Attorney's office and public defender's office. Each has its own default ped (clerk, bailiff, judge, receptionist, lawyer), changeable with a picture in the station editor or in `/whip` → Settings → Jobs.
  - The clerk window (court services, pay a fine or fee), the courtroom (my cases) and the public defender's office (hire a lawyer, ask for a public defender) are open to everyone and open es_mdt's `/court` portal. DOJ staff get the DOJ tablet there and at the chambers and DA's office. No bail.
- **"Add the usual spots"** in the station editor: the standard set for the department type (police, EMS, DOJ, business), then each spot placed with the ghost in turn. es_mdt's New department page lists them and opens the editor right after creating.
- The courthouse spots are listed first for a DOJ station; "Courthouse" is a blip choice.
- es_mdt's old hard-coded clerk desk becomes a "Courthouse" station of the DOJ once (with its blip).
- New exports: `GetStarter(type)` (client), `HasSpotType(type)` (server).
- Needs es_mdt 2.4.0 for the courthouse spots.

## 0.3.0 (2026-11-19)

- **EMS:** wounded (yellow, 3 min, 1 min after a headshot; crawl, Call EMS with G / D-pad left, auto-call after 60 s; anyone with a first aid kit can help them up) and down (red, needs EMS; the same MDT call goes up to P1). Respawn waits while EMS units are attached to the call.
- Medics with a medical bag: examine, treat, revive. Each writes a medical record and bills the patient into the EMS department's account (unpaid bills stay open). Medical records tab; only leaders waive bills.
- **Hospital check-in** spot: treatment and paying bills; it pages an on-duty medic instead of healing when one is on.
- Timers and prices in `/whip` → Settings → Jobs → EMS. Needs es_mdt 2.2.2 for the call upgrade.

## 0.2.0 (2026-11-19)

- **Locker room uniforms:** made in WHIP's character editor (add-on clothing works), limited by rank, live preview on your character, changeable during a shift; your own clothes come back at clock-off and logout.
- **Police** (with es_jail's cuffs): put a cuffed person in a car and take them out into an escort; breathalyzer, drug swab, spike strips (two per officer, picked up again).
- **Impound clerk** spot: owners see their impounded cars and fees, pay by bank or cash, and the car is brought out to a parking space. Police holds can't be paid out. Needs es_mdt 2.2.1.
- The station editor moved into WHIP's admin menu (`/w` → Stations); the `/stations` command is gone.

## 0.1.0 (2026-11-19)

- **Stations** shared by departments and businesses, with blips for everyone, members or no one. Spots: duty, armory, locker, garage, helipad, boat dock. Placed with WHIP's ghost, "use my position" or teleport; blocked parking spaces are flagged.
- Peds from a picture grid (defaults by department type) or any model; they spawn only near players, frozen and invincible.
- History, undo, restore deleted stations, export and import.
- **Duty, armory, fleet** (by rank, one vehicle each, back at the garage or gone at clock-off) and **personal lockers**.
- **Pay by rank** from the job's bank account on an on-duty timer; missed paychecks are logged and leaders are told.
- **Businesses** (`/business`): player-owned jobs made like `/departments` with a name, colour and logo (live preview), ranks and pay, staff, and a bank account with a ledger.
- Settings in `/whip` → Settings → Jobs.
