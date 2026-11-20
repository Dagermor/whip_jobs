// es_jobs page core. Views: spot (duty / armory / garage), stations (the editor), business. The game (client/main.lua)
// sends { action: 'open', view, data }; the page asks the server with J.call(name, data) (an es_jobs SecureCallback).
(function () {
  'use strict';
  const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'es_jobs';
  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  async function nui(name, data) {
    try {
      const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) });
      return await r.json();
    } catch (e) { return { ok: false, why: 'The game did not answer' }; }
  }
  /** a server call: { ok, data, why } */
  const call = (name, data) => nui('esj_call', { name, data: data || {} });

  let toastTimer = null;
  function toast(text, kind) {
    const t = $('#toast');
    t.innerHTML = `<span class="t-dot"></span><span>${esc(text)}</span>`;
    t.className = 'toast show ' + (kind || '');
    clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('show'), 3400);
  }
  function said(r, okText) {
    if (r && r.ok) { if (okText) toast(okText, 'ok'); return true; }
    toast((r && r.why) || 'That did not work', 'err');
    return false;
  }
  async function busy(btn, fn) {
    if (!btn || btn.disabled) return;
    const label = btn.innerHTML; btn.disabled = true; btn.classList.add('loading');
    try { return await fn(); } finally { btn.disabled = false; btn.classList.remove('loading'); btn.innerHTML = label; }
  }

  // ---------------------------------------------------------------- modal (B / Esc closes it first)
  let modalClose = null;
  function modal(html, onReady) {
    const m = $('#modal'), c = $('.modal-card', m);
    c.innerHTML = html; m.classList.remove('hidden');
    return new Promise((res) => {
      modalClose = (v) => { m.classList.add('hidden'); c.innerHTML = ''; modalClose = null; res(v); };
      m.onclick = (e) => { if (e.target === m) modalClose(null); };
      $$('[data-m]', c).forEach((b) => b.onclick = () => modalClose && modalClose(b.dataset.m));
      if (onReady) onReady(c, (v) => modalClose && modalClose(v));
      const first = $('[autofocus]', c); if (first) first.focus();
    });
  }
  function confirm(title, text, yes, danger) {
    return modal(`<h2>${esc(title)}</h2><p>${esc(text)}</p><div class="row end"><button class="btn ghost" data-m="no">Cancel</button>
      <button class="btn ${danger ? 'danger' : 'accent'}" data-m="yes">${esc(yes || 'OK')}</button></div>`).then((v) => v === 'yes');
  }

  // ---------------------------------------------------------------- logos and pictures
  const logos = {};
  /** a department's (es_mdt) or a business's (ours) logo, as a data URL, or null */
  async function logoOf(o) {
    if (!o || !o.logoVer) return null;
    const k = o.kind + ':' + o.id, have = logos[k];
    if (have && have.ver === o.logoVer) return have.data;
    let data = null;
    if (o.kind === 'dept') {
      const r = await nui('esj_deptLogo', { id: o.id, ver: o.logoVer });
      data = r && r.ok ? r.url : null;
    } else {
      const first = await call('es_jobs:biz:logo', { id: o.id, i: 1 });
      if (first.ok && first.data.total > 0) {
        const parts = [first.data.part];
        for (let i = 2; i <= first.data.total; i++) {
          const p = await call('es_jobs:biz:logo', { id: o.id, i });
          if (!p.ok) return null;
          parts.push(p.data.part);
        }
        data = parts.join('');
      }
    }
    if (data) logos[k] = { ver: o.logoVer, data };
    return data;
  }
  function setLogo(k, ver, data) { logos[k] = { ver, data }; }
  /** a round logo badge: the logo once it loads, the short name on the org's colour until then */
  function logoEl(o, size) {
    const el = document.createElement('div');
    el.className = 'org-logo' + (size ? ' ' + size : '');
    el.style.setProperty('--oc', (o && o.color) || '#334155');
    el.textContent = ((o && (o.short || o.name)) || '?').slice(0, 5);
    if (o) logoOf(o).then((src) => { if (src) { el.classList.add('has'); el.innerHTML = `<img src="${src}" alt="">`; } });
    return el;
  }
  const logoHtml = (o, size) => `<span data-logo="${esc(o.kind)}:${esc(o.id)}" class="org-logo ${size || ''}" style="--oc:${esc(o.color || '#334155')}">${esc((o.short || o.name || '?').slice(0, 5))}</span>`;
  /** fill every [data-logo] placeholder under root */
  function fillLogos(root, orgs) {
    $$('[data-logo]', root).forEach((el) => {
      const [kind, id] = el.dataset.logo.split(':');
      const o = orgs.find((x) => x.kind === kind && String(x.id) === id);
      if (o) logoOf(o).then((src) => { if (src && el.isConnected) { el.classList.add('has'); el.innerHTML = `<img src="${src}" alt="">`; } });
    });
  }
  // pictures: items from whip_core, peds and vehicles from FiveM's docs (a letter tile when there is none)
  const itemImg = (key, img) => img || `https://cfx-nui-whip_core/html/img/items/${encodeURIComponent(key)}.png`;
  const pedImg = (m) => `https://docs.fivem.net/peds/${encodeURIComponent(String(m || '').toLowerCase())}.webp`;
  const vehImg = (m, img) => img || `https://docs.fivem.net/vehicles/${encodeURIComponent(String(m || '').toLowerCase())}.webp`;
  /** <img> that turns into a placeholder when the picture is missing */
  const img = (src, cls, fallback) => `<img class="${cls || ''}" src="${esc(src)}" alt="" onerror="this.outerHTML='<div class=&quot;${cls || ''} noimg&quot;>${esc(fallback || '?')}</div>'">`;

  const money = (n) => (n < 0 ? '-$' : '$') + Math.abs(Math.round(n || 0)).toLocaleString('en-US');
  function ago(t) {
    const s = Math.max(0, Math.floor(Date.now() / 1000 - t));
    if (s < 60) return 'just now'; if (s < 3600) return Math.floor(s / 60) + ' min ago';
    if (s < 86400) return Math.floor(s / 3600) + ' h ago'; return Math.floor(s / 86400) + ' d ago';
  }

  // ---------------------------------------------------------------- views
  const J = window.J = { $, $$, esc, nui, call, toast, said, busy, modal, confirm, logoOf, logoEl, logoHtml, fillLogos, setLogo, itemImg, pedImg, vehImg, img,
    money, ago, views: {}, view: null, me: {} };

  function show(view, data) {
    $$('#app > .shell').forEach((s) => s.classList.add('hidden'));
    const el = $('#v-' + view);
    if (!el) return;
    el.classList.remove('hidden');
    J.view = view;
    $('#app').dataset.view = view;
    const v = J.views[view];
    window.ESPadPage = (v && v.pad) || { keys: [['Esc', 'Close']] };
    if (v && v.open) v.open(data || {});
    if (window.ESPad) window.ESPad.hints();   // this view's buttons, not the last one's
  }
  J.show = show;
  function close() {
    if (modalClose) { modalClose(null); return; }
    const v = J.views[J.view];
    if (v && v.back && v.back()) return;   // the view went back a step instead
    $('#app').classList.remove('shown');
    setTimeout(() => $('#app').classList.add('hidden'), 160);
    nui('esj_close');
  }
  J.close = close;
  document.addEventListener('click', (e) => { if (e.target.closest('[data-close]')) close(); });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('#app').classList.contains('hidden')) {
      const t = e.target.tagName;
      if ((t === 'INPUT' || t === 'TEXTAREA') && !modalClose) { e.target.blur(); return; }
      e.preventDefault(); close();
    }
  });

  window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'open') {
      J.me = m.me || {};
      $('#app').classList.remove('hidden'); requestAnimationFrame(() => $('#app').classList.add('shown'));
      show(m.view, m.data);
    } else if (m.action === 'close') {
      if (modalClose) modalClose(null);
      $('#app').classList.remove('shown'); $('#app').classList.add('hidden');
      const v = J.views[J.view]; if (v && v.closed) v.closed();
    } else if (m.action === 'hide') {
      // the game is placing a ghost: the page steps out of the way
      $('#app').style.visibility = m.on ? 'hidden' : '';
    } else if (m.action === 'bizChanged') {
      const v = J.views[J.view]; if (v && v.changed) v.changed(m.id);
    }
  });
})();
