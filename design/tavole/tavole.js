/* SubVision 2.0 · design boards: shared runtime and components.
 * Components follow AnimeUp 2.1's design system (AnimeUpKit/DesignSystem), copied for
 * SubVision: SidebarTab, ActivityCard, NoteView, StatusChip, AUBar, AUButtonStyle,
 * AUAlert, SettingsRow, CapsuleSegments, TopBarSegment. Icons are simple inline SVG
 * stand-ins for SF Symbols; the final icons come in F4.
 *
 * URL parameters: ?theme=light|dark|system  ?lang=en|it  ?board=E2 (one board, for screenshots)
 *                 ?list=1 (writes the board manifest into #manifest, for screenshot.sh)
 */
(function () {
  const P = new URLSearchParams(location.search);
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch (e) {} },
  };
  const S = window.SV = {};
  S.theme = P.get('theme') || store.get('sv-theme') || 'system';
  S.lang = P.get('lang') || store.get('sv-lang') || 'it';
  S.only = P.get('board');
  if (S.only) document.documentElement.classList.add('shot');

  function applyTheme() {
    const sys = matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
    document.documentElement.dataset.theme = S.theme === 'system' ? sys : S.theme;
  }
  applyTheme();
  matchMedia('(prefers-color-scheme: light)').addEventListener('change', applyTheme);

  // ---------- strings
  const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  S.esc = esc;
  /** t(key, vars): the string in the current language; {x} filled from vars. Unknown keys show in red. */
  S.t = function (key, vars) {
    const STR = window.STR || {};
    let e = STR[key];
    // plurals: <key>.uno / <key>.altri, chosen by vars.n (the Localizer's scheme)
    if (!e && STR[key + '.uno']) e = STR[key + ((vars && Number(vars.n) === 1) ? '.uno' : '.altri')];
    if (!e) return `<span class="missing">${esc(key)}</span>`;
    let s = e[S.lang === 'en' ? 0 : 1];
    s = s.replace(/\{\{/g, '\u0001').replace(/\}\}/g, '\u0002');
    if (vars) s = s.replace(/\{(\w+)\}/g, (m, k) => (k in vars ? vars[k] : m));
    if (/\{\w+\}/.test(s)) return `<span class="missing">${esc(key)}: ${esc(s)}</span>`;
    return s.replace(/\u0001/g, '{').replace(/\u0002/g, '}');
  };
  /** Joins parts with the catalog's separator (" · "). */
  S.tj = (...parts) => parts.join(S.t('app.common.list_separator'));
  const t = S.t;

  // ---------- icons (SF Symbol stand-ins)
  const ICONS = {
    gear: '<circle cx="8" cy="8" r="2.3"/><path d="M8 1.6v1.7M8 12.7v1.7M1.6 8h1.7M12.7 8h1.7M3.5 3.5l1.2 1.2M11.3 11.3l1.2 1.2M3.5 12.5l1.2-1.2M11.3 4.7l1.2-1.2"/><circle cx="8" cy="8" r="4.6"/>',
    process: '<rect x="1.8" y="3" width="12.4" height="9" rx="2"/><path d="M4.5 9.5h7M5.5 7.3h5"/>',
    preview: '<path d="M2 5V3.2C2 2.5 2.5 2 3.2 2H5M11 2h1.8c.7 0 1.2.5 1.2 1.2V5M14 11v1.8c0 .7-.5 1.2-1.2 1.2H11M5 14H3.2C2.5 14 2 13.5 2 12.8V11"/><path d="M4.5 10.5h7"/>',
    fix: '<path d="M2.5 4h8M2.5 7.5h6M2.5 11h4"/><path d="M9.5 11.2l1.8 1.8 3.2-3.6"/>',
    inspector: '<rect x="1.8" y="2.5" width="12.4" height="11" rx="2"/><path d="M10 2.5v11"/>',
    sidebar: '<rect x="1.8" y="2.5" width="12.4" height="11" rx="2"/><path d="M6 2.5v11"/>',
    chevD: '<path d="M4 6l4 4 4-4"/>', chevR: '<path d="M6 4l4 4-4 4"/>', chevL: '<path d="M10 4l-4 4 4 4"/>',
    updown: '<path d="M5 6l3-3 3 3M5 10l3 3 3-3"/>',
    check: '<path d="M3.5 8.3l3 3 6-6.6"/>', x: '<path d="M4.5 4.5l7 7M11.5 4.5l-7 7"/>',
    stop: '<rect x="4" y="4" width="8" height="8" rx="1.5" fill="currentColor"/>',
    play: '<path d="M5 3.5v9l7.5-4.5z" fill="currentColor"/>',
    folder: '<path d="M1.8 4.2c0-.8.6-1.4 1.4-1.4h3l1.4 1.6h5.2c.8 0 1.4.6 1.4 1.4v6c0 .8-.6 1.4-1.4 1.4H3.2c-.8 0-1.4-.6-1.4-1.4z"/>',
    doc: '<path d="M4 1.8h5l3 3v9.4H4z"/><path d="M9 1.8v3h3"/>',
    plus: '<path d="M8 3v10M3 8h10"/>', minus: '<path d="M3 8h10"/>',
    refresh: '<path d="M13 8a5 5 0 1 1-1.5-3.6"/><path d="M13 2.5v3h-3"/>',
    up: '<path d="M8 13V3M4 7l4-4 4 4"/>', ext: '<path d="M6 3h7v7M13 3l-8 8"/>',
    info: '<circle cx="8" cy="8" r="6.2"/><path d="M8 7.2v4M8 4.8v.1"/>',
    warn: '<path d="M8 1.8l6.6 11.6H1.4z"/><path d="M8 6.2v3.4M8 11.4v.1"/>',
    err: '<path d="M5.3 1.8h5.4l3.5 3.5v5.4l-3.5 3.5H5.3l-3.5-3.5V5.3z"/><path d="M8 4.8v3.8M8 11v.1"/>',
    ok: '<circle cx="8" cy="8" r="6.2"/><path d="M5 8.2l2 2 4-4.4"/>',
    dots: '<circle cx="3.5" cy="8" r="1" fill="currentColor"/><circle cx="8" cy="8" r="1" fill="currentColor"/><circle cx="12.5" cy="8" r="1" fill="currentColor"/>',
    search: '<circle cx="7" cy="7" r="4.3"/><path d="M10.2 10.2l3.6 3.6"/>',
    film: '<rect x="2" y="2.5" width="12" height="11" rx="1.5"/><path d="M5 2.5v11M11 2.5v11M2 6h3M2 10h3M11 6h3M11 10h3"/>',
    globe: '<circle cx="8" cy="8" r="6.2"/><path d="M1.8 8h12.4M8 1.8c2 2 2 10.4 0 12.4M8 1.8c-2 2-2 10.4 0 12.4"/>',
    list: '<path d="M5.5 4h8M5.5 8h8M5.5 12h8"/><circle cx="2.8" cy="4" r=".8" fill="currentColor"/><circle cx="2.8" cy="8" r=".8" fill="currentColor"/><circle cx="2.8" cy="12" r=".8" fill="currentColor"/>',
    wrench: '<path d="M10.5 2a3.3 3.3 0 0 0-3.2 4.3L2.5 11.1 4.9 13.5l4.8-4.8A3.3 3.3 0 0 0 14 5.5l-2 2-2-.5-.5-2z"/>',
    arrowcircle: '<circle cx="8" cy="8" r="6.2"/><path d="M8 4.8v6.4M5.3 8.7L8 11.3l2.7-2.6"/>',
    bell: '<path d="M4 11V7.3a4 4 0 0 1 8 0V11l1.2 1.2H2.8z"/><path d="M6.6 13.6a1.5 1.5 0 0 0 2.8 0"/>',
    trash: '<path d="M3 4.5h10M6 4.5V3h4v1.5M4.3 4.5l.6 9h6.2l.6-9"/>',
    github: '<path d="M8 1.6a6.4 6.4 0 0 0-2 12.5c.3 0 .4-.1.4-.3v-1.1c-1.8.4-2.2-.8-2.2-.8-.3-.7-.7-1-.7-1-.6-.4 0-.4 0-.4.6.1 1 .7 1 .7.6 1 1.5.7 1.9.5 0-.4.2-.7.4-.9-1.4-.2-2.9-.7-2.9-3.2 0-.7.2-1.3.7-1.7-.1-.2-.3-.8.1-1.7 0 0 .5-.2 1.8.7a6 6 0 0 1 3.2 0c1.2-.8 1.8-.7 1.8-.7.3.9.1 1.5.1 1.7.4.4.7 1 .7 1.7 0 2.5-1.5 3-2.9 3.2.2.2.4.6.4 1.2v1.8c0 .2.1.4.4.3A6.4 6.4 0 0 0 8 1.6z" fill="currentColor" stroke="none"/>',
    // alert icons (40 pt, outline): SubVision's own drawings come in F4
    'a-stop-file': '<rect x="3" y="2" width="22" height="28" rx="3"/><path d="M8 9h12M8 14h8"/><circle cx="27" cy="27" r="9"/><rect x="23.5" y="23.5" width="7" height="7" rx="1.2" fill="currentColor"/>',
    'a-stop-all': '<rect x="2" y="6" width="18" height="24" rx="3"/><rect x="8" y="2" width="18" height="24" rx="3"/><circle cx="28" cy="28" r="9"/><rect x="24.5" y="24.5" width="7" height="7" rx="1.2" fill="currentColor"/>',
    'a-quit': '<path d="M16 5v13"/><path d="M10 8.5a11.5 11.5 0 1 0 12 0"/>',
    'a-window-close': '<rect x="3" y="6" width="34" height="26" rx="4"/><path d="M3 13h34"/><circle cx="8.5" cy="9.5" r="1.4" fill="currentColor"/><circle cx="13" cy="9.5" r="1.4"/><circle cx="17.5" cy="9.5" r="1.4"/><path d="M15 25l4 3 7-8"/>',
    'a-tool-missing': '<rect x="4" y="8" width="32" height="24" rx="3"/><path d="M4 14h32M10 8v24M30 8v24"/><path d="M16 20l8 8M24 20l-8 8"/>',
    'a-vision': '<path d="M3 20s6-10 17-10 17 10 17 10-6 10-17 10S3 20 3 20z"/><circle cx="20" cy="20" r="5"/><path d="M6 34L34 6"/>',
    'a-language': '<circle cx="20" cy="20" r="15"/><path d="M5 20h30M20 5c5 5 5 25 0 30M20 5c-5 5-5 25 0 30"/><path d="M28 28l8 8M36 28l-8 8"/>',
    'a-folder-empty': '<path d="M3 11c0-1.7 1.3-3 3-3h8l3 4h17c1.7 0 3 1.3 3 3v15c0 1.7-1.3 3-3 3H6c-1.7 0-3-1.3-3-3z"/><path d="M15 23h10" stroke-dasharray="2 3"/>',
    'a-info': '<circle cx="20" cy="20" r="15"/><path d="M20 17v11M20 12v.2"/>',
    'a-update': '<circle cx="20" cy="20" r="15"/><path d="M20 12v15M14 21l6 6 6-6"/>',
    'a-error': '<path d="M13 4h14l9 9v14l-9 9H13l-9-9V13z"/><path d="M20 12v10M20 27v.2"/>',
    'a-list': '<rect x="7" y="4" width="26" height="32" rx="3"/><path d="M13 13h14M13 19h14M13 25h9"/><path d="M28 30l4 4"/>',
  };
  /** Sizes: the stand-ins draw inside ~78 % of their box, so a box is ~1.3× the SF symbol point size
   *  of SVDesign (sidebar tab 14 pt → 20, gear 13 → 18, top bar segment 12 → 15, button 12/11/10 → 15/13/12,
   *  note 14 → 18, row status 10 → 13); alert icons fill their 40 pt box. Note-design ?37. */
  S.icon = function (name, size = 14, cls = '') {
    const big = name.startsWith('a-');
    const vb = big ? 40 : 16;
    return `<svg class="${cls}" width="${size}" height="${size}" viewBox="0 0 ${vb} ${vb}" fill="none" stroke="currentColor" stroke-width="${big ? 2 : 1.4}" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ''}</svg>`;
  };
  const icon = S.icon;

  // ---------- small components
  S.btn = (label, role = 'secondary', o = {}) =>
    `<span class="btn ${role} ${o.size || ''} ${o.full ? 'full' : ''} ${o.dis ? 'dis' : ''}">${o.icon ? icon(o.icon, o.size === 'sm' ? 12 : o.size === 'lg' ? 15 : 13) : ''}<span class="t">${label}</span>${o.kbd ? `<span class="kbd">${o.kbd}</span>` : ''}</span>`;
  S.chip = (text, tone = '') => `<span class="chip ${tone}"><span class="t">${text}</span></span>`;
  S.dot = (tone = '') => `<span class="dot ${tone}"></span>`;
  S.link = (text, tone = '', ic) => `<span class="ulink ${tone}">${ic ? icon(ic, 12) + ' ' : ''}${text}</span>`;
  S.spin = (sz = '') => `<span class="spin ${sz}"></span>`;
  /** The warning triangle drawn for a status circle: inside ~68 % of the box, so it keeps a margin from the ring. */
  ICONS.warnc = '<path d="M8 2.9l5.4 9.4H2.6z"/><path d="M8 6.6v2.6M8 10.8v.1"/>';
  S.bar = (f, tone = '', thick) => `<span class="bar ${tone} ${thick ? 'thick' : ''}"><i style="width:${Math.round(f * 1000) / 10}%"></i></span>`;
  S.toggle = (on, dis) => `<span class="toggle ${on ? 'on' : ''} ${dis ? 'dis' : ''}"></span>`;
  S.capseg = (opts, sel) => `<span class="capseg">${opts.map((o, i) => `<span class="${i === sel ? 'on' : ''}">${o}</span>`).join('')}</span>`;
  S.popup = (label, w = 0, dis) => `<span class="popup ${dis ? 'dis' : ''}" ${w ? `style="width:${w}px"` : ''}><span>${label}</span><span class="chev">${icon('updown', 12)}</span></span>`;
  S.field = (text, w = 0, dis) => `<span class="field ${dis ? 'dis' : ''}" ${w ? `style="width:${w}px"` : ''}>${text}</span>`;
  S.stepper = (text, w = 64, dis) => `<span class="stepper ${dis ? 'dis' : ''}">${S.field(text, w)}<span class="arrows"><i>▲</i><i>▼</i></span></span>`;
  S.slider = (f, o = {}) => {
    const ticks = o.ticks ? o.ticks.map(x => `<span class="tick" style="left:${x * 100}%"></span>`).join('') : '';
    return `<span class="slider ${o.dis ? 'dis' : ''}"><span class="tr"></span><span class="fi" style="width:calc(${f} * (100% - 16px) + 8px)"></span>${ticks}<span class="kn" style="left:calc(${f} * (100% - 16px) + 8px)"></span></span>`;
  };
  S.checkbox = on => `<span class="checkbox ${on ? 'on' : ''}">${on ? icon('check', 11) : ''}</span>`;
  const NOTE_IC = { accent: 'info', neutral: 'info', green: 'ok', yellow: 'warn', red: 'err' };
  /** NoteView: tint, line, 8 pt corners; icon, title, text and buttons in the status colour. */
  S.note = (tone, title, text, actions = '') =>
    `<div class="note ${tone}"><span class="ic">${icon(NOTE_IC[tone], 18)}</span><div class="bd">${title ? `<b>${title}</b><br>` : ''}${text || ''}</div>${actions ? `<div class="ac">${actions}</div>` : ''}</div>`;
  S.tint = label => `<span class="tint">${label}</span>`;
  S.lights = off => `<span class="lights ${off ? 'off' : ''}"><i></i><i></i><i></i></span>`;

  // ---------- frame
  const TABS = [
    { id: 'process', ic: 'process', key: 'app.sidebar.tab.process', k: '⌘1' },
    { id: 'preview', ic: 'preview', key: 'app.sidebar.tab.preview', k: '⌘2' },
    { id: 'fix', ic: 'fix', key: 'app.sidebar.tab.fix', k: '⌘3' },
  ];
  S.TABS = TABS;
  /** The glass sidebar: o.tab, o.subs {process,preview,fix}, o.trail {id: 'busy'|'done'}, o.card (html), o.update */
  S.sidebar = function (o = {}) {
    const subs = o.subs || {};
    const tabs = TABS.map(x => {
      const tr = (o.trail || {})[x.id];
      const trail = tr === 'busy' ? S.spin() : tr === 'done' ? `<span class="tr">${icon('check', 14)}</span>` : '';
      return `<div class="tab ${o.tab === x.id ? 'sel' : ''}"><span class="tile">${icon(x.ic, 20)}</span><div style="min-width:0"><div class="t1">${t(x.key)}</div><div class="t2">${subs[x.id] || ''}</div></div>${trail ? `<span style="margin-left:auto;display:flex">${trail}</span>` : ''}</div>`;
    }).join('');
    const foot = `<div class="foot"><span class="num">${t('app.sidebar.version', { version: '2.0.0' })}</span>${o.checking ? S.spin('s') : icon('refresh', 14)}<span class="sp"></span>${icon('github', 16)}<span>${t('app.sidebar.github_short')}</span></div>`;
    return `<div class="side"><div class="toprow">${S.lights(o.inactive)}<span class="iconbtn">${icon('gear', 18)}</span></div><div style="display:flex;flex-direction:column;gap:2px">${tabs}</div><div class="grow"></div>${o.card || ''}${foot}</div>`;
  };
  /** ActivityCard (DS4): kind with spinner or symbol, a line, a bar, buttons. */
  S.activity = (kind, line, frac, buttons = '', o = {}) =>
    `<div style="background:var(--soft);border:1px solid var(--softLine);border-radius:10px;padding:12px;display:flex;flex-direction:column;gap:8px">
      <div style="display:flex;gap:6px;align-items:center;color:var(--primaryText);font-size:11px;font-weight:600">${o.symbol ? icon(o.symbol, 13) : S.spin('s')}${kind}</div>
      <div style="font-size:12px;line-height:1.45">${line}</div>${frac != null ? S.bar(frac) : ''}${o.foot ? `<div style="font-size:11px;color:var(--text2)">${o.foot}</div>` : ''}
      ${buttons ? `<div style="display:flex;gap:6px;margin-top:4px">${buttons}</div>` : ''}</div>`;
  S.updateCard = v =>
    `<div style="background:var(--yellowBg);border:1px solid var(--yellowLine);border-radius:10px;padding:10px 12px;color:var(--yellowText);display:flex;flex-direction:column;gap:6px">
      <div style="display:flex;gap:6px;align-items:center;font-size:12px;font-weight:600">${icon('arrowcircle', 14)}${t('app.sidebar.update', { version: v })}</div>
      <div style="display:flex;align-items:baseline">${S.link(t('app.sidebar.whats_new'), 'yellow')}<span style="flex:1"></span>${S.btn(t('app.common.download'), 'notice', { size: 'sm' })}</div></div>`;
  /** Top bar of the narrow window (board N1 of AnimeUp). */
  S.topbar = function (o = {}) {
    const segs = TABS.map(x => {
      const sel = o.tab === x.id;
      const busy = (o.busy || []).includes(x.id);
      return `<span class="tseg ${sel ? 'sel' : ''}">${busy ? S.spin('s') : icon(x.ic, 15)}${t(x.key)}${x.id === 'process' && o.count ? `<span class="cnt">${o.count}</span>` : ''}</span>`;
    }).join('');
    return `<div class="topbar"><div class="l">${S.lights()}${o.canSidebar ? `<span class="iconbtn">${icon('sidebar', 18)}</span>` : ''}</div><span class="tsegs">${segs}</span><div class="r">${o.inspector ? `<span class="iconbtn ${o.inspectorOn ? 'on' : ''}">${icon('inspector', 18)}</span>` : ''}<span class="iconbtn">${icon('gear', 18)}</span></div></div>`;
  };
  /** The main window. o: w,h, side (opts) | topbar (opts), page (html), insp (html), inspOver, overlay (html) */
  S.win = function (o) {
    const w = o.w || 1360, h = o.h || 840;
    const narrow = !!o.topbar;
    const pageCls = ['page', narrow ? 'full topbarred' : '', o.insp && !o.inspOver ? 'withinsp' : '', o.pageCls || ''].join(' ');
    return `<div class="win" style="width:${w}px;height:${h}px">
      ${narrow ? S.topbar(o.topbar) : S.sidebar(o.side)}
      <div class="${pageCls}">${o.page || ''}</div>
      ${o.insp ? `<div class="insp ${o.inspOver ? 'over' : ''}" style="${narrow ? 'top:52px' : ''}">${o.insp}</div>` : ''}
      ${o.overlay || ''}</div>`;
  };
  S.pageHead = (title, intro, right = '') =>
    `<div class="ph"><div><h2>${title}</h2>${intro ? `<p>${intro}</p>` : ''}</div><span class="sp"></span>${right}</div>`;

  /** AUAlert card: icon, title, texts, stacked full-width buttons, optional checkbox. */
  S.alert = function (o) {
    const btns = o.buttons.map((b, i) => S.btn(b[0], b[1] || 'secondary', { size: 'lg', full: true })).join('');
    return `<div class="alert"><span class="ai tone-${o.tone}">${icon('a-' + o.icon, 40)}</span><div class="at">${o.title}</div>${(o.texts || []).map(x => `<div class="ax">${x}</div>`).join('')}<div class="ab">${btns}</div>${o.checkbox ? `<div class="acb">${S.checkbox(false)}${o.checkbox}</div>` : ''}</div>`;
  };

  // ---------- boards
  const boards = [];
  /** board(code, title, desc, size [w,h] of the stage content, fn returning html, opts {row}) */
  S.board = (code, title, desc, size, fn, o = {}) => boards.push({ code, title, desc, size, fn, o });
  S.boards = boards;

  function render() {
    const root = document.getElementById('boards');
    if (!root) return;
    root.innerHTML = boards.map(b => {
      const [w, h] = b.size;
      return `<section class="board ${S.only === b.code ? 'only' : ''}" id="${b.code}" data-code="${b.code}" data-size="${w + 80 + 32}x${h + 80 + 32 + 62}">
        <div class="board-cap"><span class="code">${b.code}</span><span class="ttl">${b.title}</span><span class="dsc">${b.desc}</span></div>
        <div class="stage ${b.o.row ? 'row' : ''}" style="width:${w + 80}px;height:${h + 80}px">${b.fn()}</div></section>`;
    }).join('');
    const m = document.getElementById('manifest');
    if (m) m.textContent = boards.map(b => `${b.code} ${b.size[0] + 80 + 32} ${b.size[1] + 80 + 32 + 62}`).join('\n');
  }
  S.render = render;

  function head() {
    const h = document.querySelector('.doc-head');
    if (!h) return;
    const seg = (opts, cur, fn) => `<span class="seg-doc">${opts.map(([v, l]) => `<button data-v="${v}" class="${v === cur ? 'on' : ''}">${l}</button>`).join('')}</span>`;
    const ctl = h.querySelector('.ctl');
    ctl.innerHTML = `${seg([['light', 'Chiaro'], ['dark', 'Scuro'], ['system', 'Sistema']], S.theme)} ${seg([['en', 'EN'], ['it', 'IT']], S.lang)}`;
    const [ts, ls] = ctl.querySelectorAll('.seg-doc');
    ts.onclick = e => { const v = e.target.dataset.v; if (!v) return; S.theme = v; store.set('sv-theme', v); applyTheme(); head(); };
    ls.onclick = e => { const v = e.target.dataset.v; if (!v) return; S.lang = v; store.set('sv-lang', v); document.documentElement.lang = v; render(); head(); };
  }
  document.documentElement.lang = S.lang;
  window.addEventListener('DOMContentLoaded', () => {
    if (P.get('list')) { const pre = document.createElement('pre'); pre.id = 'manifest'; document.body.appendChild(pre); }
    render(); head();
    if (S.only) { const el = document.getElementById(S.only); if (el) el.scrollIntoView(); }
  });
})();
