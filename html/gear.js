// es_jobs: a station spot on screen. Duty desk (clock on / off per department or business, the next paycheck),
// armory (equipment by rank, take and hand back), fleet garage (vehicles by rank, one each), impound clerk (pay, collect).
(function () {
  'use strict';
  const { $, esc, call, said, busy, money, img, itemImg, vehImg } = J;
  const ICON = { duty: '⏱', armory: '🛡', garage: '🚓', helipad: '🚁', boatdock: '⚓', impound: 'Ⓟ', hospital: '✚' };
  let D = null;

  const head = () => `<div class="sp-head"><div class="ico">${ICON[D.type] || '•'}</div>
    <div class="t"><b>${esc(D.label)}</b><span>${esc(D.station)}${D.onDuty ? ' · on duty' : ''}</span></div>
    <button class="btn icon" data-close title="Close">✕</button></div>`;

  function render() {
    const el = $('#v-spot');
    let body = '';
    if (D.type === 'hospital' && J.hosp) {   // ems.js: treatment, bills, medical records
      el.innerHTML = head() + '<div class="sp-body"></div>';
      J.hosp.open(el, D, where);
      return;
    }
    if (D.type === 'duty') body = duty();
    else if (D.type === 'armory') body = armory();
    else if (D.type === 'impound') body = impound();
    else body = garage();
    el.innerHTML = head() + `<div class="sp-body fade-in">${body}</div>`;
    wire(el);
  }

  function duty() {
    if (!D.jobs.length) return '<div class="list-empty">You do not work for anyone at this station.</div>';
    return D.jobs.map((j) => {
      const pct = Math.min(100, Math.round((j.payMin / Math.max(1, j.payEvery)) * 100));
      const left = Math.max(0, j.payEvery - j.payMin);
      return `<div class="duty-card ${j.onDuty ? 'on' : ''}">
        ${J.logoHtml({ kind: j.kind, id: j.orgId, short: j.short, name: j.name, color: '#334155' }, '')}
        <div class="t"><b>${esc(j.name)}</b><span class="hint">${esc(j.rank || '')}${j.payOn ? ` · ${money(j.pay)} every ${j.payEvery} min on duty` : ''}</span>
          ${j.onDuty && j.payOn ? `<div class="bar"><i style="width:${pct}%"></i></div><span class="hint">Next paycheck in ${left} min</span>` : ''}</div>
        <span class="pill ${j.onDuty ? 'on' : 'off'}">${j.onDuty ? 'On duty' : 'Off duty'}</span>
        <button class="btn ${j.onDuty ? '' : 'accent'}" data-duty="${j.jobId}" data-on="${j.onDuty ? 0 : 1}">${j.onDuty ? 'Clock off' : 'Clock on'}</button>
      </div>`;
    }).join('');
  }

  function armory() {
    let out = D.onDuty ? '' : '<div class="banner warn">⚠ Clock on to take equipment. You can still hand things back.</div>';
    if (!D.items.length) return out + '<div class="list-empty">This armory has nothing stocked yet. A leader adds stock in the station editor.</div>';
    out += '<div class="gear-grid">' + D.items.map((it) => `<div class="gear ${it.allowed ? '' : 'locked'}">
      ${it.allowed ? '' : '<span class="lock">🔒 rank ' + esc(it.min) + '+</span>'}
      <div class="img">${img(itemImg(it.item, it.img), '', (it.label || '?').slice(0, 1))}</div>
      <b>${esc(it.label)}</b><span class="meta">You carry ${it.have} / ${it.max}</span>
      <div class="row"><button class="btn small accent" data-take="${esc(it.item)}" ${it.allowed && it.have < it.max ? '' : 'disabled'}>Take</button>
      <button class="btn small ghost" data-ret="${esc(it.item)}" ${it.have > 0 ? '' : 'disabled'}>Hand back</button></div></div>`).join('') + '</div>';
    return out;
  }

  function garage() {
    let out = '';
    if (!D.onDuty) out += '<div class="banner warn">⚠ Clock on to take a vehicle.</div>';
    if (D.mine) out += `<div class="banner ok">🚓 Your ${esc(D.mine.label)} (${esc(D.mine.plate)}) is out. Drive it back here and press the prompt to put it away.</div>`;
    if (!D.spawns) out += '<div class="banner warn">⚠ This garage has no parking spaces yet. A leader adds them in the station editor.</div>';
    if (!D.vehicles.length) return out + '<div class="list-empty">No vehicles here yet. A leader adds them in the station editor.</div>';
    out += '<div class="gear-grid">' + D.vehicles.map((v) => `<div class="gear veh ${v.allowed ? '' : 'locked'}">
      ${v.allowed ? '' : '<span class="lock">🔒 rank ' + esc(v.min) + '+</span>'}
      <div class="img">${img(vehImg(v.model, v.img), '', '🚗')}</div>
      <b>${esc(v.label)}</b><span class="meta">${esc(v.class || v.model)}</span>
      <div class="row"><button class="btn small accent" data-veh="${esc(v.model)}" ${v.allowed && !D.mine && D.spawns ? '' : 'disabled'}>Take out</button></div></div>`).join('') + '</div>';
    return out;
  }

  function impound() {
    const STATUS = { held: 'At the impound lot', pending: 'On its way to the lot', released: 'Released: ready to collect' };
    if (!D.cars.length) return '<div class="list-empty">🅿 None of your vehicles are impounded.</div>';
    let out = D.spawns ? '' : '<div class="banner warn">⚠ This clerk has no parking spaces yet: pay here, collect at the lot.</div>';
    out += '<div class="imp-list">' + D.cars.map((c) => {
      const hold = c.held ? (c.holdUntil ? `Police hold until ${new Date(c.holdUntil * 1000).toLocaleString([], { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}` : 'Police hold: an officer must release it') : '';
      const bill = c.status === 'held' ? `<div class="imp-bill"><span>Impound fee</span><b>${money(c.fee)}</b>${c.storage ? `<span>Storage (${c.days} day${c.days === 1 ? '' : 's'})</span><b>${money(c.storage)}</b>` : ''}<span class="tot">Total</span><b class="tot">${money(c.owe)}</b></div>` : '';
      const pay = c.canPay ? D.methods.map((m, i) => `<button class="btn ${i === 0 ? 'accent' : ''}" data-pay="${c.id}" data-m="${m}">Pay ${money(c.owe)} · ${m === 'cash' ? 'cash' : 'bank'}</button>`).join('') : '';
      const take = c.canTake ? `<button class="btn accent" data-takeout="${c.id}">Bring it out</button>` : '';
      return `<div class="imp-card ${c.status}">
        <div class="img">${img(vehImg(c.model, c.img), '', '🚗')}</div>
        <div class="imp-t"><b>${esc(c.label)}</b><span class="plate">${esc(c.plate || '')}</span>
          <span class="pill ${c.status === 'released' ? 'on' : ''}">${esc(STATUS[c.status] || c.status)}</span>
          <span class="hint">${esc(c.reason || '')}${c.dept ? ' · ' + esc(c.dept) : ''}${c.lot ? ' · ' + esc(c.lot) : ''}</span>
          ${hold ? `<span class="hint warn">🔒 ${esc(hold)}</span>` : ''}${bill}
          <div class="row">${pay}${take}</div></div></div>`;
    }).join('') + '</div>';
    return out;
  }

  const where = () => ({ station: D.stationId, spot: D.spot });
  async function reload() {
    const r = await call('es_jobs:spot:open', where());
    if (r.ok) { D = r.data; render(); } else said(r);
  }

  function wire(el) {
    J.fillLogos(el, (D.jobs || []).map((j) => ({ kind: j.kind, id: j.orgId, logoVer: j.logoVer, short: j.short })));
    el.querySelectorAll('[data-duty]').forEach((b) => b.onclick = () => busy(b, async () => {
      const on = b.dataset.on === '1';
      const r = await call('es_jobs:duty', Object.assign(where(), { jobId: +b.dataset.duty, on }));
      if (said(r)) reload();
    }));
    el.querySelectorAll('[data-take]').forEach((b) => b.onclick = () => busy(b, async () => {
      const r = await call('es_jobs:armory:take', Object.assign(where(), { item: b.dataset.take, n: 1 }));
      if (said(r)) { D.items.find((x) => x.item === b.dataset.take).have = r.data.have; render(); }
    }));
    el.querySelectorAll('[data-ret]').forEach((b) => b.onclick = () => busy(b, async () => {
      const r = await call('es_jobs:armory:return', Object.assign(where(), { item: b.dataset.ret, n: 1 }));
      if (said(r)) { D.items.find((x) => x.item === b.dataset.ret).have = r.data.have; render(); }
    }));
    el.querySelectorAll('[data-pay]').forEach((b) => b.onclick = () => busy(b, async () => {
      const r = await call('es_jobs:imp:pay', Object.assign(where(), { id: +b.dataset.pay, method: b.dataset.m }));
      if (said(r, 'Paid: it is released')) reload();
    }));
    el.querySelectorAll('[data-takeout]').forEach((b) => b.onclick = () => busy(b, async () => {
      const r = await call('es_jobs:imp:take', Object.assign(where(), { id: +b.dataset.takeout }));
      if (said(r, `${r.data && r.data.label} is out front`)) J.close();
    }));
    el.querySelectorAll('[data-veh]').forEach((b) => b.onclick = () => busy(b, async () => {
      const r = await call('es_jobs:fleet:take', Object.assign(where(), { model: b.dataset.veh }));
      if (said(r, `${r.data && r.data.label} is out front (${r.data && r.data.plate})`)) J.close();
    }));
  }

  J.views.spot = { open: (d) => { D = d; render(); }, back: () => D && D.type === 'hospital' && J.hosp && J.hosp.back(), pad: { keys: [['Esc', 'Close']] } };
})();
