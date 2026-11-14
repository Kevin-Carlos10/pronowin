(function () {
  'use strict';
  var body = document.body;
  if (!body.classList.contains('landing')) return;

  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
  var finePointer = window.matchMedia('(hover: hover) and (pointer: fine)');
  var motionToggle = document.querySelector('[data-motion-toggle]');
  var motionLabel = document.querySelector('[data-motion-label]');
  var animations = new Set();
  var tilts = [];
  var paused = false;
  var motionAllowed = false;
  try { paused = sessionStorage.getItem('pronowin-motion-paused') === 'true'; } catch (_) {}

  function animate(element, frames, options) {
    if (!motionAllowed || document.hidden || !element.animate) return;
    try {
      var animation = element.animate(frames, options);
      animations.add(animation);
      animation.finished.then(function () { animations.delete(animation); }, function () { animations.delete(animation); });
    } catch (_) { /* The readable, static presentation is the fallback. */ }
  }

  function resetTilt(state) {
    if (state.frame) cancelAnimationFrame(state.frame);
    state.frame = 0;
    state.element.style.setProperty('--tilt-x', '0deg');
    state.element.style.setProperty('--tilt-y', '0deg');
    state.element.style.setProperty('--pointer-x', '50%');
    state.element.style.setProperty('--pointer-y', '50%');
  }

  function applyMotionPreference() {
    motionAllowed = !paused && !reduced.matches;
    body.classList.toggle('motion-enabled', motionAllowed);
    document.documentElement.classList.toggle('motion-paused', !motionAllowed);
    body.classList.toggle('page-away', document.hidden);
    if (motionToggle) {
      motionToggle.hidden = false;
      motionToggle.setAttribute('aria-pressed', String(motionAllowed));
      motionToggle.disabled = reduced.matches;
      motionToggle.setAttribute('aria-label', reduced.matches ? 'Animations réduites selon vos préférences système' : (motionAllowed ? 'Mettre les animations en pause' : 'Activer les animations'));
    }
    if (motionLabel) motionLabel.textContent = reduced.matches ? 'Mouvements réduits' : (motionAllowed ? 'Animations : activées' : 'Animations : en pause');
    if (!motionAllowed || document.hidden) {
      animations.forEach(function (animation) { animation.cancel(); });
      animations.clear();
      tilts.forEach(resetTilt);
    }
  }
  if (motionToggle) motionToggle.addEventListener('click', function () {
    paused = !paused;
    try { sessionStorage.setItem('pronowin-motion-paused', String(paused)); } catch (_) {}
    applyMotionPreference();
  });
  reduced.addEventListener('change', applyMotionPreference);
  document.addEventListener('visibilitychange', applyMotionPreference);
  applyMotionPreference();

  if ('IntersectionObserver' in window) {
    var sceneObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) { entry.target.classList.toggle('in-view', entry.isIntersecting); });
    }, { rootMargin: '80px 0px' });
    document.querySelectorAll('[data-motion-scene]').forEach(function (scene) { sceneObserver.observe(scene); });

    // Reveal once. CSS never makes content depend on the observer or animation finishing.
    var revealObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        revealObserver.unobserve(entry.target);
        if (entry.boundingClientRect.top < 0) return;
        var delay = Math.min(240, Math.max(0, Number(entry.target.dataset.revealDelay) || 0));
        animate(entry.target, [{ opacity: 0, transform: 'translateY(24px)' }, { opacity: 1, transform: 'translateY(0)' }], { duration: 650, delay: delay, easing: 'cubic-bezier(.2,.7,.2,1)', fill: 'backwards' });
      });
    }, { threshold: 0.08 });
    document.querySelectorAll('[data-reveal]').forEach(function (element) {
      if (element.getBoundingClientRect().bottom > 0) revealObserver.observe(element);
    });
  } else {
    document.querySelectorAll('[data-motion-scene]').forEach(function (scene) { scene.classList.add('in-view'); });
  }

  var controls = document.querySelector('[data-stage-controls]');
  var tabs = controls ? Array.from(controls.querySelectorAll('[data-stage-tab]')) : [];
  var panels = tabs.map(function (tab) {
    return Array.from(document.querySelectorAll('[data-stage-panel]')).find(function (panel) { return panel.dataset.stagePanel === tab.dataset.stageTab; });
  });
  if (tabs.length && panels.every(Boolean)) {
    controls.setAttribute('role', 'tablist');
    if (!controls.hasAttribute('aria-label')) controls.setAttribute('aria-label', 'Explorer les fonctionnalités de PronoWin');
    tabs.forEach(function (tab, index) {
      tab.id = tab.id || 'experience-tab-' + index;
      panels[index].id = panels[index].id || 'experience-panel-' + index;
      tab.setAttribute('role', 'tab');
      tab.setAttribute('aria-controls', panels[index].id);
      panels[index].setAttribute('role', 'tabpanel');
      panels[index].setAttribute('aria-labelledby', tab.id);
      panels[index].tabIndex = 0;
      tab.addEventListener('click', function () { activateStage(index, false); });
      tab.addEventListener('keydown', function (event) {
        var next = { ArrowRight: (index + 1) % tabs.length, ArrowLeft: (index + tabs.length - 1) % tabs.length, Home: 0, End: tabs.length - 1 }[event.key];
        if (next === undefined) return;
        event.preventDefault();
        activateStage(next, true);
      });
    });
    function activateStage(index, focus) {
      var changed = tabs[index].getAttribute('aria-selected') !== 'true';
      tabs.forEach(function (tab, i) {
        var selected = i === index;
        tab.setAttribute('aria-selected', String(selected));
        tab.tabIndex = selected ? 0 : -1;
        tab.classList.toggle('is-active', selected);
        panels[i].hidden = !selected;
        panels[i].classList.toggle('is-active', selected);
      });
      if (focus) tabs[index].focus();
      if (changed) animate(panels[index], [{ opacity: 0, transform: 'translateY(10px)' }, { opacity: 1, transform: 'translateY(0)' }], { duration: 300, easing: 'ease-out' });
    }
    activateStage(0, false);
    controls.hidden = false;
  }

  document.querySelectorAll('[data-tilt]').forEach(function (element) {
    var state = { element: element, frame: 0, x: 0, y: 0 };
    tilts.push(state);
    element.addEventListener('pointermove', function (event) {
      if (!motionAllowed || document.hidden || !finePointer.matches || event.pointerType === 'touch') return;
      state.x = event.clientX;
      state.y = event.clientY;
      if (state.frame) return;
      state.frame = requestAnimationFrame(function () {
        state.frame = 0;
        var rect = element.getBoundingClientRect();
        if (!rect.width || !rect.height) return;
        var x = Math.max(0, Math.min(1, (state.x - rect.left) / rect.width));
        var y = Math.max(0, Math.min(1, (state.y - rect.top) / rect.height));
        element.style.setProperty('--tilt-x', ((.5 - y) * 8).toFixed(2) + 'deg');
        element.style.setProperty('--tilt-y', ((x - .5) * 10).toFixed(2) + 'deg');
        element.style.setProperty('--pointer-x', (x * 100).toFixed(1) + '%');
        element.style.setProperty('--pointer-y', (y * 100).toFixed(1) + '%');
      });
    }, { passive: true });
    element.addEventListener('pointerleave', function () { resetTilt(state); });
    element.addEventListener('pointercancel', function () { resetTilt(state); });
  });
  finePointer.addEventListener('change', function () { tilts.forEach(resetTilt); });

  var navbar = document.querySelector('.navbar');
  var sentinel = document.querySelector('[data-nav-sentinel]');
  if (navbar && sentinel && 'IntersectionObserver' in window) {
    new IntersectionObserver(function (entries) {
      navbar.classList.toggle('is-scrolled', !entries[0].isIntersecting && entries[0].boundingClientRect.top < 0);
    }).observe(sentinel);
  }
  var links = Array.from(document.querySelectorAll('.nav-links a[href^="#"], .mobile-nav a[href^="#"]'));
  var sections = Array.from(new Set(links.map(function (link) { return document.getElementById(link.hash.slice(1)); }).filter(Boolean)));
  if (sections.length && 'IntersectionObserver' in window) {
    var visible = new Set();
    var navigationObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) { if (entry.isIntersecting) visible.add(entry.target); else visible.delete(entry.target); });
      var current = Array.from(visible).sort(function (a, b) { return Math.abs(a.getBoundingClientRect().top) - Math.abs(b.getBoundingClientRect().top); })[0];
      links.forEach(function (link) {
        if (current && link.hash === '#' + current.id) link.setAttribute('aria-current', 'location');
        else link.removeAttribute('aria-current');
      });
    }, { rootMargin: '-15% 0px -55% 0px' });
    sections.forEach(function (section) { navigationObserver.observe(section); });
  }
})();
