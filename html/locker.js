// es_jobs: the locker room. Uniforms of the departments and businesses the player works for here, each from a rank up,
// shown on the player as they are picked (a live preview: the game puts it on their ped behind this panel and a camera
// faces them). A puts it on for the shift; own clothes come back at clock-off. Leaders make and change uniforms in WHIP's
// own character editor (every clothing pack the server streams, add-ons too) and set who may wear them.
(function () {
  'use strict';
  const { $, $$, esc, nui, call, said, busy, modal, confirm, toast } = J;
  let D = null, tab = 0, shown = null;
  const PART_ORDER = ['c11', 'c8', 'c3', 'c4', 'c6', 'c9', 'c10', 'c7', 'c5', 'c1', 'p0', 'p1', 'p2', 'p6', 'p7'];
  const DEFAULT_SKIP = ['p1', 'p2', 'p6', 'p7'];
  const where = () => D.where;
  const org = () => D.orgs[tab] || null;
  const rankName = (o, lvl) => { const r = (o.roles || []).find((x) => x.level === lvl) || (o.roles || []).filter((x) => x.level <= lvl).pop(); return r ? r.name : 'rank ' + lvl; };

  function partsHas(u, k) { const t = k[0] === 'c' ? u.parts.c : u.parts.p; return t && t[k.slice(1)]; }

  function card(o, u) {
    const pic = u.pics && (u.pics.c11 || u.pics.c8 || u.pics.p0);
    const other = u.body !== D.body;
    const wearing = D.wearing === u.id;
    const lockWhy = other ? `For ${u.body} characters` : (o.level < u.minLevel ? `${esc(rankName(o, u.minLevel))} and up` : (!o.onDuty && D.onlyOnDuty ? 'Clock on first' : ''));
    return `<div class="lk-card ${u.allowed ? '' : 'locked'} ${wearing ? 'on' : ''}" data-u="${u.id}" tabindex="0">
      <div class="lk-pic">${pic ? `<img src="${esc(pic)}" alt="" onerror="this.remove()">` : ''}<span class="lk-glyph">👔</span></div>
      <div class="lk-t"><b>${esc(u.name)}</b><span>${wearing ? '✔ Wearing' : (lockWhy ? '🔒 ' + lockWhy : esc(rankName(o, u.minLevel)) + ' and up')}</span></div>
      ${o.canDesign ? `<button class="btn small ghost lk-edit" data-edit="${u.id}" title="Change">✎</button>` : ''}
    </div>`;
  }

  function render() {
    const el = $('#v-locker');
    const o = org();
    const tabs = D.orgs.length > 1 ? `<div class="chips lk-tabs">${D.orgs.map((x, i) => `<button class="fchip lk-tab ${i === tab ? 'on' : ''}" data-tab="${i}">${esc(x.short || x.name)}</button>`).join('')}</div>` : '';
    let body = '';
    if (!o) body = '<div class="list-empty">You do not work for anyone at this station.</div>';
    else {
      const mine = o.uniforms.filter((u) => u.body === D.body || o.canDesign);
      if (D.onlyOnDuty && !o.onDuty) body += `<div class="banner warn">⚠ Clock on at ${esc(o.short || o.name)} to put a uniform on.</div>`;
      body += mine.length ? `<div class="lk-grid">${mine.map((u) => card(o, u)).join('')}</div>`
        : `<div class="list-empty">${esc(o.short || o.name)} has no uniforms yet.${o.canDesign ? ' Make the first one below.' : ' A leader makes them here.'}</div>`;
      if (o.canDesign) body += `<button class="btn accent lk-new" id="lk-new">＋ New uniform</button>`;
    }
    el.innerHTML = `<div class="lk-head">
        ${o ? J.logoHtml({ kind: o.kind, id: o.id, short: o.short, name: o.name, color: o.color }, '') : ''}
        <div class="t"><b>Locker room</b><span>${o ? esc(o.name) + ' · ' + esc(o.rank || '') + (o.onDuty ? ' · on duty' : '') : ''}</span></div>
        <button class="btn icon" data-close title="Close">✕</button></div>
      ${tabs}
      <div class="lk-body fade-in">${body}</div>
      <div class="lk-foot">
        <div class="row lk-view">
          <button class="btn small ghost" id="lk-left" title="Turn left">⟲</button>
          <button class="btn small ghost" id="lk-right" title="Turn right">⟳</button>
          <button class="btn small ghost" id="lk-zoom">🔍 Face / body</button>
        </div>
        <div class="row">
          ${D.wearingAny ? '<button class="btn" id="lk-own">Own clothes</button>' : ''}
          ${D.wearingAny && D.adjust ? '<button class="btn ghost" id="lk-adjust">Adjust</button>' : ''}
          ${D.personal ? '<button class="btn ghost" id="lk-personal">🗄 Personal locker</button>' : ''}
        </div>
      </div>`;
    wire(el);
  }

  async function preview(u) {
    if (shown === (u && u.id)) return;
    shown = u ? u.id : null;
    await nui('esj_preview', { parts: u && u.body === D.body ? u.parts : null });
  }
  const uniform = (id) => { for (const o of D.orgs) { const u = o.uniforms.find((x) => x.id === id); if (u) return u; } return null; };

  function wire(el) {
    const o = org();
    if (o) J.fillLogos(el, [{ kind: o.kind, id: o.id, logoVer: o.logoVer, short: o.short }]);
    $$('[data-tab]', el).forEach((b) => b.onclick = () => { tab = +b.dataset.tab; preview(null); render(); });
    $$('[data-u]', el).forEach((c) => {
      const u = uniform(+c.dataset.u);
      const pv = () => preview(u);
      c.addEventListener('mouseenter', pv); c.addEventListener('focus', pv); c.addEventListener('espcur', pv);
      c.onclick = (e) => { if (e.target.closest('[data-edit]')) return; wearIt(u, c); };
    });
    $$('[data-edit]', el).forEach((b) => b.onclick = (e) => { e.stopPropagation(); design(uniform(+b.dataset.edit)); });
    const nb = $('#lk-new', el); if (nb) { nb.onclick = () => design(null); nb.addEventListener('espcur', () => preview(null)); }
    $('#lk-left', el).onclick = () => nui('esj_turn', { by: -45 });
    $('#lk-right', el).onclick = () => nui('esj_turn', { by: 45 });
    $('#lk-zoom', el).onclick = () => nui('esj_zoom');
    const own = $('#lk-own', el); if (own) own.onclick = () => busy(own, async () => {
      const r = await call('es_jobs:uni:own', where());
      if (said(r, 'Back in your own clothes')) { shown = null; D.wearing = false; D.wearingAny = false; render(); }
    });
    const adj = $('#lk-adjust', el); if (adj) adj.onclick = () => nui('esj_adjust');
    const per = $('#lk-personal', el); if (per) per.onclick = () => nui('esj_personal');
  }

  async function wearIt(u, c) {
    if (!u.allowed) { toast(u.body !== D.body ? `That one is for ${u.body} characters` : (D.onlyOnDuty && !org().onDuty ? 'Clock on first' : 'Your rank cannot wear that one yet'), 'err'); return; }
    if (D.wearing === u.id) return;
    c.classList.add('loading');
    const r = await call('es_jobs:uni:wear', Object.assign({ id: u.id }, where()));
    c.classList.remove('loading');
    if (said(r, `${u.name} on`)) { D.wearing = u.id; D.wearingAny = true; shown = u.id; render(); }
  }

  // ---------------------------------------------------------------- leaders: make and change uniforms
  function design(u) {
    const o = org();
    const skip = u ? PART_ORDER.filter((k) => !partsHas(u, k)) : DEFAULT_SKIP.slice();
    const roles = (o.roles || []);
    const opts = [`<option value="0">Everyone at ${esc(o.short || o.name)}</option>`].concat(roles.map((r) =>
      `<option value="${r.level}" ${u && u.minLevel === r.level ? 'selected' : ''}>${esc(r.name)} (level ${r.level}) and up</option>`)).join('');
    preview(null);
    const vals = { name: '', min: 0, skip: [] };
    return modal(`<h2>${u ? 'Change uniform' : 'New uniform'}</h2>
      <p class="hint">${u ? 'Change its name and who may wear it, or open it in the editor to change the clothes.'
        : 'Name it and pick who may wear it, then dress it in the character editor: every clothing pack on the server is there, add-ons too.'}</p>
      <div class="field"><label>Name</label><input type="text" id="lu-name" maxlength="40" value="${esc(u ? u.name : '')}" placeholder="Patrol, Class A, Winter..." autofocus></div>
      <div class="field"><label>Who may wear it</label><select id="lu-min">${opts}</select></div>
      <div class="field"><label>Leave as the wearer's own</label><div class="perm-grid">${PART_ORDER.map((k) =>
        `<label class="toggle"><input type="checkbox" data-skip="${k}" ${skip.indexOf(k) >= 0 ? 'checked' : ''}> ${esc(D.parts[k] || k)}</label>`).join('')}</div>
        <span class="hint">Ticked parts stay as each wearer has them (glasses, a watch). The rest is the uniform's.</span></div>
      ${u ? `<p class="hint">Made for ${esc(u.body)} characters.${u.body !== D.body ? ' You can rename it here, but only a ' + esc(u.body) + ' character can change its clothes.' : ''}</p>` : ''}
      <div class="row end">
        ${u ? '<button class="btn danger" data-m="del">Delete</button>' : ''}
        <button class="btn ghost" data-m="no">Cancel</button>
        ${u ? '<button class="btn" data-m="save">Save</button>' : ''}
        ${!u || u.body === D.body ? `<button class="btn accent" data-m="dress">${u ? 'Change the clothes' : 'Dress it'} →</button>` : ''}
      </div>`, (c) => {
      // read the fields as a button is pressed (capture: before the modal empties itself)
      c.addEventListener('click', (e) => {
        if (!e.target.closest('[data-m]')) return;
        vals.name = $('#lu-name', c).value; vals.min = +$('#lu-min', c).value;
        vals.skip = $$('[data-skip]', c).filter((x) => x.checked).map((x) => x.dataset.skip);
      }, true);
    }).then(async (v) => {
      if (!v || v === 'no') return;
      if (v === 'del') {
        if (!(await confirm('Delete this uniform?', `${u.name} goes for everyone. Whoever wears it now keeps it until they change or clock off.`, 'Delete', true))) return;
        const r = await call('es_jobs:uni:delete', Object.assign({ id: u.id }, where()));
        if (said(r, 'Deleted')) { o.uniforms = o.uniforms.filter((x) => x.id !== u.id); render(); }
        return;
      }
      const name = (vals.name || '').trim();
      if (!name) { toast('Give it a name', 'err'); return design(u); }
      if (v === 'save') {
        const r = await call('es_jobs:uni:save', Object.assign({ jobId: o.jobId, id: u.id, name, minLevel: vals.min, skip: vals.skip }, where()));
        if (said(r, 'Saved')) { u.name = name; u.minLevel = vals.min; vals.skip.forEach((k) => { const t = k[0] === 'c' ? u.parts.c : u.parts.p; if (t) delete t[k.slice(1)]; }); render(); }
        return;
      }
      nui('esj_design', { jobId: o.jobId, id: u ? u.id : null, name, minLevel: vals.min, skip: vals.skip, org: o.name,
        wearing: D.wearing || null });
    });
  }
  J.views.locker = {
    open: (d) => { D = d; shown = null; tab = Math.max(0, D.orgs.findIndex((o) => o.uniforms.some((u) => u.id === D.wearing))); render(); },
    closed: () => { shown = null; },
    pad: { tabs: ['.lk-tab'], keys: [['Esc', 'Close'], ['Mouse', 'Hover a uniform to see it on you']],
      padExtra: [['x', 'Turn'], ['y', 'Face / body']],
      onX: () => { nui('esj_turn', { by: 45 }); return true; }, onY: () => { nui('esj_zoom'); return true; } },
  };
})();
