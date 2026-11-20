// es_jobs: controller support (copied from es_mdt 2.0.13's html/pad.js, same messages; client/pad.lua sends them).
// The game reads the pad (client/pad.lua, WHIP's Whip.padScreen: the browser cannot see a gamepad inside FiveM) and sends
//   { action: 'padState', open, nav, pad, hints, sens, keyboard }   the screen opened / closed, a setting changed
//   { action: 'pad', cmd, rep }        up down left right a b x y lb rb menu (rep: a held D-pad repeating)
//   { action: 'padAxes', lx, ly, rx, ry, lt, rt }   the sticks and triggers, only while they move
//   { action: 'padDevice', pad, hud? }  the player swapped between pad and mouse
//   { action: 'padHold', id, label, ms, kind, stop?, done? }   a held button's ring (MDT page only)
// This file moves a highlight between what can be clicked (the ring), picks with A, goes back with B (the page's own Esc),
// switches tabs with LB / RB, scrolls with LT / RT and the right stick, opens WHIP's keyboard for text boxes, drives the Live
// map, and shows button hints (controller pictures on a pad, keys on a keyboard). A page tells it its tabs:
//   window.ESPadPage = { tabs: ['#nav .nav-item'], keys: [['Esc', 'Close']] }
(function () {
  'use strict';
  const res = (() => { try { return GetParentResourceName(); } catch (e) { return 'es_mdt'; } })();
  const P = {
    open: false, nav: false, pad: false, hints: 'xbox', sens: 100, keyboard: true,
    cur: null, lastRect: null, typing: false,
    axes: { lx: 0, ly: 0, rx: 0, ry: 0, lt: 0, rt: 0 }, stick: { dir: null, next: 0 }, raf: 0, last: 0,
  };
  const page = () => window.ESPadPage || {};
  const post = (name, body) => fetch(`https://${res}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body || {}) })
    .then((r) => r.json()).catch(() => null);
  const driving = () => P.open && P.nav && P.pad;

  // ---------------------------------------------------------------- button pictures
  const XB = { a: ['A', 'xa'], b: ['B', 'xb'], x: ['X', 'xx'], y: ['Y', 'xy'], lb: ['LB', 'sh'], rb: ['RB', 'sh'], lt: ['LT', 'sh'], rt: ['RT', 'sh'],
    ls: ['LS', 'st'], rs: ['RS', 'st'], menu: ['☰', 'sh'], view: ['⧉', 'sh'], dpad: ['✚', 'dp'], dpad_up: ['▲', 'dp'], dpad_down: ['▼', 'dp'], dpad_left: ['◀', 'dp'], dpad_right: ['▶', 'dp'] };
  const PS = { a: ['✕', 'pa'], b: ['○', 'pb'], x: ['□', 'px'], y: ['△', 'py'], lb: ['L1', 'sh'], rb: ['R1', 'sh'], lt: ['L2', 'sh'], rt: ['R2', 'sh'],
    ls: ['L3', 'st'], rs: ['R3', 'st'], menu: ['OPTIONS', 'sh'], view: ['SHARE', 'sh'] };
  function glyph(name, style) {
    style = style || (P.hints === 'off' ? 'xbox' : P.hints);
    const g = (style === 'playstation' && PS[name]) || XB[name] || [String(name).toUpperCase(), 'sh'];
    return `<span class="espg ${g[1]}" data-pad-glyph="${name}">${g[0]}</span>`;
  }
  /** a WHIP slot ('lb_dpad_left', 'lb_y') as pictures */
  function slotGlyphs(slot, style) {
    if (!slot) return '';
    const parts = String(slot).split('_');
    const out = [];
    if (parts[0] === 'lb') { out.push(glyph('lb', style)); parts.shift(); }
    const rest = parts.join('_');
    if (rest) out.push(glyph(rest === 'a' || rest === 'b' || rest === 'x' || rest === 'y' || rest.indexOf('dpad') === 0 ? rest : rest, style));
    return out.join('<i class="espg-plus">+</i>');
  }
  const kbd = (k) => `<kbd class="espk">${k}</kbd>`;

  // ---------------------------------------------------------------- what can be picked
  const SEL = 'button, a[href], input:not([type=hidden]), select, textarea, [tabindex]:not([tabindex="-1"]), [data-nav], [data-go], [data-sel], [data-act], [data-case], [data-person], [data-id].click, .click, [role=button], [onclick], [data-pad]';
  let cache = null, cacheAt = 0, dirty = true;
  new MutationObserver(() => { dirty = true; }).observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'style', 'hidden', 'disabled'] });
  function shown(el) {
    if (!el.isConnected || el.closest('[data-pad-skip], .hidden, [hidden], [aria-hidden="true"]')) return false;
    if (el.disabled) return false;
    const r = el.getBoundingClientRect();
    if (r.width < 3 || r.height < 3) return false;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.pointerEvents === 'none' || +cs.opacity === 0) return false;
    return true;
  }
  /** the box an element can be seen through (its scrolling parents and the window) */
  function clipOf(el) {
    let x0 = 0, y0 = 0, x1 = window.innerWidth, y1 = window.innerHeight;
    for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
      const cs = getComputedStyle(p);
      if (/(auto|scroll|hidden)/.test(cs.overflow + cs.overflowY + cs.overflowX)) {
        const r = p.getBoundingClientRect();
        x0 = Math.max(x0, r.left); y0 = Math.max(y0, r.top); x1 = Math.min(x1, r.right); y1 = Math.min(y1, r.bottom);
      }
    }
    return { x0, y0, x1, y1 };
  }
  /** is the point covered by something that is not el (a dialog over the page) */
  function onTop(el, x, y) {
    const h = document.elementFromPoint(x, y);
    return !!h && (h === el || el.contains(h) || h.contains(el) && !h.matches(SEL));
  }
  function reachable(el) {
    const r = el.getBoundingClientRect(), c = clipOf(el);
    const cx = Math.min(Math.max(r.left + r.width / 2, c.x0 + 1), c.x1 - 1), cy = Math.min(Math.max(r.top + r.height / 2, c.y0 + 1), c.y1 - 1);
    if (c.x1 - c.x0 < 2 || c.y1 - c.y0 < 2) return false;
    const inside = r.left + r.width / 2 >= c.x0 && r.left + r.width / 2 <= c.x1 && r.top + r.height / 2 >= c.y0 && r.top + r.height / 2 <= c.y1;
    if (inside) return onTop(el, r.left + r.width / 2, r.top + r.height / 2);
    // scrolled out of sight: reachable if the box it scrolls in is not under a dialog
    let sc = el.parentElement;
    while (sc && sc !== document.body && !/(auto|scroll)/.test(getComputedStyle(sc).overflowY + getComputedStyle(sc).overflowX)) sc = sc.parentElement;
    if (!sc || sc === document.body) return false;
    const h = document.elementFromPoint(cx, cy);
    return !!h && (sc.contains(h) || h === sc);
  }
  function candidates() {
    const now = performance.now();
    if (cache && !dirty && now - cacheAt < 400) return cache;
    const set = new Set();
    document.querySelectorAll(SEL).forEach((el) => set.add(el));
    // anything drawn as clickable (a pointer cursor) that its parent is not: rows and cards with a click handler
    document.querySelectorAll('body *').forEach((el) => {
      if (set.has(el) || el.id === 'esp-ring' || el.closest('#esp-hints')) return;
      const cs = getComputedStyle(el);
      if (cs.cursor !== 'pointer') return;
      const p = el.parentElement;
      if (p && getComputedStyle(p).cursor === 'pointer') return;
      set.add(el);
    });
    const out = [];
    set.forEach((el) => {
      if (el.closest('#esp-hints, #esp-ring, #esp-hold')) return;
      if (el.tagName === 'LABEL' && el.control && set.has(el.control) && shown(el.control)) return;
      if (el.tagName === 'INPUT' && (el.type === 'checkbox' || el.type === 'radio') && !shown(el)) return;
      if (!shown(el) || !reachable(el)) return;
      out.push(el);
    });
    cache = out; cacheAt = now; dirty = false;
    return out;
  }

  // ---------------------------------------------------------------- the ring
  let ring = null;
  function ringEl() {
    if (ring) return ring;
    ring = document.createElement('div'); ring.id = 'esp-ring'; ring.setAttribute('aria-hidden', 'true');
    document.body.appendChild(ring);
    return ring;
  }
  function drawRing() {
    const r = ringEl();
    const el = P.cur;
    if (!driving() || !el || !el.isConnected) { r.classList.remove('on'); return; }
    const b = el.getBoundingClientRect(), c = clipOf(el);
    const x0 = Math.max(b.left, c.x0), y0 = Math.max(b.top, c.y0), x1 = Math.min(b.right, c.x1), y1 = Math.min(b.bottom, c.y1);
    if (x1 - x0 < 2 || y1 - y0 < 2) { r.classList.remove('on'); return; }
    r.style.transform = `translate(${x0 - 4}px, ${y0 - 4}px)`;
    r.style.width = (x1 - x0 + 8) + 'px'; r.style.height = (y1 - y0 + 8) + 'px';
    const rad = parseFloat(getComputedStyle(el).borderRadius) || 6;
    r.style.borderRadius = (rad + 4) + 'px';
    r.classList.add('on');
    P.lastRect = b;
  }
  function setCur(el, scroll) {
    if (P.cur && P.cur !== el) P.cur.classList.remove('esp-focus');
    P.cur = el || null;
    if (el) {
      el.classList.add('esp-focus');
      try { el.dispatchEvent(new CustomEvent('espcur', { bubbles: true })); } catch (e) { /* old */ }
      if (scroll !== false) { try { el.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch (e) { /* old */ } }
    }
    drawRing(); hintsDraw();
  }
  /** where to start: the active tab, else the first thing at the top left of what is on top */
  function start() {
    const list = candidates();
    if (!list.length) return null;
    const pref = (page().start && page().start()) || (map() && document.getElementById('lm-map'));
    if (pref && list.includes(pref)) return pref;
    const on = list.find((el) => el.classList.contains('on') && el.matches((page().tabs || []).join(',') || '#nav .nav-item'));
    const dialog = list.find((el) => el.closest('[role=dialog], .modal, #modal:not(.hidden), .cb-card, .rm-card, .pa-card'));
    if (dialog) {
      const d = dialog.closest('[role=dialog], .modal, #modal, .cb-card, .rm-card, .pa-card');
      const inD = list.filter((el) => d.contains(el));
      return pick(inD, 'first');
    }
    return on || pick(list, 'first');
  }
  function pick(list, how) {
    let best = null, bs = Infinity;
    list.forEach((el) => { const r = el.getBoundingClientRect(); const s = r.top * 2 + r.left; if (s < bs) { bs = s; best = el; } });
    return best;
  }

  // ---------------------------------------------------------------- moving
  function move(dir) {
    const list = candidates();
    if (!P.cur || !P.cur.isConnected || !list.includes(P.cur)) {
      // lost (re-drawn or a dialog came up): the nearest to where the ring was, else the start
      if (P.lastRect && P.cur && !P.cur.isConnected) {
        const lr = P.lastRect, cx = lr.left + lr.width / 2, cy = lr.top + lr.height / 2;
        let best = null, bd = Infinity;
        list.forEach((el) => { const r = el.getBoundingClientRect(); const d = Math.hypot(r.left + r.width / 2 - cx, r.top + r.height / 2 - cy); if (d < bd) { bd = d; best = el; } });
        if (best) return setCur(best);
      }
      return setCur(start());
    }
    const a = P.cur.getBoundingClientRect();
    const acx = a.left + a.width / 2, acy = a.top + a.height / 2;
    let best = null, bs = Infinity;
    list.forEach((el) => {
      if (el === P.cur || el.contains(P.cur)) return;
      const b = el.getBoundingClientRect();
      const bcx = b.left + b.width / 2, bcy = b.top + b.height / 2;
      let major, minor, overlap;
      if (dir === 'down') { if (bcy <= acy + 2 || b.bottom <= a.bottom - 1 && !P.cur.contains(el)) return; major = Math.max(0, b.top - a.bottom); minor = Math.abs(bcx - acx); overlap = b.left < a.right && b.right > a.left; }
      else if (dir === 'up') { if (bcy >= acy - 2 || b.top >= a.top + 1 && !P.cur.contains(el)) return; major = Math.max(0, a.top - b.bottom); minor = Math.abs(bcx - acx); overlap = b.left < a.right && b.right > a.left; }
      else if (dir === 'right') { if (bcx <= acx + 2) return; major = Math.max(0, b.left - a.right); minor = Math.abs(bcy - acy); overlap = b.top < a.bottom && b.bottom > a.top; }
      else { if (bcx >= acx - 2) return; major = Math.max(0, a.left - b.right); minor = Math.abs(bcy - acy); overlap = b.top < a.bottom && b.bottom > a.top; }
      const s = overlap ? major + minor * 0.25 : major + minor * 2 + 300;
      if (s < bs) { bs = s; best = el; }
    });
    if (best) return setCur(best);
    // nothing that way: scroll the list it is in (long lists load more as they scroll)
    if (dir === 'down' || dir === 'up') scrollBy(dir === 'down' ? 160 : -160);
  }

  // ---------------------------------------------------------------- picking, typing, back
  const TEXT = /^(text|search|email|number|tel|url|password|date|datetime-local|time|)$/;
  function isText(el) { return (el.tagName === 'INPUT' && TEXT.test(el.type || '')) || el.tagName === 'TEXTAREA' || el.isContentEditable; }
  function labelOf(el) {
    const f = el.closest('.field, label, .form-row, .fld');
    const l = (el.labels && el.labels[0]) || (f && f.querySelector('label'));
    return ((l && l.textContent) || el.getAttribute('aria-label') || el.placeholder || el.name || 'Type').trim().slice(0, 80);
  }
  function setValue(el, v) {
    if (el.isContentEditable) el.textContent = v;
    else {
      const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const d = Object.getOwnPropertyDescriptor(proto, 'value');
      if (d && d.set) d.set.call(el, v); else el.value = v;
    }
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  function type(el) {
    if (!P.keyboard) { el.focus(); return; }
    if (P.typing) return;
    P.typing = true; hintsDraw();
    const max = +el.getAttribute('maxlength') > 0 ? +el.getAttribute('maxlength') : (el.tagName === 'TEXTAREA' ? 2000 : 255);
    post('esui_padKeyboard', {
      title: labelOf(el), value: el.isContentEditable ? el.textContent : el.value, placeholder: el.placeholder || '',
      maxLength: max, numeric: el.type === 'number', predict: !(el.dataset.padPredict === 'false' || /plate|serial|code|id\b/i.test(el.id + ' ' + el.name + ' ' + (el.placeholder || ''))),
    }).then((r) => {
      P.typing = false;
      if (r && r.ok && typeof r.text === 'string') {
        setValue(el, r.text);
        // a one-line box that sends with Enter (searches, notes): Enter as the keyboard would
        if (el.tagName === 'INPUT' && el.dataset.padEnter !== 'false') el.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
      } else if (r && r.why === 'off') el.focus();
      hintsDraw(); drawRing();
    });
  }
  function stepSelect(el, d) {
    const n = el.options.length; if (!n) return;
    let i = el.selectedIndex;
    for (let k = 0; k < n; k++) { i = (i + d + n) % n; if (!el.options[i].disabled) break; }
    el.selectedIndex = i;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  function stepRange(el, d) {
    const st = +el.step || 1, v = Math.min(+el.max || 100, Math.max(+el.min || 0, (+el.value || 0) + d * st));
    setValue(el, String(v));
  }
  function press(el) {
    if (!el) return;
    if (page().onPress && page().onPress(el) === true) return;
    if (isText(el)) return type(el);
    if (el.tagName === 'SELECT') return stepSelect(el, 1);
    if (el.tagName === 'INPUT' && el.type === 'range') return;
    if (el.tagName === 'INPUT' && el.type === 'file') return el.click();
    const r = el.getBoundingClientRect(), o = { bubbles: true, cancelable: true, view: window, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2, button: 0 };
    el.dispatchEvent(new MouseEvent('mousedown', o));
    el.dispatchEvent(new MouseEvent('mouseup', o));
    el.click();
    if (el.tagName === 'INPUT' || el.tagName === 'SELECT') try { el.focus({ preventScroll: true }); } catch (e) { /* */ }
  }
  function key(k, target) {
    const t = target || document.activeElement || document.body;
    const ev = new KeyboardEvent('keydown', { key: k, code: k, bubbles: true, cancelable: true });
    t.dispatchEvent(ev);
  }
  function back() {
    if (page().back && page().back() === true) return;
    const ae = document.activeElement;
    // typing with a real keyboard: Esc leaves the box first. On a pad nothing is being typed there (WHIP's keyboard is), so straight back
    if (!driving() && ae && ae !== document.body && isText(ae)) { ae.blur(); return; }
    if (ae && isText(ae)) ae.blur();
    key('Escape', document.body);
  }

  // ---------------------------------------------------------------- tabs, scrolling
  function tabs(d) {
    for (const sel of (page().tabs || ['#nav .nav-item'])) {
      const all = Array.from(document.querySelectorAll(sel)).filter((el) => shown(el) && reachable(el));
      if (all.length < 2) continue;
      let i = all.findIndex((el) => el.classList.contains('on') || el.classList.contains('active') || el.getAttribute('aria-selected') === 'true');
      i = ((i < 0 ? (d > 0 ? -1 : 0) : i) + d + all.length) % all.length;
      press(all[i]);
      setCur(all[i]);
      return;
    }
  }
  function scroller(from) {
    for (let p = from; p && p !== document.documentElement; p = p.parentElement) {
      const cs = getComputedStyle(p);
      if (/(auto|scroll)/.test(cs.overflowY) && p.scrollHeight > p.clientHeight + 2) return p;
    }
    // else the biggest scrolling box on screen
    let best = null, area = 0;
    document.querySelectorAll('body *').forEach((el) => {
      if (el.scrollHeight <= el.clientHeight + 2) return;
      const cs = getComputedStyle(el); if (!/(auto|scroll)/.test(cs.overflowY)) return;
      const r = el.getBoundingClientRect(); if (r.width * r.height <= area || !onTop(el, r.left + r.width / 2, r.top + Math.min(r.height / 2, 40))) return;
      area = r.width * r.height; best = el;
    });
    return best;
  }
  function scrollBy(px) {
    const s = scroller(P.cur && P.cur.isConnected ? P.cur : null);
    if (s) s.scrollTop += px;
    drawRing();
  }

  // ---------------------------------------------------------------- the Live map (html/mdt/livemap.js says how: window.ESPadMap)
  const map = () => { const m = window.ESPadMap; return m && m.active && m.active() ? m : null; };

  // ---------------------------------------------------------------- sticks and triggers (a frame loop only while one is moved)
  const k = () => Math.max(0.25, Math.min(3, (P.sens || 100) / 100));
  function axesFrame(t) {
    P.raf = 0;
    if (!driving()) return;
    const A = P.axes, dt = Math.min(0.1, Math.max(0, (t - (P.last || t)) / 1000)); P.last = t;
    const m = map();
    if (m) {
      if (A.lx || A.ly) m.pan(-A.lx * 900 * k() * dt, -A.ly * 900 * k() * dt);
      const z = (A.rt - A.lt) + (-A.ry);
      if (Math.abs(z) > 0.05) m.zoom(Math.exp(z * 1.6 * k() * dt));
    } else {
      const v = A.ry + (A.rt - A.lt);
      if (Math.abs(v) > 0.05) scrollBy(v * 1100 * k() * dt);
      // the left stick steps like the D-pad (as WHIP's menus: past 0.6, then repeats)
      const dir = Math.abs(A.lx) > Math.abs(A.ly) ? (A.lx > 0.6 ? 'right' : A.lx < -0.6 ? 'left' : null) : (A.ly > 0.6 ? 'down' : A.ly < -0.6 ? 'up' : null);
      if (dir !== P.stick.dir) { P.stick.dir = dir; if (dir) { stepDir(dir); P.stick.next = t + 380; } }
      else if (dir && t >= P.stick.next) { stepDir(dir); P.stick.next = t + 110 / k(); }
    }
    if (A.lx || A.ly || A.rx || A.ry || A.lt || A.rt) P.raf = requestAnimationFrame(axesFrame);
    else { P.last = 0; P.stick.dir = null; }
  }
  function stepDir(dir) {
    const el = P.cur;
    if (el && el.tagName === 'SELECT' && (dir === 'left' || dir === 'right')) return stepSelect(el, dir === 'right' ? 1 : -1);
    if (el && el.tagName === 'INPUT' && el.type === 'range' && (dir === 'left' || dir === 'right')) return stepRange(el, dir === 'right' ? 1 : -1);
    move(dir);
  }

  // ---------------------------------------------------------------- the buttons
  function onPad(cmd) {
    if (!driving() || P.typing) return;
    if (!P.cur || !P.cur.isConnected) { if (cmd === 'up' || cmd === 'down' || cmd === 'left' || cmd === 'right' || cmd === 'a') { const s = start(); if (s) { setCur(s); if (cmd !== 'a') return; } } }
    const m = map();
    switch (cmd) {
      case 'up': case 'down': case 'left': case 'right': return stepDir(cmd);
      case 'a':
        if (m && (!P.cur || P.cur.closest('#lm-map') && !P.cur.closest('.lm-tools, .lm-top, .lm-detail, #lm-layers'))) { m.nearest(); return; }
        return press(P.cur);
      case 'b': return back();
      case 'menu': if (page().close) page().close(); else back(); return;
      case 'lb': return tabs(-1);
      case 'rb': return tabs(1);
      case 'x': {
        if (m) return m.fit && m.fit();
        if (page().onX && page().onX() === true) return;
        const s = Array.from(document.querySelectorAll(page().search || '#gsearch, input[type=search], #lm-q, input[placeholder*="Search" i]')).find((el) => shown(el) && reachable(el));
        if (s) { setCur(s); type(s); }
        return;
      }
      case 'y': {
        if (m) return m.me && m.me();
        if (page().onY && page().onY() === true) return;
        const t = Array.from(document.querySelectorAll((page().tabs || ['#nav .nav-item']).join(','))).find((el) => (el.classList.contains('on') || el.classList.contains('active')) && shown(el) && reachable(el));
        if (t) setCur(t);
        return;
      }
    }
  }

  // ---------------------------------------------------------------- hints
  let bar = null;
  function hintsDraw() {
    if (!bar) { bar = document.createElement('div'); bar.id = 'esp-hints'; bar.setAttribute('aria-hidden', 'true'); document.body.appendChild(bar); }
    const show = P.open && P.hints !== 'off' && (P.pad ? P.nav : true) && !(page().hints === false);
    document.documentElement.classList.toggle('esp-pad', driving());
    if (!show) { bar.classList.remove('on'); return; }
    const h = [];
    const add = (g, t) => h.push(`<span class="esp-h">${g}<em>${t}</em></span>`);
    if (P.pad) {
      const m = map(), el = P.cur && P.cur.isConnected ? P.cur : null;
      if (P.typing) add(glyph('a') + glyph('b'), 'On-screen keyboard');
      else if (m) { add(glyph('ls'), 'Move map'); add(glyph('rs') + glyph('lt') + glyph('rt'), 'Zoom'); add(glyph('a'), 'Nearest pin'); add(glyph('x'), 'Fit all'); add(glyph('y'), 'My unit'); add(glyph('dpad'), 'Buttons'); }
      else {
        add(glyph('dpad') + glyph('ls'), 'Move');
        add(glyph('a'), el && isText(el) ? (P.keyboard ? 'Type' : 'Edit') : el && el.tagName === 'SELECT' ? 'Next option' : 'Select');
        if (el && (el.tagName === 'SELECT' || el.type === 'range')) add(glyph('dpad_left') + glyph('dpad_right'), 'Change');
        const t = (page().tabs || ['#nav .nav-item']).some((s) => Array.from(document.querySelectorAll(s)).filter((x) => shown(x)).length > 1);
        if (t) add(glyph('lb') + glyph('rb'), 'Tabs');
        add(glyph('lt') + glyph('rt'), 'Scroll');
        (page().padExtra || []).forEach(([g, t]) => add(g.split('+').map((x) => glyph(x)).join(''), t));
      }
      add(glyph('b'), 'Back');
    } else {
      ((typeof page().keys === 'function' ? page().keys() : page().keys) || [['Esc', 'Back / close']]).forEach(([k2, t]) => add(k2.split('+').map(kbd).join('<i class="espg-plus">+</i>'), t));
    }
    bar.innerHTML = h.join('');
    bar.classList.toggle('ps', P.hints === 'playstation');
    bar.classList.add('on');
  }

  // ---------------------------------------------------------------- the hold ring (panic, hide a call, the radar remote)
  let hold = null, holdT = null;
  function holdRing(m) {
    if (!hold) { hold = document.createElement('div'); hold.id = 'esp-hold'; hold.setAttribute('aria-hidden', 'true'); document.body.appendChild(hold); }
    clearTimeout(holdT);
    if (m.stop) {
      if (hold.dataset.id && hold.dataset.id !== String(m.id)) return;
      hold.classList.toggle('done', !!m.done);
      holdT = setTimeout(() => { hold.classList.remove('on', 'done'); hold.dataset.id = ''; }, m.done ? 700 : 0);
      return;
    }
    const ms = Math.max(100, +m.ms || 1000);
    hold.dataset.id = String(m.id || '');
    hold.className = 'on' + (m.kind === 'panic' ? ' panic' : '');
    hold.innerHTML = `<svg viewBox="0 0 44 44"><circle class="bg" cx="22" cy="22" r="19"/><circle class="fg" cx="22" cy="22" r="19" style="animation-duration:${ms}ms"/></svg><span>${String(m.label || 'Hold').replace(/[<>&]/g, '')}</span>`;
  }

  // ---------------------------------------------------------------- the game's messages
  let raf2 = 0;
  function keepRing() { raf2 = 0; if (!driving()) return; drawRing(); raf2 = requestAnimationFrame(keepRing); }
  function stateChanged() {
    hintsDraw();
    if (driving()) { if (!P.cur || !P.cur.isConnected) setTimeout(() => { if (driving() && (!P.cur || !P.cur.isConnected)) setCur(start(), false); }, 60); if (!raf2) raf2 = requestAnimationFrame(keepRing); }
    else { if (P.cur) P.cur.classList.remove('esp-focus'); drawRing(); }
    document.dispatchEvent(new CustomEvent('espad:state', { detail: { pad: P.pad, hints: P.hints, open: P.open } }));
  }
  window.addEventListener('message', (e) => {
    let m = e.data;
    if (typeof m === 'string') { try { m = JSON.parse(m); } catch (x) { return; } }
    if (!m || typeof m.action !== 'string' || m.action.indexOf('pad') !== 0) return;
    if (m.action === 'padState') {
      const was = P.open;
      P.open = !!m.open;
      if (m.nav != null) P.nav = !!m.nav;
      if (m.pad != null) P.pad = !!m.pad;
      if (m.hints) P.hints = m.hints;
      if (m.sens) P.sens = +m.sens;
      if (m.keyboard != null) P.keyboard = !!m.keyboard;
      if (!P.open) { P.cur = null; P.typing = false; P.axes = { lx: 0, ly: 0, rx: 0, ry: 0, lt: 0, rt: 0 }; }
      else if (!was) P.cur = null;
      stateChanged();
    } else if (m.action === 'padDevice') {
      P.pad = !!m.pad;
      if (m.hints) P.hints = m.hints;
      stateChanged();
    } else if (m.action === 'pad') {
      onPad(String(m.cmd || ''));
      hintsDraw();
    } else if (m.action === 'padAxes') {
      P.axes = { lx: +m.lx || 0, ly: +m.ly || 0, rx: +m.rx || 0, ry: +m.ry || 0, lt: +m.lt || 0, rt: +m.rt || 0 };
      if (!P.raf && driving()) P.raf = requestAnimationFrame(axesFrame);
    } else if (m.action === 'padHold') holdRing(m);
  });
  // the mouse is back: the ring goes until the pad is used again (the game also says so with padDevice)
  window.addEventListener('resize', () => { dirty = true; drawRing(); });
  document.addEventListener('scroll', () => { if (driving()) drawRing(); }, true);

  window.ESPad = { glyph, slotGlyphs, state: () => Object.assign({}, P, { cur: undefined }), move, press, back, tabs, onPad, setCur, candidates, cur: () => P.cur, hints: hintsDraw };
})();
