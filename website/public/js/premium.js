/*
 * Paiement Mobile Money depuis le site (13 octobre 2026).
 *
 * Trois étapes : l'adresse du compte, le code reçu par e-mail, la formule.
 * Le code ouvre un jeton de paiement de 30 minutes (jamais une session de
 * l'application), gardé le temps de l'onglet. Au retour de GeniusPay
 * (?p=<paiement>), la page suit le paiement jusqu'à l'activation.
 */
(function () {
  'use strict';

  var API = '/api/v1/paiement-web';
  var ETAPES = ['identification', 'code', 'formule', 'suivi'];
  var CLE_JETON = 'pronowin-paiement';
  var email = '';
  var formules = {};

  function el(id) { return document.getElementById(id); }

  function lireJeton() {
    try { return sessionStorage.getItem(CLE_JETON); } catch (e) { return null; }
  }
  function ecrireJeton(jeton) {
    try {
      if (jeton) sessionStorage.setItem(CLE_JETON, jeton);
      else sessionStorage.removeItem(CLE_JETON);
    } catch (e) { /* stockage indisponible : la page reste utilisable */ }
  }

  function montrer(nom) {
    ETAPES.forEach(function (e) { el('etape-' + e).hidden = e !== nom; });
    var champ = el('etape-' + nom).querySelector('input:not([type=radio])');
    if (champ) champ.focus();
  }

  function message(id, texte, erreur) {
    var m = el(id);
    m.textContent = texte || '';
    m.classList.toggle('pay-msg--erreur', !!erreur);
  }

  function fcfa(n) {
    return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + ' FCFA';
  }

  function dateLongue(iso) {
    var d = new Date(iso);
    return isNaN(d) ? '' : d.toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' });
  }

  function appel(chemin, options) {
    options = options || {};
    var entetes = { 'Content-Type': 'application/json', Accept: 'application/json' };
    if (options.jeton) entetes.Authorization = 'Bearer ' + options.jeton;
    return fetch(API + chemin, {
      method: options.methode || 'GET',
      headers: entetes,
      body: options.corps ? JSON.stringify(options.corps) : undefined,
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (d) {
        if (!r.ok) {
          var e = new Error(d.message || 'Une erreur est survenue. Réessayez dans un instant.');
          e.statut = r.status;
          throw e;
        }
        return d;
      });
    });
  }

  function occupe(formulaire, oui) {
    var b = formulaire.querySelector('button[type=submit]');
    b.disabled = oui;
    b.setAttribute('aria-busy', oui ? 'true' : 'false');
  }

  /** Jeton expiré : on repart de l'adresse, avec une explication. */
  function recommencer(texte) {
    ecrireJeton(null);
    montrer('identification');
    message('msg-email', texte, true);
  }

  // ── 1. Adresse ─────────────────────────────────────────────────────────
  el('form-email').addEventListener('submit', function (ev) {
    ev.preventDefault();
    var saisie = el('email').value.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(saisie)) {
      message('msg-email', 'Indiquez une adresse e-mail valide.', true);
      return;
    }
    occupe(ev.target, true);
    message('msg-email', '');
    appel('/code', { methode: 'POST', corps: { email: saisie } }).then(function (d) {
      email = saisie;
      el('texte-code').textContent = d.message + ' Il est valable 10 minutes.';
      el('code').value = '';
      montrer('code');
    }).catch(function (e) {
      message('msg-email', e.message, true);
    }).then(function () { occupe(ev.target, false); });
  });

  // ── 2. Code ────────────────────────────────────────────────────────────
  el('form-code').addEventListener('submit', function (ev) {
    ev.preventDefault();
    var code = el('code').value.replace(/\s/g, '');
    if (!/^\d{4,8}$/.test(code)) {
      message('msg-code', 'Saisissez les chiffres du code reçu.', true);
      return;
    }
    occupe(ev.target, true);
    message('msg-code', '');
    appel('/verifier', { methode: 'POST', corps: { email: email, code: code } }).then(function (d) {
      ecrireJeton(d.jeton);
      var texte = 'Compte : ' + d.compte.pseudo + '.';
      if (d.compte.premium_jusqu_au) {
        texte += ' Premium actif jusqu\'au ' + dateLongue(d.compte.premium_jusqu_au) + ' : ce paiement le prolonge.';
      }
      el('texte-compte').textContent = texte;
      if (!d.paiement_ouvert) {
        message('msg-formule', 'Le paiement Mobile Money n\'est pas encore ouvert pour ce compte.', true);
        el('bouton-payer').disabled = true;
      }
      montrer('formule');
    }).catch(function (e) {
      message('msg-code', e.message, true);
    }).then(function () { occupe(ev.target, false); });
  });

  el('changer-adresse').addEventListener('click', function () {
    message('msg-code', '');
    montrer('identification');
  });

  // ── 3. Formule ─────────────────────────────────────────────────────────
  el('form-formule').addEventListener('submit', function (ev) {
    ev.preventDefault();
    var jeton = lireJeton();
    if (!jeton) { recommencer('Identification expirée : indiquez à nouveau votre adresse.'); return; }
    var plan = ev.target.querySelector('input[name=plan]:checked').value;
    occupe(ev.target, true);
    message('msg-formule', '');
    appel('/payer', { methode: 'POST', jeton: jeton, corps: { plan: plan } }).then(function (d) {
      window.location.assign(d.checkout_url);
    }).catch(function (e) {
      occupe(ev.target, false);
      if (e.statut === 401) recommencer(e.message);
      else message('msg-formule', e.message, true);
    });
  });

  /** Le montant de la formule choisie, sur le bouton. */
  function majBouton() {
    var choisi = document.querySelector('input[name=plan]:checked');
    var f = choisi && formules[choisi.value];
    if (f) el('bouton-payer').textContent = 'Payer ' + fcfa(f.montant) + ' par Mobile Money';
  }
  Array.prototype.forEach.call(document.querySelectorAll('input[name=plan]'), function (r) {
    r.addEventListener('change', majBouton);
  });

  // ── Suivi au retour de GeniusPay ───────────────────────────────────────
  function suivre(id, echec) {
    montrer('suivi');
    var jeton = lireJeton();
    if (echec) {
      el('texte-suivi').textContent = 'Le paiement n\'a pas abouti. Aucun montant n\'a été validé pour votre abonnement.';
      el('reessayer').hidden = false;
      return;
    }
    if (!jeton) {
      el('texte-suivi').textContent = 'Merci ! Votre paiement est en cours de confirmation. Le Premium s\'activera sur votre compte dès que l\'opérateur l\'aura confirmé : une notification vous préviendra dans l\'application.';
      return;
    }
    var essais = 0;
    (function tour() {
      appel('/etat/' + encodeURIComponent(id), { jeton: jeton }).then(function (d) {
        if (d.premium_active) {
          el('texte-suivi').textContent = 'Votre Premium est actif' +
            (d.expire_le ? ' jusqu\'au ' + dateLongue(d.expire_le) : '') +
            '. Ouvrez l\'application PronoWin : il y est déjà débloqué.';
          ecrireJeton(null);
          return;
        }
        if (['failed', 'cancelled', 'expired'].indexOf(d.statut) >= 0) {
          el('texte-suivi').textContent = 'Le paiement n\'a pas abouti. Aucun montant n\'a été validé pour votre abonnement.';
          el('reessayer').hidden = false;
          return;
        }
        if (d.statut === 'anomalie') {
          el('texte-suivi').textContent = 'Le paiement reçu ne correspond pas à la formule choisie. Notre équipe vérifie et vous recontacte.';
          return;
        }
        essais += 1;
        if (essais > 150) {
          el('texte-suivi').textContent = 'Toujours pas de confirmation. Si vous avez payé, le Premium s\'activera dès que l\'opérateur confirmera : une notification vous préviendra dans l\'application.';
          return;
        }
        setTimeout(tour, 4000);
      }).catch(function (e) {
        if (e.statut === 401) {
          el('texte-suivi').textContent = 'Votre paiement est en cours de confirmation. Le Premium s\'activera sur votre compte dès que l\'opérateur l\'aura confirmé.';
          return;
        }
        setTimeout(tour, 6000);
      });
    })();
  }

  el('reessayer').addEventListener('click', function () {
    window.history.replaceState(null, '', window.location.pathname);
    if (lireJeton()) montrer('formule');
    else montrer('identification');
  });

  // ── Démarrage ──────────────────────────────────────────────────────────
  appel('/offre').then(function (offre) {
    (offre.formules || []).forEach(function (f) {
      formules[f.id] = f;
      var cible = document.querySelector('[data-prix="' + f.id + '"]');
      if (cible) cible.textContent = fcfa(f.montant);
    });
    majBouton();
    if (!offre.disponible) { indisponible(); return; }
    var params = new URLSearchParams(window.location.search);
    var id = params.get('p');
    if (id) suivre(id, params.get('statut') === 'echec');
  }).catch(indisponible);

  function indisponible() {
    el('indisponible').hidden = false;
    ETAPES.forEach(function (e) { el('etape-' + e).hidden = true; });
  }
})();
