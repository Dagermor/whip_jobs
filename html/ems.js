// whip_jobs 0.3.0: EMS on the page. The hurt chip (wounded: yellow, down: red), drawn without focus, and the hospital desk
// (treatment, bills, and medical records for EMS on duty) inside the station spot view (gear.js hands it over).
(function () {
  'use strict';
  const { $, esc, call, said, busy, money, ago } = J;

  // ---------------------------------------------------------------- the chip
  const chip = document.createElement('div');
  chip.id = 'esj-hurt'; chip.className = 'hurt-chip hidden';
  document.body.appendChild(chip);
  const mmss = (s) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  function drawChip(m) {
    if (!m.state || m.state === 'none') { chip.classList.add('hidden'); return; }
    const key = m.pad ? (window.ESPad ? window.ESPad.glyph('dpad_left') : '◀') : '<kbd>G</kbd>';
    const units = m.units > 0 ? `<span class="hc-units">🚑 ${m.units} unit${m.units === 1 ? '' : 's'} responding</span>` : '';
    let body;
    if (m.state === 'wounded') {
      const call = m.called ? '<span class="hc-ok">✓ EMS called</span>'
        : `<span class="hc-key">${key} Call EMS</span>${m.autoIn != null ? `<span class="hc-sub">auto-call in ${m.autoIn}s</span>` : ''}`;
      body = `<div class="hc-ico">✚</div><div class="hc-t"><b>WOUNDED${m.headshot ? ' · HEAD' : ''}</b>
        <span class="hc-sub">${m.left != null ? `Bleeding out in <b class="hc-time">${mmss(m.left)}</b>` : ''} · crawl with ${m.pad ? 'the left stick' : 'W A S D'}</span>
        <div class="hc-row">${call}${units}</div></div>`;
      if (m.left != null) chip.style.setProperty('--hc-pct', Math.max(0, Math.min(100, m.left / 1.8)) + '%');
    } else {
      body = `<div class="hc-ico">✚</div><div class="hc-t"><b>DOWN · UNRESPONSIVE</b>
        <span class="hc-sub">${m.called ? 'EMS has been called (priority 1)' : 'Waiting for help'}</span><div class="hc-row">${units || '<span class="hc-sub">No units on the call yet</span>'}</div></div>`;
    }
    chip.className = 'hurt-chip ' + m.state + (m.left != null && m.left <= 30 && m.state === 'wounded' ? ' urgent' : '');
    chip.innerHTML = body;
  }
  window.addEventListener('message', (e) => { const m = e.data || {}; if (m.action === 'hurt') drawChip(m); });

  // ---------------------------------------------------------------- the hospital desk
  let D = null, where = null, el = null, tab = 'care', P = null, q = '', list = null;
  const KICON = { aid: '🩹', treat: '💉', revive: '❤', respawn: '🏥', desk: '🛎', note: '📝' };
  const dt = (t) => t ? new Date(t * 1000).toLocaleString([], { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '';

  function care() {
    const h = D.hosp;
    const bar = `<div class="hp-health"><span>Your health</span><div class="bar"><i class="${h.health < 35 ? 'lo' : h.health < 70 ? 'mid' : 'hi'}" style="width:${Math.round(h.health)}%"></i></div><b>${Math.round(h.health)}%</b></div>`;
    if (h.staffed) {
      return bar + `<div class="hp-card"><div class="hp-ico">🚑</div><div class="t"><b>${h.medics} medic${h.medics === 1 ? '' : 's'} on duty</b>
        <span class="hint">The desk calls them for you: wait here and a medic will see you.</span></div>
        <button class="btn accent" data-ring>Call a medic</button></div>`;
    }
    const pay = (D.hosp.methods || ['bank']).map((m, i) => `<button class="btn ${i === 0 ? 'accent' : ''}" data-treat="${m}" ${h.hurt ? '' : 'disabled'}>
      Get treated · ${money(h.price)} ${m === 'cash' ? 'cash' : 'bank'}</button>`).join('');
    return bar + `<div class="hp-card"><div class="hp-ico">🩺</div><div class="t"><b>Treatment</b>
      <span class="hint">${h.hurt ? 'A nurse patches you up to full health.' : 'You are not hurt.'}${h.medics ? '' : ' No medics are on duty.'}</span></div>
      <div class="row">${h.price > 0 ? pay : `<button class="btn accent" data-treat="bank" ${h.hurt ? '' : 'disabled'}>Get treated</button>`}</div></div>`;
  }

  function bills() {
    const b = D.hosp.bills || [];
    if (!b.length) return '<div class="list-empty">🧾 You have no open medical bills.</div>';
    const total = b.reduce((a, x) => a + x.amount, 0);
    return `<div class="banner warn">You owe ${money(total)} in medical bills.</div><div class="hp-list">` + b.map((x) => `<div class="hp-bill">
      <div class="t"><b>${esc(x.reason)}</b><span class="hint">${esc(x.dept || '')} · ${dt(x.at)}</span></div><b class="amt">${money(x.amount)}</b>
      <div class="row">${(D.hosp.methods || ['bank']).map((m, i) => `<button class="btn small ${i === 0 ? 'accent' : ''}" data-pay="${x.id}" data-m="${m}">Pay · ${m}</button>`).join('')}</div></div>`).join('') + '</div>';
  }

  function recordRow(r, showName) {
    return `<div class="rec ${r.kind}"><div class="rec-ico">${KICON[r.kind] || '•'}</div><div class="t">
      <b>${showName ? esc(r.name) + ' · ' : ''}${esc(r.kindLabel)}${r.injury ? ' · ' + esc(r.injury) : ''}</b>
      <span class="hint">${dt(r.at)}${r.by ? ' · ' + esc(r.by) : ''}${r.dept ? ' · ' + esc(r.dept) : ''}${r.place ? ' · ' + esc(r.place) : ''}</span>
      ${r.treatment ? `<span>${esc(r.treatment)}</span>` : ''}${r.notes ? `<span class="rec-note">${esc(r.notes)}</span>` : ''}</div>
      ${r.bill ? `<span class="pill">${money(r.bill)}</span>` : ''}</div>`;
  }

  function records() {
    if (P) {
      return `<div class="rec-head"><button class="btn ghost small" data-back>‹ All patients</button><div class="t"><b>${esc(P.name)}</b>
        <span class="hint">Patient #${P.charId} · ${P.records.length} record${P.records.length === 1 ? '' : 's'}${P.owed ? ' · owes ' + money(P.owed) : ''}</span></div></div>
        ${P.bills.length ? `<div class="hp-list">${P.bills.map((b) => `<div class="hp-bill"><div class="t"><b>${esc(b.reason)}</b><span class="hint">${esc(b.dept || '')} · ${dt(b.at)}</span></div>
          <b class="amt">${money(b.amount)}</b>${b.canWaive ? `<button class="btn small ghost" data-waive="${b.id}">Waive</button>` : ''}</div>`).join('')}</div>` : ''}
        <div class="rec-add"><textarea id="hp-note" rows="2" maxlength="1000" placeholder="Add a note to this patient's record"></textarea>
        <button class="btn accent" data-note>Add note</button></div>
        <div class="rec-list">${P.records.map((r) => recordRow(r, false)).join('') || '<div class="list-empty">No records.</div>'}</div>`;
    }
    const L = list || { patients: [], recent: [] };
    return `<div class="rec-search"><input type="text" id="hp-q" maxlength="40" placeholder="Search a patient by name" value="${esc(q)}"><button class="btn" data-search>Search</button></div>
      <div class="rec-grid"><div><div class="lbl">Patients</div><div class="pt-list">${L.patients.map((p) => `<button class="pt" data-pt="${p.charId}">
        <b>${esc(p.name)}</b><span class="hint">${p.n} record${p.n === 1 ? '' : 's'} · ${ago(p.last)}</span></button>`).join('') || '<div class="list-empty">Nobody found.</div>'}</div></div>
      <div><div class="lbl">Latest</div><div class="rec-list">${L.recent.map((r) => recordRow(r, true)).join('') || '<div class="list-empty">No records yet.</div>'}</div></div></div>`;
  }

  function render() {
    const h = D.hosp;
    const tabs = [['care', '🩺 Treatment'], ['bills', `🧾 Bills${h.bills.length ? ' (' + h.bills.length + ')' : ''}`]];
    if (h.medic) tabs.push(['records', '📋 Medical records']);
    if (!tabs.some((t) => t[0] === tab)) tab = 'care';
    const body = tab === 'care' ? care() : tab === 'bills' ? bills() : records();
    el.querySelector('.sp-body').innerHTML = `<div class="chips hp-tabs">${tabs.map((t) => `<button class="fchip hp-tab ${t[0] === tab ? 'on' : ''}" data-tab="${t[0]}">${t[1]}</button>`).join('')}</div>
      <div class="hp-body fade-in">${body}</div>`;
    wire();
    window.ESPadPage = { tabs: ['.hp-tab'], keys: [['Esc', 'Close']] };
    if (window.ESPad) window.ESPad.hints();
  }

  async function loadList() {
    const r = await call('whip_jobs:med:list', Object.assign({ q }, where()));
    if (said(r)) { list = r.data; render(); }
  }
  async function openPatient(cid) {
    const r = await call('whip_jobs:med:patient', Object.assign({ charId: cid }, where()));
    if (said(r)) { P = r.data; render(); }
  }
  async function reload() {
    const r = await call('whip_jobs:spot:open', where());
    if (r.ok) { D = r.data; render(); } else said(r);
  }

  function wire() {
    const b = el.querySelector('.sp-body');
    b.querySelectorAll('[data-tab]').forEach((x) => x.onclick = () => { tab = x.dataset.tab; P = null; render(); if (tab === 'records' && !list) loadList(); });
    b.querySelectorAll('[data-treat]').forEach((x) => x.onclick = () => busy(x, async () => {
      const r = await call('whip_jobs:hosp:treat', Object.assign({ method: x.dataset.treat }, where()));
      if (said(r, 'You are treated: full health')) reload();
    }));
    b.querySelectorAll('[data-ring]').forEach((x) => x.onclick = () => busy(x, async () => {
      const r = await call('whip_jobs:hosp:treat', where());
      said(r, r.data && r.data.again ? 'A medic was already called: wait here' : 'A medic is on the way: wait here');
    }));
    b.querySelectorAll('[data-pay]').forEach((x) => x.onclick = () => busy(x, async () => {
      const r = await call('whip_jobs:hosp:pay', Object.assign({ id: +x.dataset.pay, method: x.dataset.m }, where()));
      if (said(r, 'Bill paid')) { D.hosp.bills = r.data.bills; render(); }
    }));
    const qi = b.querySelector('#hp-q');
    if (qi) qi.onkeydown = (e) => { if (e.key === 'Enter') { q = qi.value; loadList(); } };
    b.querySelectorAll('[data-search]').forEach((x) => x.onclick = () => busy(x, async () => { q = qi.value; await loadList(); }));
    b.querySelectorAll('[data-pt]').forEach((x) => x.onclick = () => busy(x, () => openPatient(+x.dataset.pt)));
    b.querySelectorAll('[data-back]').forEach((x) => x.onclick = () => { P = null; render(); });
    b.querySelectorAll('[data-note]').forEach((x) => x.onclick = () => busy(x, async () => {
      const r = await call('whip_jobs:med:note', Object.assign({ charId: P.charId, text: b.querySelector('#hp-note').value }, where()));
      if (said(r, 'Note added')) { P = r.data; render(); }
    }));
    b.querySelectorAll('[data-waive]').forEach((x) => x.onclick = async () => {
      if (!await J.confirm('Waive this bill?', 'The patient will not have to pay it.', 'Waive')) return;
      const r = await call('whip_jobs:med:waive', Object.assign({ id: +x.dataset.waive }, where()));
      if (said(r, 'Bill waived')) { P = r.data; render(); }
    });
  }

  J.hosp = {
    open(root, data, whereFn) { el = root; D = data; where = whereFn; tab = 'care'; P = null; list = null; q = ''; render(); },
    back() { if (P) { P = null; render(); return true; } return false; },
  };
})();
