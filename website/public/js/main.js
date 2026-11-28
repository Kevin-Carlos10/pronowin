(function () {
  'use strict';
  var toggle = document.querySelector('.nav-toggle');
  var menu = document.querySelector('.mobile-nav');
  var breakpoint = window.matchMedia('(max-width: 900px)');

  if (toggle && menu) {
    // Without JavaScript the regular links remain visible, including on mobile.
    document.documentElement.classList.add('nav-enhanced');
    toggle.hidden = false;

    function closeMenu(returnFocus) {
      menu.hidden = true;
      toggle.setAttribute('aria-expanded', 'false');
      toggle.setAttribute('aria-label', 'Ouvrir le menu');
      if (returnFocus) toggle.focus();
    }

    toggle.addEventListener('click', function () {
      var opening = menu.hidden;
      menu.hidden = !opening;
      toggle.setAttribute('aria-expanded', String(opening));
      toggle.setAttribute('aria-label', opening ? 'Fermer le menu' : 'Ouvrir le menu');
    });

    menu.addEventListener('click', function (event) {
      var link = event.target.closest('a[href^="#"]');
      if (!link) return;
      closeMenu(false);
      var target = document.getElementById(link.hash.slice(1));
      if (target) {
        target.setAttribute('tabindex', '-1');
        target.focus({ preventScroll: true });
      }
    });

    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape' && !menu.hidden) closeMenu(true);
    });
    document.addEventListener('click', function (event) {
      if (!menu.hidden && !event.target.closest('.navbar')) closeMenu(false);
    });
    breakpoint.addEventListener('change', function () {
      if (!breakpoint.matches) closeMenu(false);
    });
  }

  // A footer link or a shared #comparer URL must reveal its destination.
  function revealAnchor() {
    var target = document.getElementById(window.location.hash.slice(1));
    if (target && target.tagName === 'DETAILS') target.open = true;
  }
  document.querySelectorAll('a[href="#comparer"]').forEach(function (link) {
    link.addEventListener('click', function () {
      var comparison = document.getElementById('comparer');
      if (comparison) comparison.open = true;
    });
  });
  window.addEventListener('hashchange', revealAnchor);
  revealAnchor();
})();
