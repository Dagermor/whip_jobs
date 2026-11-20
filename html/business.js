// es_jobs: Businesses (/business). Player-owned businesses made like a department (name, short name, colour, logo with
// a live preview), their ranks and pay, staff (hire someone standing near, set rank, let go), money (the business
// account and its ledger) and stations. Departments the player leads show here too, for pay, money and stations.
(function () {
  'use strict';
  const { $, $$, esc, call, toast, said, busy, modal, confirm, money, ago } = J;
  const MAX_BYTES = 192 * 1024, SIDE = 256, CHUNK = 15000;
  const PK = { cur: null };
  const B = { list: [], admin: false, canCreate: false, price: 0, jobId: null, cur: null, tab: 'overview', creating: false };
  const PERMS = [['canHire', 'Hire'], ['canFire', 'Let go'], ['canPromote', 'Promote'], ['canDemote', 'Demote'], ['canManage', 'Manage (ranks, pay, logo)']];

  // ---------------------------------------------------------------- the logo picker (es_mdt Departments')
  function loadImg(src) {
    return new Promise((res, rej) => { const im = new Image(); im.onload = () => res(im); im.onerror = () => rej(new Error('That is not a picture this screen can read')); im.src = src; });
  }
  function cutBackground(ctx) {
    const img = ctx.getImageData(0, 0, SIDE, SIDE), p = img.data;
    let seed = -1;
    for (const [x, y] of [[1, 1], [SIDE - 2, 1], [1, SIDE - 2], [SIDE - 2, SIDE - 2]]) { const i = (y * SIDE + x) * 4; if (p[i + 3] > 200) { seed = i; break; } }
    if (seed < 0) return false;
    const c = [p[seed], p[seed + 1], p[seed + 2]];
    const near = (i) => Math.abs(p[i] - c[0]) + Math.abs(p[i + 1] - c[1]) + Math.abs(p[i + 2] - c[2]) < 90;
    const seen = new Uint8Array(SIDE * SIDE), stack = [];
    for (let i = 0; i < SIDE; i++) stack.push(i, 0, i, SIDE - 1, 0, i, SIDE - 1, i);
    while (stack.length) {
      const y = stack.pop(), x = stack.pop();
      if (x < 0 || y < 0 || x >= SIDE || y >= SIDE) continue;
      const k = y * SIDE + x; if (seen[k]) continue; seen[k] = 1;
      const i = k * 4; if (p[i + 3] === 0) { stack.push(x + 1, y, x - 1, y, x, y + 1, x, y - 1); continue; }
      if (!near(i)) continue;
      p[i + 3] = 0;
      stack.push(x + 1, y, x - 1, y, x, y + 1, x, y - 1);
    }
    ctx.putImageData(img, 0, 0);
    return true;
  }
  const bytesOf = (u) => Math.floor((u.length - u.indexOf(',') - 1) * 3 / 4);
  function render(im, cut, format) {
    const cv = document.createElement('canvas'); cv.width = SIDE; cv.height = SIDE;
    const ctx = cv.getContext('2d');
    const s = Math.min(SIDE / im.width, SIDE / im.height);
    const w = Math.round(im.width * s), h = Math.round(im.height * s);
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(im, Math.round((SIDE - w) / 2), Math.round((SIDE - h) / 2), w, h);
    if (cut) cutBackground(ctx);
    if (format !== 'png') {
      for (const q of [0.92, 0.85, 0.75, 0.6, 0.45]) {
        const u = cv.toDataURL('image/webp', q);
        if (u.indexOf('data:image/webp') === 0 && bytesOf(u) <= MAX_BYTES) return u;
      }
    }
    const png = cv.toDataURL('image/png');
    if (bytesOf(png) <= MAX_BYTES) return png;
    throw new Error('Even shrunk, that picture is over 192 KB. Try WebP.');
  }

  function makePicker(host, opts) {
    const P = { src: null, out: null, saved: opts.current || null, dirty: false, deptId: opts.deptId || 0, token: 0 };
    host.innerHTML = `
      <div class="picker">
        <div class="drop" tabindex="0" data-probe-press>
          <div class="drop-preview"></div>
          <div class="drop-state"></div>
        </div>
        <div class="pick-side">
          <div class="row">
            <button class="btn" data-pick="file" data-probe-press>📁 Choose picture</button>
            <input type="file" accept="image/*" class="hidden">
            <button class="btn ghost" data-pick="clear" data-probe-press>Clear</button>
          </div>
          <div class="url-row">
            <input type="text" placeholder="…or paste an image link (https://…)" data-pick="url">
            <button class="btn" data-pick="load" data-probe-press>Load</button>
          </div>
          <div class="row opts">
            <label class="switch"><input type="checkbox" data-pick="cut"><span></span> Remove plain background</label>
            <div class="seg" data-pick="fmt"><button data-v="webp" class="on">WebP</button><button data-v="png">PNG</button></div>
          </div>
          <div class="hint pick-info"></div>
        </div>
      </div>`;
    const drop = $('.drop', host), prev = $('.drop-preview', host), state = $('.drop-state', host), info = $('.pick-info', host);
    const file = $('input[type=file]', host), url = $('[data-pick=url]', host), cut = $('[data-pick=cut]', host);
    let fmt = opts.format || 'webp';
    host.querySelectorAll('.seg button').forEach((b) => b.classList.toggle('on', b.dataset.v === fmt));

    function show(kind, msg) {
      drop.className = 'drop ' + kind;
      const img = P.out || (kind === 'saved' ? P.saved : null);
      prev.innerHTML = img ? `<img src="${img}" alt="">` : '';
      if (kind === 'loading') state.innerHTML = '<div class="spin"></div><div>Loading picture…</div>';
      else if (kind === 'error') state.innerHTML = `<div class="err-ico">!</div><div>${esc(msg)}</div><div class="hint">Try another link, a file, or Ctrl+V</div>`;
      else if (kind === 'empty') state.innerHTML = '<div class="drop-ico">⬆</div><div><b>Drop a picture here</b></div><div class="hint">or paste one with Ctrl+V</div>';
      else state.innerHTML = '';
      if (P.out) info.textContent = `Preview: ${SIDE}×${SIDE} · ${P.out.indexOf('image/png') > 0 ? 'PNG' : 'WebP'} · ${Math.ceil(bytesOf(P.out) / 1024)} KB · not saved yet`;
      else if (P.saved) info.textContent = 'This is the saved logo.';
      else info.textContent = `Any picture works. It is shrunk to ${SIDE}×${SIDE}, up to 192 KB.`;
      opts.onChange && opts.onChange(P);
    }
    function process() {
      if (!P.src) return;
      try { P.out = render(P.src, cut.checked, fmt); P.dirty = true; show('ready'); }
      catch (e) { P.out = null; P.dirty = false; show('error', e.message); }
    }
    async function useSrc(srcUrl) {
      const t = ++P.token; show('loading');
      try { const im = await loadImg(srcUrl); if (t !== P.token) return; P.src = im; process(); }
      catch (e) { if (t === P.token) { P.out = null; P.src = null; show('error', e.message); } }
    }
    function useFile(f) {
      if (!f) return;
      if (!f.type || f.type.indexOf('image/') !== 0) { show('error', 'That file is not a picture'); return; }
      useSrc(URL.createObjectURL(f));
    }
    async function useUrl(u) {
      u = (u || '').trim();
      if (u.indexOf('data:image/') === 0) { useSrc(u); return; }
      if (!/^https?:\/\/\S+$/i.test(u)) { show('error', 'A link starts with https://'); return; }
      const t = ++P.token; show('loading');
      // First the browser itself (works when the site allows it), then the server fetches it
      try {
        const r = await fetch(u, { mode: 'cors' });
        if (r.ok) {
          const b = await r.blob();
          if (b.type && b.type.indexOf('image/') === 0) { if (t !== P.token) return; return useSrc(URL.createObjectURL(b)); }
        }
      } catch (e) { /* not allowed from here: ask the server */ }
      if (t !== P.token) return;
      P.out = null; P.src = null; show('error', 'That site does not let pictures be loaded from a link. Save it and choose the file, or copy the picture and press Ctrl+V.');
    }
    P.useFile = useFile; P.useUrl = useUrl;
    P.clear = () => { P.token++; P.src = null; P.out = null; P.dirty = false; url.value = ''; show(P.saved ? 'saved' : 'empty'); };
    P.value = () => P.out;
    P.markSaved = (u) => { P.saved = u; P.src = null; P.out = null; P.dirty = false; show('saved'); };

    $('[data-pick=file]', host).onclick = () => file.click();
    file.onchange = (e) => { useFile(e.target.files && e.target.files[0]); e.target.value = ''; };
    $('[data-pick=clear]', host).onclick = P.clear;
    $('[data-pick=load]', host).onclick = () => useUrl(url.value);
    url.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); useUrl(url.value); } });
    url.addEventListener('paste', (e) => e.stopPropagation());   // a link typed into the box stays a link
    cut.onchange = process;
    host.querySelectorAll('.seg button').forEach((b) => b.onclick = () => { fmt = b.dataset.v; host.querySelectorAll('.seg button').forEach((x) => x.classList.toggle('on', x === b)); process(); });
    drop.onclick = () => file.click();
    ['dragenter', 'dragover'].forEach((ev) => drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.add('hover'); }));
    ['dragleave', 'drop'].forEach((ev) => drop.addEventListener(ev, () => drop.classList.remove('hover')));
    drop.addEventListener('drop', (e) => {
      e.preventDefault();
      const dt = e.dataTransfer; if (!dt) return;
      if (dt.files && dt.files.length) return useFile(dt.files[0]);
      const link = dt.getData('text/uri-list') || dt.getData('text/plain');
      if (link) { url.value = link.split('\n')[0].trim(); useUrl(url.value); }
    });
    PK.cur = P;
    show(P.saved ? 'saved' : 'empty');
    return P;
  }

  document.addEventListener('paste', (e) => {
    const P = PK.cur; if (J.view !== 'business' || !P || !document.body.contains($('.picker'))) return;
    const items = (e.clipboardData && e.clipboardData.items) || [];
    for (const it of items) { if (it.type && it.type.indexOf('image/') === 0) { e.preventDefault(); P.useFile(it.getAsFile()); return; } }
  });

  async function uploadLogo(id, dataUrl) {
    const total = Math.ceil(dataUrl.length / CHUNK);
    let r;
    for (let i = 1; i <= total; i++) {
      r = await call('es_jobs:biz:logoPart', { id, i, total, part: dataUrl.slice((i - 1) * CHUNK, i * CHUNK) });
      if (!r.ok) return r;
    }
    if (r && r.ok && r.data.logoVer) J.setLogo('biz:' + id, r.data.logoVer, dataUrl);
    return r;
  }

  // ---------------------------------------------------------------- list
  async function loadList(keep) {
    const r = await call('es_jobs:biz:list', {});
    if (!said(r)) return;
    Object.assign(B, { list: r.data.list, admin: r.data.admin, canCreate: r.data.canCreate, price: r.data.price });
    $('#bz-new').classList.toggle('hidden', !B.canCreate);
    renderList();
    if (keep && B.jobId) await select(B.jobId, true);
    else if (!B.jobId && !B.creating) {
      const first = B.list.find((o) => o.kind === 'biz') || B.list[0];
      if (first) await select(first.jobId); else renderEmpty();
    }
  }
  function renderEmpty() {
    $('#bz-main').innerHTML = `<div class="empty"><div class="empty-ico">🏢</div><div class="empty-title">No businesses yet</div>
      <div class="hint">${B.canCreate ? 'Start one with New business.' : 'An admin opens a business for its owner. Once you work at one, it shows here.'}</div></div>`;
  }
  function renderList() {
    const el = $('#bz-list');
    const biz = B.list.filter((o) => o.kind === 'biz'), dep = B.list.filter((o) => o.kind === 'dept');
    const item = (o) => `<div class="dept-item ${B.jobId === o.jobId && !B.creating ? 'on' : ''}" data-org="${o.jobId}" tabindex="0" style="--c1:${esc(o.color || '#334155')}">
      ${J.logoHtml(o)}<div class="di-text"><div class="s">${esc(o.short || o.name)}</div><div class="n">${esc(o.name)}${o.myRank ? ' · ' + esc(o.myRank) : ''}</div></div></div>`;
    el.innerHTML = (biz.length ? '<div class="lbl">Businesses</div>' + biz.map(item).join('') : '') +
      (dep.length ? '<div class="lbl" style="margin-top:10px">Departments you lead</div>' + dep.map(item).join('') : '') ||
      '<div class="list-empty">Nothing here yet.</div>';
    J.fillLogos(el, B.list);
    $$('[data-org]', el).forEach((d) => d.onclick = () => select(+d.dataset.org));
  }

  // ---------------------------------------------------------------- one business / department
  async function select(jobId, keepTab) {
    B.creating = false; B.jobId = jobId;
    if (!keepTab) B.tab = 'overview';
    renderList();
    const r = await call('es_jobs:org:get', { jobId });
    if (!said(r)) return;
    B.cur = r.data;
    renderDetail();
  }

  function renderDetail() {
    const d = B.cur, o = d.org, biz = o.kind === 'biz';
    const tabs = [['overview', 'Overview'], ['ranks', biz ? 'Ranks & pay' : 'Pay']];
    if (biz) tabs.push(['staff', 'Staff']);
    if (d.manage) tabs.push(['money', 'Money']);
    tabs.push(['stations', 'Stations']);
    if (!tabs.some((t) => t[0] === B.tab)) B.tab = 'overview';
    $('#bz-main').innerHTML = `<div style="display:flex;flex-direction:column;height:100%">
      <div class="bz-head" style="--bc:${esc(o.color || '#334155')}"><span id="bz-logo"></span>
        <div class="t"><b>${esc(o.short)}</b><div class="dept-name">${esc(o.name)}</div>
        <div class="dept-meta">${biz ? `Business · owner ${esc(d.biz.ownerName || '-')}` : 'Department · ranks and people in /departments'}</div></div></div>
      <div class="tabs" id="bz-tabs">${tabs.map(([k, l]) => `<button class="tab ${B.tab === k ? 'on' : ''}" data-tab="${k}">${l}</button>`).join('')}</div>
      <div class="tab-body fade-in" id="bz-body"></div></div>`;
    $('#bz-logo').replaceWith(J.logoEl(o, 'lg'));
    $$('[data-tab]').forEach((b) => b.onclick = () => { B.tab = b.dataset.tab; renderDetail(); });
    window.ESPadPage = { tabs: ['#bz-tabs .tab'], keys: [['Esc', 'Close']] };
    ({ overview, ranks, staff, money: moneyTab, stations })[B.tab]();
  }

  function overview() {
    const d = B.cur, o = d.org, el = $('#bz-body');
    if (o.kind !== 'biz') {
      el.innerHTML = `<div class="card"><div class="card-title">${esc(o.name)}</div><p class="hint">Departments are made and run in /departments (ranks, people, logo).
        Here its leaders set <b>pay by rank</b>, see its <b>money</b> and set up its <b>stations</b>.</p></div>`;
      return;
    }
    const b = d.biz, can = d.rights.manage;
    el.innerHTML = `<div class="card"><div class="card-title">Details</div>
      <div class="grid"><div class="field"><label>Name</label><input type="text" id="bo-name" maxlength="48" value="${esc(b.name)}" ${can ? '' : 'disabled'}></div>
      <div class="field"><label>Short name</label><input type="text" id="bo-short" maxlength="12" value="${esc(b.short)}" ${can ? '' : 'disabled'}></div>
      <div class="field"><label>Colour</label><div class="row"><input type="color" id="bo-color" value="${esc(b.color || '#4f8ff7')}" ${can ? '' : 'disabled'}></div></div>
      <div class="field"><label>Owner</label><div style="padding:8px 0">${esc(b.ownerName || '-')}</div></div></div>
      <div class="field" style="margin-top:10px"><label>About (shown to staff)</label><textarea id="bo-blurb" maxlength="200" ${can ? '' : 'disabled'}>${esc(b.blurb || '')}</textarea></div>
      ${d.rights.admin ? '<div class="field" style="margin-top:10px"><label>Hand it to someone else (their server id, they must be in the city)</label><input type="number" id="bo-owner" min="1" placeholder="Leave empty to keep the owner"></div>' : ''}
      ${can ? '<div class="row actions"><button class="btn accent" id="bo-save">Save details</button></div>' : ''}</div>
      <div class="card"><div class="card-title">Logo</div>${can ? '<div id="bo-picker"></div><div class="row actions"><button class="btn accent" id="bo-logo" disabled>Save logo</button></div>' : '<div class="logo-box" id="bo-logobox"></div>'}</div>
      ${d.rights.admin ? `<div class="card danger-zone"><div class="card-title">Close the business</div><p class="hint">Its job, ranks and staff list go. Its account must be empty first.</p>
        <div class="row actions"><button class="btn danger" id="bo-del">Close ${esc(b.short)}</button></div></div>` : ''}`;
    if (can) {
      $('#bo-save').onclick = (e) => busy(e.currentTarget, async () => {
        const r = await call('es_jobs:biz:update', { id: b.id, name: $('#bo-name').value, short: $('#bo-short').value, color: $('#bo-color').value,
          blurb: $('#bo-blurb').value, newOwner: $('#bo-owner') && $('#bo-owner').value ? +$('#bo-owner').value : null });
        if (said(r, 'Saved')) await loadList(true);
      });
      J.logoOf(o).then((cur) => {
        const P = makePicker($('#bo-picker'), { current: cur, onChange: (p) => { const s = $('#bo-logo'); if (s) s.disabled = !p.out; } });
        $('#bo-logo').onclick = (e) => busy(e.currentTarget, async () => {
          const u = P.value(); if (!u) return;
          const r = await uploadLogo(b.id, u);
          if (said(r, 'Logo saved')) { P.markSaved(u); await loadList(true); }
        });
      });
    } else J.logoOf(o).then((src) => { const x = $('#bo-logobox'); if (x) x.innerHTML = src ? `<img src="${src}">` : '<span class="hint">No logo</span>'; });
    const del = $('#bo-del'); if (del) del.onclick = async () => {
      if (!(await confirm(`Close ${b.name}?`, 'Its job, ranks and staff list go for good. Stations it shares keep their other departments.', 'Close business', true))) return;
      const r = await call('es_jobs:biz:delete', { id: b.id });
      if (said(r, 'Business closed')) { B.jobId = null; B.cur = null; await loadList(); }
    };
  }

  function ranks() {
    const d = B.cur, biz = d.org.kind === 'biz', el = $('#bz-body');
    const canRank = biz && d.rights.manage, canPay = d.manage;
    el.innerHTML = `<div class="card"><div class="card-head"><div class="card-title">${biz ? 'Ranks and pay' : 'Pay by rank'}</div>
      ${canRank ? '<button class="btn sm" id="rk-add">＋ Rank</button>' : ''}</div>
      <p class="hint">Paid every ${d.payInterval || 15} minutes on duty, from ${biz ? 'the business' : 'the department'} account.${d.payOn === false ? ' <b class="warn">Pay is switched off in /whip.</b>' : ''} Empty: the default for the level.</p>
      <table><thead><tr><th>Rank</th><th>Level</th><th>Pay</th>${biz ? '<th>Can</th><th></th>' : ''}</tr></thead><tbody>
      ${d.ranks.map((r) => `<tr><td><b>${esc(r.name)}</b></td><td class="lvl">${r.level}</td>
        <td>${canPay ? `<input type="number" class="pay-in" min="0" data-pay="${r.roleId}" value="${r.pay == null ? '' : r.pay}" placeholder="${r.payDefault}">` : money(r.pay == null ? r.payDefault : r.pay)}</td>
        ${biz ? `<td class="hint">${PERMS.filter(([k]) => r.perms[k]).map(([, l]) => esc(l.split(' ')[0])).join(', ') || '-'}</td>
        <td>${canRank ? `<button class="btn sm ghost" data-rk="${r.roleId}">Edit</button>` : ''}</td>` : ''}</tr>`).join('')}</tbody></table></div>`;
    $$('[data-pay]', el).forEach((inp) => inp.onchange = async () => {
      const r = await call('es_jobs:pay:set', { jobId: d.org.jobId, roleId: +inp.dataset.pay, amount: inp.value === '' ? null : +inp.value });
      if (said(r, r.data && r.data.default ? `Back to the default (${money(r.data.amount)})` : 'Pay saved')) inp.value = r.data.default ? '' : r.data.amount;
    });
    $$('[data-rk]', el).forEach((b) => b.onclick = () => rankEdit(d.ranks.find((x) => x.roleId === +b.dataset.rk)));
    const add = $('#rk-add'); if (add) add.onclick = () => rankEdit(null);
  }

  function rankEdit(r) {
    const d = B.cur, isNew = !r;
    r = r || { roleId: 0, name: '', level: 10, perms: {} };
    modal(`<h2>${isNew ? 'New rank' : 'Edit ' + esc(r.name)}</h2>
      <div class="grid"><div class="field"><label>Name</label><input type="text" id="rk-name" maxlength="40" value="${esc(r.name)}" autofocus></div>
      <div class="field"><label>Level (1-100; higher outranks lower)</label><input type="number" id="rk-level" min="1" max="100" value="${r.level}"></div></div>
      <div class="lbl" style="margin:12px 0 6px">This rank can</div><div class="perm-grid">${PERMS.map(([k, l]) => `<label class="toggle"><input type="checkbox" data-perm="${k}" ${r.perms[k] ? 'checked' : ''}> ${esc(l)}</label>`).join('')}</div>
      <div class="row end">${isNew ? '' : '<button class="btn danger" id="rk-del">Delete rank</button>'}<span style="flex:1"></span><button class="btn ghost" data-m="x">Cancel</button><button class="btn accent" id="rk-save">Save</button></div>`, (c, done) => {
      $('#rk-save', c).onclick = (e) => busy(e.currentTarget, async () => {
        const perms = {}; $$('[data-perm]', c).forEach((x) => perms[x.dataset.perm] = x.checked);
        const x = await call('es_jobs:biz:rank', { id: d.biz.id, roleId: r.roleId, name: $('#rk-name', c).value, level: +$('#rk-level', c).value, perms });
        if (said(x, 'Rank saved')) { done(); await select(B.jobId, true); }
      });
      const del = $('#rk-del', c); if (del) del.onclick = (e) => busy(e.currentTarget, async () => {
        const x = await call('es_jobs:biz:rankDelete', { id: d.biz.id, roleId: r.roleId });
        if (said(x, 'Rank deleted')) { done(); await select(B.jobId, true); }
      });
    });
  }

  function staff() {
    const d = B.cur, el = $('#bz-body'), rt = d.rights;
    const opts = (cur) => d.ranks.map((r) => `<option value="${r.roleId}" ${r.roleId === cur ? 'selected' : ''}>${esc(r.name)} (${r.level})</option>`).join('');
    const onDuty = d.roster.filter((m) => m.onDuty).length;
    el.innerHTML = `<div class="stats"><div><b>${d.roster.length}</b><span>Staff</span></div><div><b class="money in">${onDuty}</b><span>On duty</span></div>
      <div><b>${d.roster.filter((m) => m.online).length}</b><span>In the city</span></div><div><b>${d.ranks.length}</b><span>Ranks</span></div></div>
      <div class="card"><div class="card-head"><div class="card-title">Staff</div>${rt.hire ? '<button class="btn accent sm" id="sf-hire">＋ Hire someone nearby</button>' : ''}</div>
      <table><thead><tr><th>Name</th><th>Rank</th><th>Status</th><th></th></tr></thead><tbody>
      ${d.roster.map((m) => `<tr><td><b>${esc(m.name)}</b>${m.owner ? ' <span class="pill">Owner</span>' : ''}</td>
        <td>${rt.promote && !m.owner ? `<select data-rank="${m.charId}">${opts(m.roleId)}</select>` : esc(m.roleName)}</td>
        <td><span class="pill ${m.onDuty ? 'on' : 'off'}">${m.onDuty ? 'On duty' : m.online ? 'In the city' : 'Away'}</span></td>
        <td>${rt.fire && !m.owner ? `<button class="btn sm ghost" data-fire="${m.charId}">Let go</button>` : ''}</td></tr>`).join('')}</tbody></table></div>`;
    $$('[data-rank]', el).forEach((s) => s.onchange = async () => {
      const r = await call('es_jobs:biz:setRank', { id: d.biz.id, charId: +s.dataset.rank, roleId: +s.value });
      if (said(r, 'Rank changed')) await select(B.jobId, true);
    });
    $$('[data-fire]', el).forEach((b) => b.onclick = async () => {
      const m = d.roster.find((x) => x.charId === +b.dataset.fire);
      if (!(await confirm(`Let ${m.name} go?`, `They stop working at ${d.biz.name}.`, 'Let go', true))) return;
      const r = await call('es_jobs:biz:fire', { id: d.biz.id, charId: m.charId });
      if (said(r, `${m.name} no longer works here`)) await select(B.jobId, true);
    });
    const h = $('#sf-hire'); if (h) h.onclick = () => busy(h, hire);
  }

  async function hire() {
    const d = B.cur;
    const r = await call('es_jobs:biz:nearby', { id: d.biz.id });
    if (!said(r)) return;
    const people = r.data || [];
    const low = d.ranks.slice().sort((a, b) => a.level - b.level);
    modal(`<h2>Hire someone nearby</h2><p class="hint">People standing within a few metres of you who do not work here yet.</p>
      ${people.length ? `<div class="field"><label>Start them as</label><select id="hi-rank">${low.map((x) => `<option value="${x.roleId}">${esc(x.name)} (${x.level})</option>`).join('')}</select></div>
      <div class="hist" style="margin-top:12px">${people.map((p) => `<div class="h"><div class="t"><b>${esc(p.name)}</b><span>Server id ${p.source}</span></div><button class="btn accent sm" data-hire="${p.source}">Hire</button></div>`).join('')}</div>`
      : '<div class="list-empty">Nobody is standing near you. Ask them to come closer, then try again.</div>'}
      <div class="row end"><button class="btn" data-m="x">Close</button></div>`, (c, done) => {
      $$('[data-hire]', c).forEach((b) => b.onclick = () => busy(b, async () => {
        const x = await call('es_jobs:biz:hire', { id: d.biz.id, target: +b.dataset.hire, roleId: +$('#hi-rank', c).value });
        if (said(x, 'Hired')) { done(); await select(B.jobId, true); }
      }));
    });
  }

  function moneyTab() {
    const d = B.cur, el = $('#bz-body'), a = d.account, w = d.payWeek || {};
    const KIND = { pay: 'Paycheck', pay_missed: 'Missed paycheck', open: 'Opened', fine: 'Fine', ticket: 'Ticket', impound: 'Impound fee', income: 'Income', invoice: 'Invoice' };
    el.innerHTML = `<div class="stats"><div><b>${a ? money(a.balance) : '-'}</b><span>Balance</span></div><div><b class="money out">${money(w.paid)}</b><span>Paid out, 7 days</span></div>
      <div><b class="money in">${money(w.income)}</b><span>Taken in, 7 days</span></div><div><b class="${w.missed ? 'money miss' : ''}">${w.missed || 0}</b><span>Missed paychecks</span></div></div>
      ${!a ? '<div class="banner warn">⚠ No bank account: paychecks cannot be paid. An admin can open one in /whip.</div>' : a.frozen ? '<div class="banner warn">⚠ The account is frozen.</div>' : ''}
      ${a ? `<p class="hint" style="margin-bottom:12px">Account ${esc(a.number)} · put money in at any bank (business accounts).</p>` : ''}
      <div class="card"><div class="card-title">Recent</div><table><thead><tr><th>When</th><th>What</th><th>Who</th><th style="text-align:right">Amount</th></tr></thead><tbody>
      ${(d.ledger || []).map((x) => `<tr><td class="hint">${ago(x.at)}</td><td>${esc(KIND[x.kind] || x.kind)}${x.note ? `<div class="hint">${esc(x.note)}</div>` : ''}</td><td>${esc(x.who || '')}</td>
        <td style="text-align:right" class="money ${x.kind === 'pay_missed' ? 'miss' : x.amount < 0 ? 'out' : 'in'}">${x.kind === 'pay_missed' ? 'missed' : money(x.amount)}</td></tr>`).join('') || '<tr><td colspan="4" class="hint">Nothing yet.</td></tr>'}
      </tbody></table></div>`;
  }

  function stations() {
    const d = B.cur, el = $('#bz-body');
    el.innerHTML = `<div class="card"><div class="card-head"><div class="card-title">Stations</div>${d.manage ? '<button class="btn accent sm" id="sn-open">Open the station editor</button>' : ''}</div>
      <p class="hint">Where ${esc(d.org.short)} clocks on, takes equipment and vehicles. A station can be shared with other departments and businesses.</p>
      <div class="hist">${(d.stations || []).map((s) => `<div class="h"><div class="t"><b>${esc(s.name)}</b><span>${s.spots} spots${s.shared ? ' · shared' : ''} · ${Object.keys(s.types).map((k) => k + (s.types[k] > 1 ? ' ×' + s.types[k] : '')).join(', ')}</span></div></div>`).join('')
        || '<div class="list-empty">No stations yet.</div>'}</div></div>`;
    const b = $('#sn-open'); if (b) b.onclick = () => J.stations.open(d.org.jobId);
  }

  // ---------------------------------------------------------------- new business
  function create() {
    B.creating = true; B.jobId = null; renderList();
    $('#bz-main').innerHTML = `<div id="create" class="fade-in">
      <div class="create-head"><div class="title">New business</div><p class="hint">Name it and give it a logo. Ranks, staff and stations come next; everything can be changed later.${B.price ? ` Opening it costs <b>${money(B.price)}</b> from your bank.` : ''}</p></div>
      <div class="preview-card" id="cr-prev"><span id="cr-plogo"></span><div><b id="cr-pshort">SHORT</b><div id="cr-pname" class="hint">Business name</div></div></div>
      <div class="card" style="margin-top:14px"><div class="grid">
        <div class="field"><label>Name</label><input type="text" id="cr-name" maxlength="48" placeholder="Bean Machine Coffee" autofocus></div>
        <div class="field"><label>Short name</label><input type="text" id="cr-short" maxlength="12" placeholder="BEAN"></div>
        <div class="field"><label>Colour</label><input type="color" id="cr-color" value="#7c4a2d"></div>
        ${B.admin ? '<div class="field"><label>Owner (server id; empty = you)</label><input type="number" id="cr-owner" min="1" placeholder="e.g. 12"></div>' : ''}
      </div><div class="field" style="margin-top:10px"><label>About</label><textarea id="cr-blurb" maxlength="200" placeholder="Coffee, pastries and the best cold brew in Los Santos."></textarea></div></div>
      <div class="card"><div class="card-title">Logo <span class="hint">(optional)</span></div><div id="cr-picker"></div></div>
      <div class="row actions"><button class="btn ghost" id="cr-cancel">Cancel</button><button class="btn accent" id="cr-go">${B.price ? 'Pay ' + money(B.price) + ' and open' : 'Open the business'}</button></div></div>`;
    const prev = () => {
      const c = $('#cr-color').value;
      $('#cr-prev').style.setProperty('--bc', c);
      $('#cr-pshort').textContent = ($('#cr-short').value || 'SHORT').toUpperCase();
      $('#cr-pname').textContent = $('#cr-name').value || 'Business name';
      const u = PK.cur && PK.cur.value();
      $('#cr-plogo').innerHTML = `<span class="org-logo lg ${u ? 'has' : ''}" style="--oc:${esc(c)}">${u ? `<img src="${u}">` : esc(($('#cr-short').value || '?').slice(0, 5).toUpperCase())}</span>`;
    };
    ['#cr-name', '#cr-short', '#cr-color'].forEach((s) => $(s).addEventListener('input', prev));
    makePicker($('#cr-picker'), { onChange: prev });
    prev();
    $('#cr-cancel').onclick = () => { B.creating = false; loadList(); };
    $('#cr-go').onclick = (e) => busy(e.currentTarget, async () => {
      const name = $('#cr-name').value.trim(), short = $('#cr-short').value.trim();
      if (name.length < 3) { toast('The name needs 3 letters or more', 'err'); return; }
      if (!/^[\w&-]{2,12}$/.test(short)) { toast('The short name is 2-12 letters, digits, & or -', 'err'); return; }
      const r = await call('es_jobs:biz:create', { name, short, color: $('#cr-color').value, blurb: $('#cr-blurb').value, owner: $('#cr-owner') && $('#cr-owner').value ? +$('#cr-owner').value : null });
      if (!said(r, `${name} is open`)) return;
      const u = PK.cur && PK.cur.value();
      if (u) { const x = await uploadLogo(r.data.id, u); if (!x.ok) toast('Opened, but the logo did not save: ' + (x.why || ''), 'err'); }
      B.creating = false; B.jobId = r.data.jobId;
      await loadList(true);
    });
  }

  $('#bz-new').onclick = create;
  J.views.business = {
    open: () => { B.jobId = null; B.cur = null; B.creating = false; loadList(); },
    changed: () => { if (J.view === 'business') loadList(); },   // the list only: never over a form being edited
    pad: { tabs: ['#bz-tabs .tab'], keys: [['Esc', 'Close']] },
  };
})();
