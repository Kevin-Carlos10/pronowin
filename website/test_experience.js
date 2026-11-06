/* Behavioral checks for the progressive animation layer, without a browser dependency. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, 'public/js/experience.js'), 'utf8');

function environment({ reduced = false, storageBlocked = false, savedPause = false } = {}) {
  const storage = new Map([['pronowin-motion-paused', String(savedPause)]]);
  function node(dataset = {}) {
    const classes = new Set();
    const attributes = new Map();
    const events = new Map();
    return {
      dataset, hidden: false, id: '', disabled: false,
      classList: { contains: key => classes.has(key), add: key => classes.add(key), toggle(key, enabled) { enabled ? classes.add(key) : classes.delete(key); } },
      style: { setProperty() {} },
      addEventListener(name, callback) { events.set(name, callback); },
      fire(name, extra = {}) { events.get(name)?.({ preventDefault() {}, ...extra }); },
      setAttribute(key, value) { attributes.set(key, String(value)); },
      hasAttribute: key => attributes.has(key),
      getAttribute: key => attributes.get(key) ?? null,
      focus() { doc.activeElement = this; },
      getBoundingClientRect: () => ({ top: 20, bottom: 120, left: 0, width: 200, height: 100 }),
      animate() { const animation = { cancelled: false, cancel() { this.cancelled = true; }, finished: new Promise(() => {}) }; createdAnimations.push(animation); return animation; },
    };
  }
  const createdAnimations = [];
  const body = node(); body.classList.add('landing');
  const root = node();
  const toggle = node();
  const label = node();
  const controls = node();
  const tabs = ['analyse', 'direct', 'suivi'].map(stageTab => node({ stageTab }));
  const panels = ['analyse', 'direct', 'suivi'].map(stagePanel => node({ stagePanel }));
  controls.querySelectorAll = () => tabs;
  const doc = node(); Object.assign(doc, { body, documentElement: root, hidden: false });
  doc.querySelector = selector => ({ '[data-motion-toggle]': toggle, '[data-motion-label]': label, '[data-stage-controls]': controls })[selector] || null;
  doc.querySelectorAll = selector => selector === '[data-stage-panel]' ? panels : [];
  const preference = node(); preference.matches = reduced;
  const pointer = node(); pointer.matches = true;
  const context = {
    document: doc,
    window: { matchMedia: query => query.includes('reduced-motion') ? preference : pointer },
    sessionStorage: {
      getItem(key) { if (storageBlocked) throw Error('Storage unavailable'); return storage.get(key); },
      setItem(key, value) { if (storageBlocked) throw Error('Storage unavailable'); storage.set(key, value); },
    },
    cancelAnimationFrame() {}, requestAnimationFrame() {},
  };
  vm.runInNewContext(source, context);
  return { body, root, toggle, doc, controls, tabs, panels, preference, storage, createdAnimations };
}

const tests = [
  ['initialization exposes one accessible panel', () => {
    const e = environment();
    assert.equal(e.controls.hidden, false);
    assert.equal(e.controls.getAttribute('role'), 'tablist');
    assert.deepEqual(e.panels.map(p => p.hidden), [false, true, true]);
    assert.deepEqual(e.tabs.map(t => t.tabIndex), [0, -1, -1]);
    assert.equal(e.tabs[0].getAttribute('aria-controls'), e.panels[0].id);
  }],
  ['click selects the corresponding panel only', () => {
    const e = environment(); e.tabs[1].fire('click');
    assert.deepEqual(e.panels.map(p => p.hidden), [true, false, true]);
    assert.deepEqual(e.tabs.map(t => t.getAttribute('aria-selected')), ['false', 'true', 'false']);
  }],
  ['arrow keys wrap; Home and End restore focus', () => {
    const e = environment(); e.tabs[0].fire('keydown', { key: 'ArrowLeft' });
    assert.equal(e.doc.activeElement, e.tabs[2]);
    e.tabs[2].fire('keydown', { key: 'ArrowRight' });
    assert.equal(e.doc.activeElement, e.tabs[0]);
    e.tabs[0].fire('keydown', { key: 'End' });
    assert.equal(e.doc.activeElement, e.tabs[2]);
    e.tabs[2].fire('keydown', { key: 'Home' });
    assert.equal(e.doc.activeElement, e.tabs[0]);
  }],
  ['pause cancels running motion and disables smooth scrolling', () => {
    const e = environment(); e.tabs[1].fire('click'); e.toggle.fire('click');
    assert.equal(e.body.classList.contains('motion-enabled'), false);
    assert.equal(e.root.classList.contains('motion-paused'), true);
    assert.ok(e.createdAnimations.every(a => a.cancelled));
    assert.equal(e.storage.get('pronowin-motion-paused'), 'true');
    const count = e.createdAnimations.length; e.tabs[2].fire('click');
    assert.equal(e.createdAnimations.length, count);
    assert.equal(e.panels[2].hidden, false);
  }],
  ['saved pause survives the next page load', () => {
    const e = environment({ savedPause: true });
    assert.equal(e.toggle.getAttribute('aria-pressed'), 'false');
    assert.equal(e.createdAnimations.length, 0);
    e.toggle.fire('click'); assert.equal(e.body.classList.contains('motion-enabled'), true);
  }],
  ['system reduced motion wins, including when changed at runtime', () => {
    const e = environment({ reduced: true });
    assert.equal(e.toggle.disabled, true);
    assert.equal(e.createdAnimations.length, 0);
    e.tabs[2].fire('click'); assert.equal(e.panels[2].hidden, false);
    e.preference.matches = false; e.preference.fire('change');
    assert.equal(e.toggle.disabled, false);
    assert.equal(e.body.classList.contains('motion-enabled'), true);
    e.preference.matches = true; e.preference.fire('change');
    assert.equal(e.body.classList.contains('motion-enabled'), false);
  }],
  ['background pages stop active animations', () => {
    const e = environment(); e.doc.hidden = true; e.doc.fire('visibilitychange');
    assert.equal(e.body.classList.contains('page-away'), true);
    assert.ok(e.createdAnimations.every(a => a.cancelled));
  }],
  ['blocked storage does not break controls or tabs', () => {
    const e = environment({ storageBlocked: true }); e.toggle.fire('click'); e.tabs[1].fire('click');
    assert.equal(e.panels[1].hidden, false);
    assert.equal(e.toggle.getAttribute('aria-pressed'), 'false');
  }],
];
for (const [name, test] of tests) { test(); console.log('  OK   ' + name); }
console.log(`${tests.length}/${tests.length} contrôles d’interaction passés`);
