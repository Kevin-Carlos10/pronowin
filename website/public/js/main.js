(function () {
  var navToggle = document.querySelector('.nav-toggle');
  var mobileNav = document.querySelector('.mobile-nav');

  if (navToggle && mobileNav) {
    navToggle.addEventListener('click', function () {
      var isOpen = mobileNav.classList.toggle('is-open');
      navToggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
      document.body.style.overflow = isOpen ? 'hidden' : '';
    });
    mobileNav.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        mobileNav.classList.remove('is-open');
        document.body.style.overflow = '';
      });
    });
  }

  document.querySelectorAll('.faq-question').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var item = btn.closest('.faq-item');
      var wasOpen = item.classList.contains('is-open');
      document.querySelectorAll('.faq-item.is-open').forEach(function (el) {
        el.classList.remove('is-open');
      });
      if (!wasOpen) item.classList.add('is-open');
    });
  });

  var quoteSlides = document.querySelectorAll('.quote-slide');
  var quoteDots = document.querySelectorAll('.quote-dot');
  if (quoteSlides.length && quoteDots.length) {
    var currentQuote = 0;
    var quoteTimer = null;

    function showQuote(index) {
      quoteSlides.forEach(function (slide, i) {
        slide.style.display = i === index ? '' : 'none';
      });
      quoteDots.forEach(function (dot, i) {
        dot.classList.toggle('is-active', i === index);
      });
      currentQuote = index;
    }

    function scheduleAutoplay() {
      if (quoteTimer) clearInterval(quoteTimer);
      quoteTimer = setInterval(function () {
        showQuote((currentQuote + 1) % quoteSlides.length);
      }, 6000);
    }

    quoteDots.forEach(function (dot) {
      dot.addEventListener('click', function () {
        showQuote(parseInt(dot.getAttribute('data-index'), 10));
        scheduleAutoplay();
      });
    });

    scheduleAutoplay();
  }

  var newsletterForm = document.querySelector('.newsletter-form');
  if (newsletterForm) {
    newsletterForm.addEventListener('submit', function (e) {
      e.preventDefault();
      var input = newsletterForm.querySelector('input');
      var btn = newsletterForm.querySelector('button');
      if (input && input.value) {
        btn.textContent = 'Merci !';
        input.value = '';
        setTimeout(function () { btn.textContent = 'Souscrire'; }, 2500);
      }
    });
  }

  /* ---------------------------------------------------------
     Scroll reveal + count-up animations (Apple-style chapters)
     --------------------------------------------------------- */
  var reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  function tagReveal(selector) {
    document.querySelectorAll(selector).forEach(function (el) {
      el.classList.add('reveal');
    });
  }

  function stagger(parentSelector, step) {
    document.querySelectorAll(parentSelector).forEach(function (parent) {
      var i = 0;
      Array.prototype.forEach.call(parent.children, function (child) {
        if (child.classList.contains('reveal')) {
          child.style.transitionDelay = (i * step) + 'ms';
          i++;
        }
      });
    });
  }

  function animateCount(el) {
    var text = el.textContent.trim();
    var m = text.match(/^([+]?)(\d+(?:\s\d{3})*(?:[.,]\d+)?)(.*)$/);
    if (!m) return;
    var prefix = m[1];
    var numPart = m[2];
    var suffix = m[3];
    var hasSpace = /\s/.test(numPart);
    var hasComma = numPart.indexOf(',') !== -1;
    var hasDot = numPart.indexOf('.') !== -1;
    var clean = numPart.replace(/\s/g, '').replace(',', '.');
    var end = parseFloat(clean);
    if (isNaN(end)) return;
    var decimals = (hasComma || hasDot) ? (clean.split('.')[1] || '').length : 0;
    var duration = 1100;
    var start = null;

    function step(ts) {
      if (start === null) start = ts;
      var progress = Math.min((ts - start) / duration, 1);
      var eased = 1 - Math.pow(1 - progress, 3);
      var current = end * eased;
      var out = decimals > 0 ? current.toFixed(decimals) : String(Math.round(current));
      if (hasSpace) {
        var parts = out.split('.');
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
        out = parts.join(',');
      } else if (hasComma) {
        out = out.replace('.', ',');
      }
      el.textContent = prefix + out + suffix;
      if (progress < 1) {
        requestAnimationFrame(step);
      } else {
        el.textContent = prefix + numPart + suffix;
      }
    }
    requestAnimationFrame(step);
  }

  if (!reduceMotion) {
    /* One-shot reveals for secondary content (cards, lists) */
    tagReveal('.feature-visual, .compare-wrap, .store-badges, .pricing-note');
    tagReveal('.chapter-stats > div');
    tagReveal('.pricing-card');
    tagReveal('.faq-item');
    stagger('.chapter-stats', 90);
    stagger('.pricing-grid', 100);
    stagger('.faq-list', 60);

    if ('IntersectionObserver' in window) {
      var observer = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          var el = entry.target;
          el.classList.add('is-visible');
          if (el.classList.contains('chapter-stat-value') && !el.dataset.counted) {
            el.dataset.counted = '1';
            animateCount(el);
          }
          observer.unobserve(el);
        });
      }, { threshold: 0.2, rootMargin: '0px 0px -60px 0px' });

      document.querySelectorAll('.reveal').forEach(function (el) {
        observer.observe(el);
      });
    } else {
      document.querySelectorAll('.reveal').forEach(function (el) {
        el.classList.add('is-visible');
      });
    }

    /* Continuous scroll-scrubbed fade/rise for headlines and big numbers,
       matching the way apple.com fades chapter titles in as they cross
       the middle of the viewport (not a one-shot on/off reveal). */
    document.querySelectorAll(
      '.hero-eyebrow, .hero-title, .hero-subtitle, .hero-cta, ' +
      '.eyebrow, .headline, .headline-sub, .mega-number'
    ).forEach(function (el) {
      el.classList.add('scrub');
    });

    var scrubEls = Array.prototype.slice.call(document.querySelectorAll('.scrub'));
    var scrubTicking = false;

    function scrubProgress(el) {
      var rect = el.getBoundingClientRect();
      var vh = window.innerHeight;
      var start = vh * 0.95;
      var end = vh * 0.55;
      var raw = (start - rect.top) / (start - end);
      return Math.min(Math.max(raw, 0), 1);
    }

    function updateScrub() {
      scrubEls.forEach(function (el) {
        var progress = scrubProgress(el);
        el.style.opacity = String(progress);
        var rise = (1 - progress) * 34;
        var scale = el.classList.contains('mega-number') ? (0.9 + progress * 0.1) : 1;
        el.style.transform = 'translateY(' + rise + 'px)' + (scale !== 1 ? ' scale(' + scale + ')' : '');
        if (el.classList.contains('mega-number') && progress > 0.85 && !el.dataset.counted) {
          el.dataset.counted = '1';
          animateCount(el);
        }
      });
      scrubTicking = false;
    }

    window.addEventListener('scroll', function () {
      if (!scrubTicking) {
        requestAnimationFrame(updateScrub);
        scrubTicking = true;
      }
    }, { passive: true });
    window.addEventListener('resize', updateScrub, { passive: true });
    updateScrub();

    /* Subtle parallax + fade on the hero phone mockup */
    var heroShowcase = document.querySelector('.hero-showcase');
    var hero = document.querySelector('.hero');
    if (heroShowcase && hero) {
      var ticking = false;
      function updateParallax() {
        var heroHeight = hero.offsetHeight || 1;
        var progress = Math.min(Math.max(window.scrollY / heroHeight, 0), 1);
        heroShowcase.style.transform = 'translateY(' + (progress * 70) + 'px) scale(' + (1 - progress * 0.06) + ')';
        heroShowcase.style.opacity = String(Math.max(1 - progress * 1.4, 0));
        ticking = false;
      }
      window.addEventListener('scroll', function () {
        if (!ticking) {
          requestAnimationFrame(updateParallax);
          ticking = true;
        }
      }, { passive: true });
      updateParallax();
    }

    /* Gracefully hide background/demo videos if the placeholder source 404s,
       so the poster image (or CSS background) shows instead of a broken player. */
    document.querySelectorAll('video').forEach(function (video) {
      video.addEventListener('error', function () {
        video.style.display = 'none';
      }, true);
    });
  }
})();
