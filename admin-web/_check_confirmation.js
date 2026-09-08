/**
 * Une boîte de confirmation doit confirmer quelque chose.
 *
 * Depuis le commit initial, le bouton « Confirmer » de la boîte partagée
 * n'appelait rien :
 *
 *     <button class="btn btn-outline" onclick="closeConfirm()">Annuler</button>
 *     <button class="btn btn-primary" id="confirm-ok-btn">Confirmer</button>
 *
 * « Annuler » avait son gestionnaire, pas lui. `submitConfirm()` était définie
 * dans layout_bottom.ejs et référencée nulle part. La boîte s'ouvrait, on
 * cliquait, il ne se passait rien — sans erreur visible, donc on croyait le
 * clic mal pris et on recommençait.
 *
 * Toutes les confirmations du panneau étaient concernées : bannir un
 * utilisateur, lever un ban, valider ou rejeter un versement, supprimer un
 * sous-admin, un tutoriel, une actualité, un pronostic, vider le journal
 * d'audit. Aucune de ces actions ne pouvait aboutir depuis l'interface.
 *
 * Rien ne pouvait le voir : la vue se rendait, le bouton s'affichait, le
 * script compilait. `_check_scripts.js` compile les gestionnaires inline — il
 * ne peut pas signaler celui qui *manque*. C'est ce trou que ce contrôle
 * ferme : il vérifie qu'un chemin relie le bouton à la fonction, et que cette
 * fonction rappelle bien ce qu'on lui a confié.
 *
 *   node _check_confirmation.js
 */
const fs   = require('fs');
const path = require('path');

let echecs = 0;
const ko = (m) => { console.log('  ✗ ' + m); echecs++; };
const ok = (m) => console.log('  ✓ ' + m);

const lire = (f) => fs.readFileSync(path.join(__dirname, 'views', f), 'utf8');
const haut = lire('layout_top.ejs');
const bas  = lire('layout_bottom.ejs');

console.log('\nBoîte de confirmation partagée');

// ── 1. Le bouton mène quelque part ──
const bouton = haut.match(/<button[^>]*id="confirm-ok-btn"[^>]*>/);
if (!bouton) {
  ko('le bouton #confirm-ok-btn a disparu de layout_top.ejs');
} else {
  const inline = /onclick="([^"]+)"/.exec(bouton[0]);
  // Un écouteur posé depuis le script convient aussi.
  const ecouteur = /confirm-ok-btn'\)[\s\S]{0,120}addEventListener\(\s*'click'/.test(bas);
  if (inline || ecouteur) {
    ok(`le bouton « Confirmer » appelle ${inline ? inline[1] : 'un écouteur enregistré'}`);
  } else {
    ko('le bouton « Confirmer » n\'appelle rien : la boîte s\'ouvre, le clic ne '
     + 'fait rien, et aucune erreur ne le signale');
  }

  // Et ce qu'il appelle doit exister.
  if (inline) {
    const nom = inline[1].replace(/\(.*$/, '').trim();
    if (new RegExp(`function\\s+${nom}\\s*\\(`).test(bas)) {
      ok(`${nom}() est bien définie`);
    } else {
      ko(`${nom}() est appelée mais n'est définie nulle part dans layout_bottom.ejs`);
    }
  }
}

// ── 2. Le chemin va jusqu'au bout ──
//
// Un bouton relié à une fonction vide passerait le point précédent. La
// fonction doit rappeler ce que `askConfirm` lui a confié.
const corps = bas.slice(bas.indexOf('function submitConfirm'));
const bloc  = corps.slice(0, corps.indexOf('\n}') + 2);
if (/_confirmCallback/.test(bloc) && /callback\(\)/.test(bloc)) {
  ok('submitConfirm() rappelle la fonction confiée à askConfirm');
} else {
  ko('submitConfirm() n\'exécute pas la fonction confiée : le bouton se relie à '
   + 'du vide');
}

// ── 3. « Annuler » doit continuer de fermer ──
// Sans ce point, supprimer les deux gestionnaires passerait le contrôle si on
// ne testait que la présence de l'un.
if (/onclick="closeConfirm\(\)"/.test(haut)) {
  ok('« Annuler » ferme toujours la boîte');
} else {
  ko('« Annuler » n\'appelle plus closeConfirm()');
}

// ── 4. Le message s'affiche comme il est écrit ──
//
// Douze appelants mettent en gras la partie qui compte — le nom supprimé, le
// montant validé. Rendu par `textContent`, le message affichait les balises en
// toutes lettres : « supprimer <strong>Lonfo lookman</strong> ? ».
console.log('\nMessage de la boîte');

const appelants = fs.readdirSync(path.join(__dirname, 'views'))
  .filter((f) => f.endsWith('.ejs'))
  .filter((f) => /msg\s*:[^\n]*<strong>/.test(lire(f)) && f !== 'layout_bottom.ejs');

if (appelants.length === 0) {
  ok('aucun appelant ne met en forme son message');
} else {
  const rendu = bas.slice(bas.indexOf("getElementById('confirm-msg')"));
  const ligne = rendu.slice(0, 400);
  if (/\.textContent\s*=/.test(ligne.split('\n')[0])) {
    ko(`${appelants.length} vue(s) mettent en gras une partie du message, mais `
     + 'il est posé en texte brut : les balises s\'afficheront en toutes lettres');
  } else if (/innerHTML/.test(ligne)) {
    // Rendu en HTML : l'échappement doit précéder, sinon un pseudo saisi par un
    // utilisateur s'exécute dans le panneau d'administration.
    const echappeAvant = ligne.indexOf('&amp;') !== -1
                      && ligne.indexOf('&amp;') < ligne.indexOf('<$1strong>');
    if (echappeAvant) {
      ok(`le message est échappé puis <strong> réautorisé (${appelants.length} vues concernées)`);
    } else {
      ko('le message est rendu en HTML sans échappement préalable : un pseudo ou '
       + 'un titre saisi par un utilisateur s\'exécuterait dans le panneau');
    }
  } else {
    ko('impossible de déterminer comment le message est affiché');
  }
}

console.log(echecs === 0
  ? '\n✅ Les confirmations aboutissent, et leur message s\'affiche correctement\n'
  : `\n❌ ${echecs} problème(s)\n`);
process.exit(echecs === 0 ? 0 : 1);
