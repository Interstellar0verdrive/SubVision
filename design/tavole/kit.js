/* SubVision 2.0 · design boards: SubVision's own composite views (file rows, step bars,
 * inspector), built from the components of tavole.js. */
(function () {
  const S = window.SV, t = S.t, icon = S.icon, btn = S.btn;
  /** Decimal comma in Italian. */
  const dec = s => (S.lang === 'it' ? String(s).replace(/(\d)\.(\d)/g, '$1,$2') : String(s));
  /** Thousands separator: 17,040 / 17.040. */
  const th = n => (typeof n === 'number' ? n.toLocaleString(S.lang === 'it' ? 'it-IT' : 'en-US') : n);
  S.dec = dec; S.th = th;

  const K = window.EK = {};
  K.openBtn = () => btn(t('app.process.open'), 'secondary', { icon: 'folder' });
  K.inspBtn = on => `<span class="iconbtn ${on ? 'on' : ''}" title="⌥⌘I" style="margin-left:4px">${icon('inspector', 16)}</span>`;
  K.reportBtn = () => btn(t('app.row.open_report'), 'secondary', { size: 'sm', icon: 'doc' });
  K.more = () => `<span class="iconbtn" style="width:22px;height:22px">${icon('dots', 14)}</span>`;
  K.list = (rows, head) => `<div class="list">${head ? `<div class="lhead"><span></span><span class="label">${t('app.list.name')}</span><span class="label r">${t('app.list.duration')}</span><span class="label r">${t('app.list.fps')}</span><span class="label r col-res">${t('app.list.size')}</span><span></span></div>` : ''}${rows.join('')}</div>`;
  const SIC = { done: ['done', 'check'], warn: ['warn', 'warn'], fail: ['fail', 'x'], bad: ['fail', 'x'], stop: ['stop', 'stop'], ready: ['wait', ''], wait: ['wait', ''] };
  /** One file row. r: st, name, dir, dur, fps, res, result, rcls, chips, acts, detail, dim */
  K.row = function (r) {
    const ic = r.st === 'run' ? S.spin() : `<span class="sicon ${SIC[r.st][0]}">${SIC[r.st][1] ? icon(SIC[r.st][1], 10) : ''}</span>`;
    const cls = { ready: 'ready', wait: 'ready', run: 'run', done: 'done', warn: 'warn', fail: 'fail', bad: 'bad', stop: 'stop' }[r.st];
    return `<div class="fr ${cls} ${r.dim ? 'dim' : ''}"><div class="frow">${ic}
      <div style="min-width:0"><div style="display:flex;gap:8px;align-items:center"><span class="fname">${r.name}</span>${r.chips || ''}</div>
        <div class="fdir">${r.dir}</div>${r.result ? `<div class="fres ${r.rcls || ''}">${r.result}</div>` : ''}</div>
      <span class="num r">${r.dur}</span><span class="num r">${dec(r.fps)}</span><span class="num r col-res">${r.res}</span>
      <span class="acts">${r.acts || ''}</span></div>${r.detail ? `<div class="detail">${r.detail}</div>` : ''}</div>`;
  };
  K.bottom = (html, noAuto) => `<div class="bottombar" style="${noAuto ? 'margin-top:0' : ''}">${html}</div>`;
  /** Step bars of one band. Specs: ['done',step,total,time,rate?] ['run',step,frac,done,total,el,eta,rate] ['wait',step,est?] ['fail',step] ['skip',step] */
  K.steps = function (band, specs, o = {}) {
    const name = band === 'dlg' ? t('app.band.dialogue') : t('app.band.signs');
    const sw = band === 'dlg' ? 'var(--bandDialogue)' : 'var(--bandSigns)';
    const lines = specs.map(sp => {
      const [st, step] = sp;
      const isRef = step === 'refine';
      const unit = t(isRef ? 'app.unit.lines' : 'app.unit.frames'), unitS = t(isRef ? 'app.unit.lines_s' : 'app.unit.fps');
      const label = step === 'ocr' ? t('app.step.ocr', { n: o.n || 3 }) : t('app.step.' + step);
      let iconH, barH, numH;
      if (st === 'done') {
        iconH = `<span style="color:var(--greenText)">${icon('check', 12)}</span>`; barH = S.bar(1, 'green');
        numH = sp[4] ? t('app.step.done', { total: th(sp[2]), unit, t: sp[3], rate: dec(sp[4]), unit_s: unitS }) : t('app.step.done_short', { total: th(sp[2]), unit, t: sp[3] });
      } else if (st === 'run') {
        iconH = S.spin('s'); barH = S.bar(sp[2]);
        numH = t('app.step.running', { done: th(sp[3]), total: th(sp[4]), unit, el: sp[5], eta: sp[6], rate: dec(sp[7]), unit_s: unitS });
      } else if (st === 'wait') {
        iconH = `<span class="dot" style="background:transparent;border:1px solid var(--glassLine);width:9px;height:9px"></span>`; barH = S.bar(0);
        numH = sp[2] ? t('app.step.waiting_est', { t: sp[2] }) : t('app.step.waiting');
      } else if (st === 'fail') {
        iconH = `<span style="color:var(--redText)">${icon('x', 12)}</span>`; barH = S.bar(0.35, 'red'); numH = t('app.step.aborted');
      } else {
        iconH = `<span class="dot" style="background:transparent;border:1px dashed var(--glassLine);width:9px;height:9px"></span>`; barH = S.bar(0, 'gray'); numH = t('app.step.not_run');
      }
      return `<div class="srow ${st}"><span style="display:grid;place-items:center">${iconH}</span><span class="sl">${label}</span>${barH}<span class="sn">${numH}</span></div>`;
    }).join('');
    return `<div class="bandgrp"><div class="label" style="display:flex;gap:6px;align-items:center;margin:4px 0 2px"><span class="sw" style="background:${sw}"></span>${name}</div>${lines}</div>`;
  };
  K.doneDetail = () => `<div style="display:grid;grid-template-columns:1fr 1fr;gap:18px;margin-top:6px">
      <div><div class="label" style="margin-bottom:4px">${t('app.row.times')}</div><div class="kv">
        <span class="k">${t('app.step.extract')}</span><span class="v">2:14 · 2:01</span>
        <span class="k">${t('app.step.group')}</span><span class="v">0:12 · 0:11</span>
        <span class="k">${t('app.step.ocr', { n: 3 })}</span><span class="v">1:03:40 · 14:02</span>
        <span class="k">${t('app.step.refine')}</span><span class="v">7:48 · 0:52</span></div>
        <div class="small t3" style="margin-top:4px">${t('app.band.dialogue')} · ${t('app.band.signs')}</div></div>
      <div><div class="label" style="margin-bottom:4px">${t('app.row.files')}</div><div class="kv">
        <span class="k">SRT</span><span class="v">Show S01E04 [1080p].srt</span>
        <span class="k">${S.lang === 'en' ? 'Report' : 'Report'}</span><span class="v">Show S01E04 [1080p].revisione.html</span>
        <span class="k">Log</span><span class="v">Show S01E04 [1080p].log</span></div>
        <div style="display:flex;gap:14px;margin-top:8px">${S.link(t('app.btn.show_in_finder'))}${S.link(t('app.row.open_srt'))}${S.link(t('app.row.open_log'))}</div></div></div>`;

  // ---------- inspector (D5)
  const P = [
    { g: 'ocr', items: [
      { k: 'lang', ctl: 'popup', v: () => (S.lang === 'en' ? 'Italian' : 'Italiano'), code: 'it-IT' },
      { k: 'fps', ctl: 'snap', f: 1, ticks: [0, .25, .5, .75, 1], v: () => '12' },
      { k: 'multi', ctl: 'toggle', on: true },
      { k: 'refine', ctl: 'toggle', on: true },
      { k: 'conf', ctl: 'slider', f: .30, v: () => dec('0.30') },
    ] },
    { g: 'dlg', items: [
      { k: 'bottom', ctl: 'slider', f: (28 - 5) / 75, v: () => '28 %' },
      { k: 'width', ctl: 'slider', f: (96 - 50) / 50, v: () => '96 %' },
    ] },
    { g: 'sig', toggle: true, items: [
      { k: 'top', ctl: 'slider', f: (22 - 5) / 45, v: () => '22 %' },
      { k: 'topw', ctl: 'slider', f: 1, v: () => '100 %' },
    ] },
    { g: 'seg', items: [
      { k: 'mindur', ctl: 'stepper', v: () => dec('0.20') + ' s' },
      { k: 'merge', ctl: 'stepper', v: () => dec('0.6') + ' s' },
      { k: 'wrap', ctl: 'stepper', v: () => '42' },
    ] },
    { g: 'adv', items: [
      { k: 'report', ctl: 'toggle', on: true },
      { k: 'gap', ctl: 'stepper', v: () => '6 s' },
      { k: 'skip', ctl: 'snap', f: 0, ticks: [0, .25, .5, .75, 1], v: () => '0' },
      { k: 'workers', ctl: 'stepper', v: () => '4' },
      { k: 'ignore', ctl: 'toggle', on: true, count: () => t('app.insp.phrases', { n: 12 }) },
      { k: 'corr', ctl: 'toggle', on: true, count: () => t('app.insp.corrections', { n: 4 }) },
    ] },
  ];
  /** o: locked, closed: [groups], changed: {key: [value, frac]}, langMissing, listMissing, compact, popover, menu */
  window.INSPECTOR = function (o = {}) {
    const closed = o.closed || [];
    const ch = o.changed || {};
    const groups = P.map(G => {
      const isClosed = closed.includes(G.g);
      const changedHere = G.items.some(it => ch[it.k]) || (G.g === 'sig' && o.signsOff);
      const right = `<span class="def ${changedHere && !o.locked ? '' : 'off'}">${t('app.btn.defaults')}</span>`;
      const sigToggle = G.toggle ? `<span style="margin-left:6px">${S.toggle(!o.signsOff, o.locked)}</span>` : '';
      const head = `<div class="grp-h"><span class="chev">${icon(isClosed ? 'chevR' : 'chevD', 11)}</span>${t('app.insp.g.' + G.g)}${sigToggle}<span class="sp"></span>${right}</div>`;
      if (isClosed) return `<div class="grp">${head}</div>`;
      const items = G.items.map(it => {
        const c = ch[it.k];
        const vtxt = c ? c[0] : it.v ? it.v() : '';
        const f = c && c[1] != null ? c[1] : it.f;
        const dis = o.locked || (G.g === 'sig' && o.signsOff) || (it.k === 'gap' && o.reportOff);
        const val = vtxt ? `<span class="pv ${c ? 'chg' : ''}">${vtxt}</span>` : '';
        let ctl = '';
        if (it.ctl === 'toggle') {
          const on = c ? c[2] : it.on;
          return `<div class="prm ${dis ? 'dis' : ''}"><div class="pl">${t('app.insp.' + it.k)}<span class="q">?</span><span class="sp"></span>${it.count ? `<span class="small ${o.listMissing && it.k === 'ignore' ? '' : 't3'}" style="${o.listMissing && it.k === 'ignore' ? 'color:var(--yellowText)' : ''}">${o.listMissing && it.k === 'ignore' ? t('app.insp.file_missing') : it.count()}</span>` : ''}${c ? '<span class="pv chg"></span>' : ''}${S.toggle(on, dis)}</div></div>`;
        }
        if (it.ctl === 'popup') {
          const warn = o.langMissing;
          ctl = `${S.popup(`${vtxt} <span class="t3 num" style="font-size:11px">${it.code}</span>`, 268, dis)}`;
          return `<div class="prm ${dis ? 'dis' : ''}"><div class="pl">${t('app.insp.' + it.k)}<span class="q">?</span></div><div class="pc" style="${warn ? 'outline:1px solid var(--yellowLine);border-radius:7px' : ''}">${ctl}</div></div>`;
        }
        if (it.ctl === 'slider' || it.ctl === 'snap') ctl = S.slider(f, { ticks: it.ticks });
        if (it.ctl === 'stepper') return `<div class="prm ${dis ? 'dis' : ''}"><div class="pl">${t('app.insp.' + it.k)}<span class="q">?</span><span class="sp"></span>${c ? '<span class="pv chg"></span>' : ''}${S.stepper(vtxt, 64)}</div></div>`;
        return `<div class="prm ${dis ? 'dis' : ''}"><div class="pl">${t('app.insp.' + it.k)}<span class="q">?</span><span class="sp"></span>${it.ctl === 'stepper' ? '' : val}</div><div class="pc">${ctl}</div></div>`;
      }).join('');
      return `<div class="grp">${head}${items}</div>`;
    }).join('');
    const notes = [
      o.locked ? S.note('accent', '', t('app.insp.locked')) : '',
      o.langMissing ? S.note('yellow', '', t('app.insp.lang_missing', { lang: S.lang === 'en' ? 'Italian' : 'Italiano' })) : '',
    ].filter(Boolean).join('<div style="height:8px"></div>');
    return `<div class="insp-h"><div class="t">${t('app.insp.title')}<span class="sp"></span><span class="iconbtn" style="width:22px;height:22px">${icon('dots', 14)}</span><span class="iconbtn" style="width:22px;height:22px">${icon('x', 12)}</span></div>
      <div class="s">${t('app.insp.subtitle')}</div></div>
      <div class="insp-b">${notes ? `<div style="margin:10px 0 4px">${notes}</div>` : ''}${groups}</div>${o.extra || ''}`;
  };
})();

/* Vision's 33 languages at the "accurate" level (spike S5), names in the app's language. */
window.VISION_LANGS = [
  ['ar-SA', 'Arabic', 'Arabo'], ['ars-SA', 'Arabic (Najdi)', 'Arabo (najdi)'], ['yue-Hans', 'Cantonese (Simplified)', 'Cantonese (semplificato)'],
  ['yue-Hant', 'Cantonese (Traditional)', 'Cantonese (tradizionale)'], ['zh-Hans', 'Chinese (Simplified)', 'Cinese (semplificato)'],
  ['zh-Hant', 'Chinese (Traditional)', 'Cinese (tradizionale)'], ['cs-CZ', 'Czech', 'Ceco'], ['da-DK', 'Danish', 'Danese'], ['nl-NL', 'Dutch', 'Olandese'],
  ['en-US', 'English', 'Inglese'], ['fi-FI', 'Finnish', 'Finlandese'], ['fr-FR', 'French', 'Francese'], ['de-DE', 'German', 'Tedesco'],
  ['hi-IN', 'Hindi', 'Hindi'], ['id-ID', 'Indonesian', 'Indonesiano'], ['it-IT', 'Italian', 'Italiano'], ['ja-JP', 'Japanese', 'Giapponese'],
  ['ko-KR', 'Korean', 'Coreano'], ['ms-MY', 'Malay', 'Malese'], ['mr-IN', 'Marathi', 'Marathi'], ['no-NO', 'Norwegian', 'Norvegese'],
  ['nb-NO', 'Norwegian Bokmål', 'Norvegese bokmål'], ['nn-NO', 'Norwegian Nynorsk', 'Norvegese nynorsk'], ['pl-PL', 'Polish', 'Polacco'],
  ['pt-BR', 'Portuguese (Brazil)', 'Portoghese (Brasile)'], ['ro-RO', 'Romanian', 'Rumeno'], ['ru-RU', 'Russian', 'Russo'], ['es-ES', 'Spanish', 'Spagnolo'],
  ['sv-SE', 'Swedish', 'Svedese'], ['th-TH', 'Thai', 'Thailandese'], ['tr-TR', 'Turkish', 'Turco'], ['uk-UA', 'Ukrainian', 'Ucraino'], ['vi-VT', 'Vietnamese', 'Vietnamita'],
];
/** A free-standing inspector panel (for the I boards), h tall. */
window.EK.panel = (html, h, o = {}) => `<div style="position:relative;width:300px;height:${h}px;border-radius:12px;overflow:${o.visible ? 'visible' : 'hidden'};box-shadow:0 0 0 1px var(--glassLine),0 18px 40px rgba(var(--shadow),calc(.35*var(--shadowK)));flex:none">
  <div class="insp" style="width:auto;left:0;border-left:0;border-radius:12px">${html}</div>${o.over || ''}</div>`;
