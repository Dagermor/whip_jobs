// whip_jobs: the station editor (admin menu /w -> Stations, Departments -> Locations, /business). A station: a name, the departments and businesses that share it, a blip, and
// its spots. Spots are placed with WHIP's ghost (the ped itself, or the vehicle for a parking space), "my position" or
// typed in; each change is saved as a whole, with the previous version kept (undo, history, restore, backups).
(function () {
  'use strict';
  const { $, $$, esc, call, nui, toast, said, busy, modal, confirm, img, pedImg, vehImg, itemImg } = J;
  const E = { data: null, filter: null, cur: null, orig: '', sel: -1, warn: {} };
  const SPRITES = [[60, 'Police station'], [61, 'Hospital'], [436, 'Fire station'], [50, 'Garage'], [64, 'Helicopter'], [410, 'Boat'], [52, 'Shop'], [419, 'Courthouse']];
  const COLORS = [[0, '#f0f0f0'], [1, '#e13b3b'], [2, '#71cb71'], [3, '#5db6e5'], [5, '#eec64e'], [17, '#ef8a36'], [27, '#a855f7'], [29, '#2f5fb3'], [38, '#2b4c9b'], [40, '#5a5a5a']];
  const T = (k) => (E.data.types || []).find((t) => t.key === k) || { key: k, label: k, icon: '•' };
  const org = (jobId) => (E.data.orgs || []).find((o) => o.jobId === jobId);
  const dirty = () => E.cur && JSON.stringify(strip(E.cur)) !== E.orig;
  const strip = (c) => ({ name: c.name, jobs: c.jobs, blip: c.blip, spots: c.spots });
  const uid = () => 's' + Math.random().toString(36).slice(2, 8);
  const fmtP = (p) => (p && p.x != null) ? `${(+p.x).toFixed(1)}, ${(+p.y).toFixed(1)}, ${(+p.z).toFixed(1)} · ${Math.round(p.h || 0)}°` : 'not placed';

  // ---------------------------------------------------------------- list
  function renderList() {
    const f = $('#st-filter');
    const orgs = E.data.orgs.filter((o) => E.data.admin || o.mine);
    f.innerHTML = `<button class="fchip ${E.filter == null ? 'on' : ''}" data-f="">All</button>` +
      orgs.map((o) => `<button class="fchip ${E.filter === o.jobId ? 'on' : ''}" data-f="${o.jobId}">${esc(o.short || o.name)}</button>`).join('');
    $$('[data-f]', f).forEach((b) => b.onclick = () => { E.filter = b.dataset.f ? +b.dataset.f : null; renderList(); });
    const list = E.data.stations.filter((s) => E.filter == null || s.jobs.indexOf(E.filter) >= 0);
    const el = $('#st-list');
    el.innerHTML = list.length ? list.map((s) => `<div class="dept-item ${E.cur && E.cur.id === s.id ? 'on' : ''}" data-st="${s.id}" tabindex="0">
      <div class="di-text" style="flex:1"><div class="s">${esc(s.name)}</div>
      <div class="n">${s.spots.length} spot${s.spots.length === 1 ? '' : 's'} · ${s.jobs.map((j) => esc((org(j) || {}).short || '?')).join(', ') || '<span class="warn">nobody</span>'}${s.canEdit ? '' : ' · view only'}</div></div></div>`).join('')
      : '<div class="list-empty">No stations yet. Make one, then add its duty desk, armory and garage.</div>';
    $$('[data-st]', el).forEach((d) => d.onclick = () => pick(+d.dataset.st));
    $('#st-admin').classList.toggle('hidden', !E.data.admin);
  }

  async function guard() {
    if (!dirty()) return true;
    return confirm('Leave without saving?', 'This station has changes that are not saved yet.', 'Leave', true);
  }
  async function pick(id) {
    if (E.cur && E.cur.id === id) return;
    if (!(await guard())) return;
    const s = E.data.stations.find((x) => x.id === id);
    if (!s) return;
    E.cur = JSON.parse(JSON.stringify(s)); E.orig = JSON.stringify(strip(E.cur)); E.sel = E.cur.spots.length ? 0 : -1; E.warn = {};
    renderList(); renderMain();
  }
  async function newStation(jobId) {
    if (!(await guard())) return;
    const mine = E.data.orgs.filter((o) => E.data.admin || o.mine);
    const j = jobId || E.filter || (mine[0] && mine[0].jobId);
    E.cur = { id: null, rev: 0, name: '', jobs: j ? [j] : [], blip: { show: 'everyone', sprite: E.data.blipDefault.sprite, color: E.data.blipDefault.color }, spots: [], canEdit: true };
    E.orig = ''; E.sel = -1; E.warn = {};
    renderList(); renderMain();
    const n = $('#st-name'); if (n) n.focus();
  }

  // ---------------------------------------------------------------- the station
  function renderMain() {
    const m = $('#st-main');
    if (!E.cur) { m.innerHTML = '<div class="empty"><div class="empty-ico">📍</div><div class="empty-title">Pick a station, or make a new one.</div><div class="hint">A station is shared: LSPD and BCSO can use the same garage.</div></div>'; return; }
    const c = E.cur, ro = !c.canEdit, b = c.blip || {};
    const orgs = E.data.orgs;
    m.innerHTML = `
      <div class="st-head">
        <div class="field"><label>Station name</label><input type="text" id="st-name" maxlength="${E.data.limits.name}" value="${esc(c.name)}" placeholder="Mission Row PD" ${ro ? 'disabled' : ''}></div>
        <div class="field" style="flex:2"><label>Shared by</label><div class="chips" id="st-jobs">${orgs.map((o) => {
          const on = c.jobs.indexOf(o.jobId) >= 0, can = !ro && (E.data.admin || o.mine);
          return (on || can) ? `<button class="fchip ${on ? 'on' : ''}" data-job="${o.jobId}" ${can ? '' : 'disabled'}>${esc(o.short || o.name)}<span class="kind"> ${o.kind === 'biz' ? 'business' : esc(o.type)}</span></button>` : '';
        }).join('')}</div></div>
        <div class="field"><label>Blip</label><div class="row">
          <div class="seg" id="st-blip">${['everyone', 'members', 'none'].map((k) => `<button data-show="${k}" class="${(b.show || 'everyone') === k ? 'on' : ''}" ${ro ? 'disabled' : ''}>${{ everyone: 'Everyone', members: 'Members', none: 'Hidden' }[k]}</button>`).join('')}</div>
          <select id="st-sprite" ${ro || b.show === 'none' ? 'disabled' : ''}>${SPRITES.map(([v, l]) => `<option value="${v}" ${+b.sprite === v ? 'selected' : ''}>${l}</option>`).join('')}
            ${SPRITES.some(([v]) => v === +b.sprite) ? '' : `<option value="${+b.sprite}" selected>Sprite ${+b.sprite}</option>`}</select>
          <div class="swatches" id="st-color">${COLORS.map(([v, h]) => `<span class="sw ${+b.color === v ? 'on' : ''}" data-color="${v}" style="background:${h}" tabindex="0"></span>`).join('')}</div>
        </div></div>
      </div>
      <div class="st-body">
        <div class="st-spots"><div id="st-spotlist"></div>
          ${ro ? '' : '<div id="st-add"></div>'}
        </div>
        <div class="st-detail" id="st-detail"></div>
      </div>
      <div class="st-foot">
        <span id="st-dirty" class="hint"></span><span class="grow"></span>
        ${c.id ? `<button class="btn ghost" id="st-hist">History</button>` : ''}
        ${c.id && !ro ? `<button class="btn ghost" id="st-undo">Undo last save</button><button class="btn danger" id="st-del">Delete station</button>` : ''}
        ${ro ? '<span class="hint">View only: you do not lead any of its departments</span>' : '<button class="btn accent" id="st-save">Save station</button>'}
      </div>`;
    wireMain();
    renderSpots(); renderDetail(); markDirty();
  }

  function markDirty() {
    const d = $('#st-dirty'); if (!d) return;
    d.innerHTML = dirty() ? '<span class="dirty-dot"></span>Not saved' : (E.cur.id ? 'Saved' : '');
  }

  function wireMain() {
    const c = E.cur;
    const n = $('#st-name'); if (n) n.oninput = () => { c.name = n.value; markDirty(); };
    $$('[data-job]').forEach((b) => b.onclick = () => {
      const j = +b.dataset.job, i = c.jobs.indexOf(j);
      if (i >= 0) c.jobs.splice(i, 1); else c.jobs.push(j);
      b.classList.toggle('on', i < 0); markDirty(); renderDetail(); renderAdd();
    });
    $$('[data-show]').forEach((b) => b.onclick = () => { c.blip.show = b.dataset.show; renderMain(); });
    const sp = $('#st-sprite'); if (sp) sp.onchange = () => { c.blip.sprite = +sp.value; markDirty(); };
    $$('[data-color]').forEach((s) => s.onclick = () => { if (!c.canEdit) return; c.blip.color = +s.dataset.color; $$('[data-color]').forEach((x) => x.classList.toggle('on', x === s)); markDirty(); });

    const sv = $('#st-save'); if (sv) sv.onclick = () => busy(sv, save);
    const un = $('#st-undo'); if (un) un.onclick = () => busy(un, undo);
    const de = $('#st-del'); if (de) de.onclick = del;
    const hi = $('#st-hist'); if (hi) hi.onclick = history;
  }

  // ---------------------------------------------------------------- spots
  /** 0.4.0: the station's main kind (its first department's type, or business) */
  const kindOf = () => { const o = org(E.cur.jobs[0]); return o ? (o.kind === 'biz' ? 'business' : o.type) : null; };
  const isDoj = () => E.cur.jobs.some((j) => { const o = org(j); return o && o.type === 'doj'; });
  function addSpotHtml() {
    const btn = (t) => {
      const soon = (t.phase || 1) > E.data.phase;
      return `<button class="btn sm" data-add="${t.key}" ${soon ? 'disabled' : ''} title="${esc(t.hint)}">${t.icon} ${esc(t.label.split(':')[0])}${soon ? '<span class="soon">soon</span>' : ''}</button>`;
    };
    const types = E.data.types || [];
    const general = types.filter((t) => !t.doj), doj = types.filter((t) => t.doj);
    const groups = [['Any department', general], ['Courthouse (DOJ)', doj]];
    if (isDoj()) groups.reverse();   // a DOJ station: the courthouse spots first
    const set = (E.data.starter || {})[kindOf()] || [];
    const missing = set.filter((k) => !E.cur.spots.some((s) => s.type === k) && (T(k).phase || 1) <= E.data.phase);
    const unplaced = E.cur.spots.filter((s) => s.x == null).length;
    return `${missing.length ? `<button class="btn accent sm starter" data-starter title="${esc(missing.map((k) => T(k).label).join(', '))}">✨ Add the usual ${kindOf() === 'doj' ? 'DOJ' : ''} spots (${missing.length})</button>` : ''}
      ${unplaced > 1 ? `<button class="btn sm starter" data-placeall>👻 Place the ${unplaced} unplaced spots, one after another</button>` : ''}
      ${groups.filter((g) => g[1].length).map(([l, list]) => `<div class="lbl" style="margin-top:12px">Add a spot: ${l}</div><div class="add-spot">${list.map(btn).join('')}</div>`).join('')}`;
  }
  function defaultPed(t) {
    if (!t.ped) return false;
    const tp = (E.data.typePeds || {})[t.key];
    if (tp) return tp;
    const o = org(E.cur.jobs[0]);
    return (o && o.ped) || 's_m_m_security_01';
  }
  function newSpot(type) {
    const t = T(type);
    const s = { id: uid(), type, label: t.label.split(':')[0], ped: defaultPed(t) };
    if (t.stock) s.stock = [];
    if (t.spawns) { s.vehicles = []; s.spawns = []; }
    return s;
  }
  /** the usual set for this kind of station, then each one placed with the ghost in turn (cancel stops) */
  async function addStarter() {
    const set = (E.data.starter || {})[kindOf()] || [];
    const missing = set.filter((k) => !E.cur.spots.some((s) => s.type === k) && (T(k).phase || 1) <= E.data.phase);
    const room = E.data.limits.spots - E.cur.spots.length;
    if (!missing.length) return;
    if (missing.length > room) { toast(`A station has ${E.data.limits.spots} spots at most`, 'err'); return; }
    missing.forEach((k) => E.cur.spots.push(newSpot(k)));
    E.sel = E.cur.spots.length - missing.length;
    renderMain();
    toast(`${missing.length} spots added. Place each one with the ghost (Backspace / B stops).`, 'ok');
    placeAll();
  }
  async function placeAll() {
    for (;;) {
      const i = E.cur.spots.findIndex((x) => x.x == null);
      if (i < 0) { renderMain(); toast('Every spot is placed. Save the station to keep them.', 'ok'); return; }
      E.sel = i; renderSpots(); renderDetail();
      if (!(await place(E.cur.spots[i], true))) { renderMain(); return; }
    }
  }
  function addSpot(type) {
    const t = T(type);
    if (E.cur.spots.length >= E.data.limits.spots) { toast(`A station has ${E.data.limits.spots} spots at most`, 'err'); return; }
    const s = newSpot(type);
    E.cur.spots.push(s); E.sel = E.cur.spots.length - 1;
    renderSpots(); renderDetail(); markDirty();
    place(s, false);   // straight into placing it
  }
  function renderSpots() {
    const el = $('#st-spotlist'); if (!el) return;
    const c = E.cur;
    el.innerHTML = c.spots.length ? c.spots.map((s, i) => {
      const t = T(s.type), placed = s.x != null;
      return `<div class="spot ${i === E.sel ? 'on' : ''} ${placed ? '' : 'bad'}" data-spot="${i}" tabindex="0">
        <div class="ico">${t.icon}</div>
        <div class="t"><b>${esc(s.label || t.label)}</b><span>${placed ? esc(t.label.split(':')[0]) : '<span class="err">not placed yet</span>'}${t.spawns ? ` · ${(s.spawns || []).length} spaces${t.fleet ? `, ${(s.vehicles || []).length} vehicles` : ''}` : ''}${t.stock ? ` · ${(s.stock || []).length} items` : ''}</span></div>
        ${s.ped ? img(pedImg(s.ped), 'pedthumb', '👤') : ''}</div>`;
    }).join('') : '<div class="list-empty">No spots yet. Add a duty desk first.</div>';
    $$('[data-spot]', el).forEach((d) => d.onclick = () => { E.sel = +d.dataset.spot; renderSpots(); renderDetail(); });
    renderAdd();
  }
  function renderAdd() {
    const a = $('#st-add'); if (!a) return;
    a.innerHTML = addSpotHtml();
    $$('[data-add]', a).forEach((b) => b.onclick = () => addSpot(b.dataset.add));
    const stb = $('[data-starter]', a); if (stb) stb.onclick = addStarter;
    const pab = $('[data-placeall]', a); if (pab) pab.onclick = placeAll;
  }

  /** ranks of the station's departments, for "who may take this" */
  function rankOptions(cur) {
    const seen = {}, out = [[0, 'Anyone on duty']];
    E.cur.jobs.forEach((j) => { const o = org(j); (o && o.ranks || []).forEach((r) => {
      const k = r.level + ':' + r.name; if (seen[k] || r.level <= 0) return; seen[k] = 1; out.push([r.level, `${r.name} (${o.short}) · ${r.level}+`]); }); });
    out.sort((a, b) => a[0] - b[0]);
    if (!out.some((o) => o[0] === +cur)) out.push([+cur, `Level ${+cur}+`]);
    return out.map(([v, l]) => `<option value="${v}" ${+cur === v ? 'selected' : ''}>${esc(l)}</option>`).join('');
  }

  function renderDetail() {
    const el = $('#st-detail'); if (!el) return;
    const s = E.cur.spots[E.sel], ro = !E.cur.canEdit;
    if (!s) { el.innerHTML = '<div class="empty"><div class="hint">Pick a spot on the left, or add one.</div></div>'; return; }
    const t = T(s.type);
    const peds = E.data.pedList || [];
    let h = `<div class="card"><div class="card-head"><div class="card-title">${t.icon} ${esc(t.label)}</div>
        ${ro ? '' : `<div class="row"><button class="btn sm ghost" data-up ${E.sel === 0 ? 'disabled' : ''}>▲</button><button class="btn sm danger" data-delspot>Remove spot</button></div>`}</div>
      <p class="hint">${esc(t.hint)}</p>
      <div class="grid" style="margin-top:12px"><div class="field"><label>Name on the prompt</label><input type="text" id="sp-label" maxlength="${E.data.limits.label}" value="${esc(s.label)}" ${ro ? 'disabled' : ''}></div>
      <div class="field"><label>Where</label><div class="coords" style="padding:8px 0">${s.x != null ? esc(fmtP(s)) : '<span class="err">Not placed: place it before saving</span>'}</div></div></div>
      ${ro ? '' : `<div class="place-bar"><button class="btn accent" data-place>👻 Place with ghost</button><button class="btn" data-mypos>📍 Use my position</button>`}
      ${s.x != null ? `<button class="btn ghost" data-go>➜ Go there</button>` : ''}${ro ? '' : '</div><p class="hint">Ghost: move with the mouse or sticks, turn it, <b>E / A</b> to place, <b>Backspace / B</b> to cancel.</p>'}
    </div>`;
    // the ped
    h += `<div class="card"><div class="card-head"><div class="card-title">Ped</div>${ro ? '' : `<label class="switch"><input type="checkbox" id="sp-hasped" ${s.ped ? 'checked' : ''}><span></span> A ped stands here</label>`}</div>`;
    if (s.ped) {
      const known = peds.find((p) => p.model === s.ped);
      h += `<div class="ped-big">${img(pedImg(s.ped), '', '👤')}<div><b>${esc(known ? known.label : 'Custom model')}</b><div class="coords">${esc(s.ped)}</div>
        ${ro ? '' : `<div class="field" style="margin-top:10px"><label>Any other ped model</label><div class="row"><input type="text" id="sp-pedtxt" maxlength="48" value="${esc(s.ped)}" placeholder="s_m_y_cop_01" data-pad-predict="false"><button class="btn sm" id="sp-pedset">Use</button></div></div>`}</div></div>
        ${ro ? '' : `<div class="lbl" style="margin:14px 0 6px">Pick one (the picture is what stands there)</div><div class="ped-grid">${peds.map((p) => `<div class="ped-opt ${p.model === s.ped ? 'on' : ''}" data-ped="${esc(p.model)}" tabindex="0">${img(pedImg(p.model), '', '👤')}${esc(p.label)}</div>`).join('')}</div>`}`;
    } else h += '<p class="hint">No ped: just a prompt at the spot (a locker, a sign, a helipad).</p>';
    h += '</div>';
    if (t.stock) h += stockCard(s, ro);
    if (t.spawns) h += (t.fleet ? vehCard(s, ro) : '') + spawnCard(s, ro, t);
    el.innerHTML = h;
    wireDetail(s, t);
  }

  function stockCard(s, ro) {
    const items = E.data.items || [];
    const by = {}; items.forEach((i) => by[i.key] = i);
    return `<div class="card"><div class="card-head"><div class="card-title">Stock <span class="hint">(issued free; rank needed and the most one person may carry)</span></div>
      ${ro ? '' : '<button class="btn sm" data-addstock>＋ Item</button>'}</div>
      <datalist id="dl-items">${items.map((i) => `<option value="${esc(i.key)}">${esc(i.label)}</option>`).join('')}</datalist>
      <div class="rows">${(s.stock || []).map((it, i) => {
        const d = by[it.item];
        return `<div class="rrow stock">${d ? img(itemImg(it.item, d.img), 'it', (d.label || '?').slice(0, 1)) : '<div class="it">?</div>'}
          <div><input type="text" list="dl-items" data-si="${i}" data-k="item" value="${esc(it.item)}" placeholder="item key" ${ro ? 'disabled' : ''} data-pad-predict="false">
          <div class="${d ? 'hint' : 'err'}">${d ? esc(d.label) : (it.item ? 'Not an item on this server' : 'Pick an item')}</div></div>
          <select data-si="${i}" data-k="min" ${ro ? 'disabled' : ''}>${rankOptions(it.min || 0)}</select>
          <input type="number" min="1" max="${E.data.armoryMax}" data-si="${i}" data-k="max" value="${+it.max || 1}" title="Most one person may carry" ${ro ? 'disabled' : ''}>
          ${ro ? '' : `<button class="btn sm ghost" data-delstock="${i}">✕</button>`}</div>`;
      }).join('') || '<div class="list-empty">Nothing stocked yet.</div>'}</div></div>`;
  }

  function vehCard(s, ro) {
    return `<div class="card"><div class="card-head"><div class="card-title">Vehicles <span class="hint">(by rank)</span></div>${ro ? '' : '<button class="btn sm" data-addveh>＋ Vehicle</button>'}</div>
      <div class="rows">${(s.vehicles || []).map((v, i) => `<div class="rrow veh">${img(vehImg(v.model), 'vh', '🚗')}
        <input type="text" data-vi="${i}" data-k="model" value="${esc(v.model)}" placeholder="model (police3)" ${ro ? 'disabled' : ''} data-pad-predict="false">
        <input type="text" data-vi="${i}" data-k="label" value="${esc(v.label)}" placeholder="Name shown" maxlength="40" ${ro ? 'disabled' : ''}>
        <select data-vi="${i}" data-k="min" ${ro ? 'disabled' : ''}>${rankOptions(v.min || 0)}</select>
        <input type="number" min="-1" max="60" data-vi="${i}" data-k="livery" value="${v.livery == null ? -1 : v.livery}" title="Livery (-1: as it comes)" ${ro ? 'disabled' : ''}>
        ${ro ? '' : `<button class="btn sm ghost" data-delveh="${i}">✕</button>`}</div>`).join('') || '<div class="list-empty">No vehicles yet.</div>'}</div></div>`;
  }

  function spawnCard(s, ro, t) {
    return `<div class="card"><div class="card-head"><div class="card-title">${t.spawns === 'boat' ? 'Boat moorings' : t.spawns === 'heli' ? 'Landing pads' : 'Parking spaces'} <span class="hint">(where they come out)</span></div>
      ${ro ? '' : '<div class="row"><button class="btn sm" data-addspawn>＋ Place with ghost</button><button class="btn sm ghost" data-addspawnpos>＋ Where I am / my car is</button></div>'}</div>
      <div class="rows">${(s.spawns || []).map((p, i) => {
        const w = E.warn[s.id + ':' + i];
        return `<div class="rrow spawn"><b class="num">${i + 1}</b><div><div class="coords">${esc(fmtP(p))}</div>
          ${w == null ? '' : (w.length ? w.map((x) => `<div class="warn">⚠ ${esc(x)}</div>`).join('') : '<div class="okc">✓ Clear</div>')}</div>
          <div class="row">${ro ? '' : `<button class="btn sm ghost" data-movespawn="${i}">Move</button>`}<button class="btn sm ghost" data-gospawn="${i}">Go</button>
          <button class="btn sm ghost" data-checkspawn="${i}">Check</button>${ro ? '' : `<button class="btn sm ghost" data-delspawn="${i}">✕</button>`}</div></div>`;
      }).join('') || '<div class="list-empty">No spaces yet: vehicles cannot come out until you add one.</div>'}</div></div>`;
  }

  function wireDetail(s, t) {
    const el = $('#st-detail');
    const changed = () => { markDirty(); renderSpots(); };
    const lab = $('#sp-label'); if (lab) lab.oninput = () => { s.label = lab.value; changed(); };
    const q = (sel, fn) => $$(sel, el).forEach((b) => b.onclick = () => fn(b));
    q('[data-place]', () => place(s, true));
    q('[data-mypos]', async () => { const r = await nui('esj_myPos'); if (r && r.ok) { Object.assign(s, r.point); changed(); renderDetail(); } });
    q('[data-go]', () => go(s));
    q('[data-delspot]', async () => { if (await confirm('Remove this spot?', `${s.label || t.label} goes when you save.`, 'Remove', true)) { E.cur.spots.splice(E.sel, 1); E.sel = Math.min(E.sel, E.cur.spots.length - 1); changed(); renderDetail(); } });
    q('[data-up]', () => { const i = E.sel; const a = E.cur.spots; [a[i - 1], a[i]] = [a[i], a[i - 1]]; E.sel = i - 1; changed(); renderDetail(); });
    const hp = $('#sp-hasped'); if (hp) hp.onchange = () => { s.ped = hp.checked ? (defaultPed({ ped: true, key: t.key })) : false; changed(); renderDetail(); };
    q('[data-ped]', (b) => { s.ped = b.dataset.ped; changed(); renderDetail(); });
    const ps = $('#sp-pedset'); if (ps) ps.onclick = () => { const v = $('#sp-pedtxt').value.trim(); if (!/^[\w]{1,48}$/.test(v)) { toast('A ped model is letters, digits and _', 'err'); return; } s.ped = v; changed(); renderDetail(); };
    // stock
    q('[data-addstock]', () => { if ((s.stock || []).length >= E.data.limits.stock) return; s.stock.push({ item: '', min: 0, max: 1 }); changed(); renderDetail(); });
    q('[data-delstock]', (b) => { s.stock.splice(+b.dataset.delstock, 1); changed(); renderDetail(); });
    $$('[data-si]', el).forEach((inp) => inp.onchange = () => {
      const it = s.stock[+inp.dataset.si], k = inp.dataset.k;
      it[k] = k === 'item' ? inp.value.trim() : Math.max(k === 'max' ? 1 : 0, Math.min(k === 'max' ? E.data.armoryMax : 100, +inp.value || 0));
      changed(); if (k === 'item') renderDetail();
    });
    // vehicles
    q('[data-addveh]', () => { if ((s.vehicles || []).length >= E.data.limits.vehicles) return; s.vehicles.push({ model: '', label: '', min: 0, livery: -1 }); changed(); renderDetail(); });
    q('[data-delveh]', (b) => { s.vehicles.splice(+b.dataset.delveh, 1); changed(); renderDetail(); });
    $$('[data-vi]', el).forEach((inp) => inp.onchange = () => {
      const v = s.vehicles[+inp.dataset.vi], k = inp.dataset.k;
      v[k] = (k === 'model' || k === 'label') ? inp.value.trim() : +inp.value;
      if (k === 'model' && !v.label) v.label = v.model;
      changed(); if (k === 'model') renderDetail();
    });
    // parking spaces
    q('[data-addspawn]', () => placeSpawn(s, t, -1));
    q('[data-addspawnpos]', async () => { const r = await nui('esj_myPos'); if (r && r.ok) { s.spawns.push(r.point); changed(); check(s, t, s.spawns.length - 1); } });
    q('[data-movespawn]', (b) => placeSpawn(s, t, +b.dataset.movespawn));
    q('[data-gospawn]', (b) => go(s.spawns[+b.dataset.gospawn]));
    q('[data-checkspawn]', (b) => check(s, t, +b.dataset.checkspawn));
    q('[data-delspawn]', (b) => { s.spawns.splice(+b.dataset.delspawn, 1); E.warn = {}; changed(); renderDetail(); });
  }

  async function place(s, msgOnCancel) {
    const r = await nui('esj_place', { model: s.ped || null, x: s.x, y: s.y, z: s.z, h: s.h, label: s.label, station: E.cur.id || 0, spot: s.id });
    if (r && r.ok) { Object.assign(s, r.point); markDirty(); renderSpots(); renderDetail(); toast('Placed. Save the station to keep it.', 'ok'); return true; }
    if (msgOnCancel || (r && r.why !== 'cancelled')) toast(r && r.why === 'cancelled' ? 'Not moved' : ((r && r.why) || 'Could not place it'), r && r.why === 'cancelled' ? '' : 'err');
    return false;
  }
  async function placeSpawn(s, t, i) {
    if (i < 0 && s.spawns.length >= E.data.limits.spawns) { toast(`${E.data.limits.spawns} spaces at most`, 'err'); return; }
    const v = (s.vehicles || []).find((x) => x.model) || { model: t.spawns === 'heli' ? 'polmav' : t.spawns === 'boat' ? 'predator' : 'police' };
    const at = i >= 0 ? s.spawns[i] : (s.spawns[s.spawns.length - 1] || s);
    const r = await nui('esj_place', { vehicle: true, model: v.model, x: at.x, y: at.y, z: at.z, h: at.h, label: 'Parking space' });
    if (!(r && r.ok)) { if (r && r.why !== 'cancelled') toast(r.why || 'Could not place it', 'err'); return; }
    if (i >= 0) s.spawns[i] = r.point; else s.spawns.push(r.point);
    markDirty(); renderSpots(); check(s, t, i >= 0 ? i : s.spawns.length - 1);
  }
  async function check(s, t, i) {
    const p = s.spawns[i]; if (!p) return;
    const r = await nui('esj_checkSpawn', Object.assign({ kind: t.spawns }, p));
    E.warn[s.id + ':' + i] = r && r.ok ? (r.far ? ['Too far away to check: go nearer'] : r.warn) : ['Could not check'];
    renderDetail();
  }
  async function go(p) {
    if (!p || p.x == null) return;
    const r = await nui('esj_teleport', { station: E.cur.id || 0, x: p.x, y: p.y, z: p.z, h: p.h });
    if (!(r && r.ok)) toast((r && r.why) || 'Could not go there', 'err');
  }

  // ---------------------------------------------------------------- save, undo, history, delete
  function problems() {
    const c = E.cur;
    if ((c.name || '').trim().length < 2) return 'Name the station';
    const onlyPublic = c.spots.length > 0 && c.spots.every((s) => T(s.type).public);
    if (!c.jobs.length && !(onlyPublic && E.data.admin)) return 'Pick at least one department or business (a station of only impound or hospital spots needs none)';
    const i = c.spots.findIndex((s) => s.x == null);
    if (i >= 0) { E.sel = i; renderSpots(); renderDetail(); return `"${c.spots[i].label}" is not placed yet`; }
    for (const s of c.spots) {
      if ((s.stock || []).some((x) => !x.item)) return `${s.label}: an item row is empty`;
      if ((s.vehicles || []).some((x) => !x.model)) return `${s.label}: a vehicle row has no model`;
    }
    return null;
  }
  async function save() {
    const p = problems(); if (p) { toast(p, 'err'); return; }
    const c = E.cur;
    const r = await call('whip_jobs:st:save', { id: c.id, rev: c.rev, name: c.name, jobs: c.jobs, blip: c.blip, spots: c.spots });
    if (!said(r, 'Station saved')) return;
    c.id = r.data.id; c.rev = r.data.rev; c.spots = r.data.spots;
    E.orig = JSON.stringify(strip(c));
    await reload(c.id);
  }
  async function undo() {
    if (dirty() && !(await confirm('Undo the last save?', 'Your unsaved changes go too.', 'Undo', true))) return;
    const r = await call('whip_jobs:st:undo', { id: E.cur.id });
    if (!said(r, 'Back to the version before the last save')) return;
    await reload(E.cur.id, true);
  }
  async function del() {
    const c = E.cur;
    if (!(await confirm('Delete this station?', `${c.name}: its peds, prompts and blip go for everyone. An admin can bring it back from Deleted.`, 'Delete', true))) return;
    const r = await call('whip_jobs:st:delete', { id: c.id });
    if (!said(r, 'Station deleted')) return;
    E.cur = null; await reload();
  }
  async function history() {
    const r = await call('whip_jobs:st:history', { id: E.cur.id });
    if (!said(r)) return;
    const rows = r.data || [];
    modal(`<h2>History: ${esc(E.cur.name)}</h2><div class="hist">${rows.map((h) => `<div class="h"><div class="t"><b>${esc(h.action)}</b><span>${esc(h.who)} · ${J.ago(h.at)} · ${h.spots} spots</span></div>
      ${E.cur.canEdit ? `<button class="btn sm" data-restore="${h.id}">Restore this</button>` : ''}</div>`).join('') || '<div class="list-empty">No earlier versions yet.</div>'}</div>
      <div class="row end"><button class="btn" data-m="x">Close</button></div>`, (c, done) => {
      $$('[data-restore]', c).forEach((b) => b.onclick = () => busy(b, async () => {
        const x = await call('whip_jobs:st:restore', { historyId: +b.dataset.restore });
        if (said(x, 'Restored')) { done(); await reload(x.data.id, true); }
      }));
    });
  }
  async function reload(selectId, force) {
    const r = await call('whip_jobs:st:list', {});
    if (!r.ok) { said(r); return; }
    E.data = r.data;
    if (selectId) { const keepSel = E.sel; if (force || !E.cur || E.cur.id !== selectId) E.cur = null; await pick(selectId); if (E.cur && keepSel >= 0 && keepSel < E.cur.spots.length) { E.sel = keepSel; renderSpots(); renderDetail(); } }
    else { renderList(); renderMain(); }
  }

  // ---------------------------------------------------------------- backups (admins)
  async function exportAll() {
    const r = await call('whip_jobs:st:export', {});
    if (!said(r)) return;
    const text = JSON.stringify(r.data, null, 1);
    modal(`<h2>Station backup</h2><p class="hint">${r.data.stations.length} stations. Copy this and keep it somewhere safe; Restore backup puts it back.</p>
      <textarea readonly id="bk-text">${esc(text)}</textarea><div class="row end"><button class="btn" id="bk-copy">Copy</button><button class="btn accent" data-m="x">Done</button></div>`, (c) => {
      $('#bk-copy', c).onclick = () => { const t = $('#bk-text', c); t.select(); try { document.execCommand('copy'); toast('Copied', 'ok'); } catch (e) { toast('Select it and press Ctrl+C', ''); } };
    });
  }
  async function importAll() {
    modal(`<h2>Restore a backup</h2><p class="hint">Paste a backup. Stations with the same number are replaced (what they are now stays in their history); the others are added.</p>
      <textarea id="im-text" placeholder='{"whip_jobs":"0.1","stations":[...]}'></textarea><div class="row end"><button class="btn ghost" data-m="x">Cancel</button><button class="btn accent" id="im-go">Restore</button></div>`, (c, done) => {
      $('#im-go', c).onclick = (e) => busy(e.currentTarget, async () => {
        const r = await call('whip_jobs:st:import', { text: $('#im-text', c).value });
        if (said(r, `${r.data && r.data.count} stations restored`)) { done(); E.cur = null; await reload(); }
      });
    });
  }
  async function deleted() {
    const rows = E.data.deleted || [];
    modal(`<h2>Deleted stations</h2><div class="hist">${rows.map((h) => `<div class="h"><div class="t"><b>${esc(h.name)}</b><span>#${h.stationId} · deleted ${J.ago(h.at)}</span></div>
      <button class="btn sm" data-back="${h.id}">Bring back</button></div>`).join('') || '<div class="list-empty">Nothing deleted.</div>'}</div><div class="row end"><button class="btn" data-m="x">Close</button></div>`, (c, done) => {
      $$('[data-back]', c).forEach((b) => b.onclick = () => busy(b, async () => {
        const r = await call('whip_jobs:st:restore', { historyId: +b.dataset.back });
        if (said(r, 'Station is back')) { done(); await reload(r.data.id, true); }
      }));
    });
  }

  $('#st-new').onclick = () => newStation();
  $('#st-export').onclick = exportAll;
  $('#st-import').onclick = importAll;
  $('#st-deleted').onclick = deleted;

  J.views.stations = {
    open: (d) => {
      E.data = d; E.cur = null; E.filter = d.focusJob || null;
      renderList(); renderMain();
      const first = (d.focusStation && E.data.stations.find((s) => s.id === d.focusStation))
        || E.data.stations.find((s) => E.filter == null || s.jobs.indexOf(E.filter) >= 0);
      if (d.startNew) newStation(d.focusJob).then(() => { if (d.startStarter && E.cur && !E.cur.id) addStarter(); });
      else if (first) pick(first.id);
    },
    back: () => {
      if (dirty() && !E.leaving) {
        confirm('Close without saving?', 'This station has changes that are not saved yet.', 'Close', true).then((y) => { if (y) { E.leaving = true; E.cur = null; J.close(); E.leaving = false; } });
        return true;
      }
      return false;
    },
    pad: { keys: [['Esc', 'Close']] },
  };
  J.stations = { open: async (jobId) => { const r = await call('whip_jobs:st:list', {}); if (!said(r)) return; r.data.focusJob = jobId; J.show('stations', r.data); } };
})();
