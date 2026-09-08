/**
 * Aucun bouton ne doit être relié à rien.
 *
 * Le bouton « Confirmer » de la boîte partagée n'appelait rien depuis le commit
 * initial : « Annuler » avait son gestionnaire, pas lui. Dix-huit actions dans
 * douze vues ne pouvaient donc pas aboutir — bannir, valider un versement,
 * supprimer un sous-admin, vider le journal. Sans erreur, sans message : on
 * cliquait, il ne se passait rien, et on croyait le clic mal pris.
 *
 * `_check_scripts.js` compile les gestionnaires inline ; il ne peut pas
 * signaler celui qui *manque*. `_check_confirmation.js` couvre cette boîte-là.
 * Ce contrôle-ci couvre tous les autres boutons du panneau.
 *
 * ── Ce qui compte comme « relié » ──
 *
 *   - un attribut on*
 *   - type=submit (ou pas de type) à l'intérieur d'un form, ou un attribut form=
 *   - un id sur lequel un addEventListener est posé, directement ou via la
 *     variable qui le range
 *   - une classe ou un attribut vus dans un querySelector(All) suivi d'un
 *     addEventListener, ou dans un closest()/matches() d'écouteur délégué
 *
 * ── Deux erreurs de conception, corrigées après mesure ──
 *
 * La détection « à l'intérieur d'un form » passait par `parentNode` : elle
 * déclarait muets les boutons d'envoi de `tutoriel_form`, pourtant bien dans
 * leur formulaire. Le contrôle travaille donc sur le HTML rendu comme chaîne,
 * en comparant les positions de `<form` et `</form>`.
 *
 * Et `dataset.x` lu quelque part dans le script était compté comme un
 * rattachement : un seul `dataset.result` suffisait à blanchir tout bouton
 * portant `data-result`. Éprouvé en cassant volontairement l'écouteur de
 * `.force-result-btn` : l'audit ne signalait rien. Règle retirée.
 *
 * Ces deux corrections vont en sens inverse, et c'est le but : un contrôle qui
 * accuse du code correct finit désarmé ; un contrôle qui blanchit tout ne sert
 * à rien. Éprouvé dans les deux sens — gestionnaire retiré de la boîte de
 * confirmation, puis écouteur délégué cassé : signalés tous les deux.
 *
 *   node _check_boutons.js
 */
const ejs = require('ejs');
const { views, opts } = require('./test_all_views.js');

const scriptsDe = (html) =>
  [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)]
    .map((m) => m[1]).join('\n');

/** Tout ce que les scripts désignent puis écoutent. */
function cibles(js) {
  const ids = new Set(), classes = new Set(), attributs = new Set();
  const noter = (sel) => {
    for (const part of sel.split(',')) {
      const s = part.trim();
      let m;
      if ((m = /^#([\w-]+)$/.exec(s)))            ids.add(m[1]);
      else if ((m = /\.([\w-]+)/.exec(s)))        classes.add(m[1]);
      else if ((m = /\[([\w-]+)[\]=]/.exec(s)))   attributs.add(m[1]);
    }
  };

  for (const m of js.matchAll(/querySelectorAll?\(\s*['"`]([^'"`]+)['"`]\s*\)([\s\S]{0,220})/g)) {
    if (/addEventListener|\.onclick\s*=/.test(m[2])) noter(m[1]);
  }
  for (const m of js.matchAll(/getElementById\(\s*['"]([\w-]+)['"]\s*\)([\s\S]{0,160})/g)) {
    if (/addEventListener|\.onclick\s*=/.test(m[2])) ids.add(m[1]);
  }
  for (const m of js.matchAll(/\.(?:closest|matches)\(\s*['"`]([^'"`]+)['"`]\s*\)/g)) noter(m[1]);
  for (const m of js.matchAll(/classList\.contains\(\s*['"]([\w-]+)['"]\s*\)/g)) classes.add(m[1]);
  // `dataset.x` lu quelque part dans le script ne prouve rien : il suffisait
  // d'un `dataset.result` pour que TOUT bouton portant `data-result` passe pour
  // câblé. Éprouvé : en cassant volontairement l'écouteur de
  // `.force-result-btn`, l'audit ne signalait rien. Le rattachement réel se lit
  // dans un `closest()`, un `matches()` ou un `querySelectorAll()` — traités
  // au-dessus.
  // Cas courant : l'element est range dans une variable, et l'ecouteur est
  // pose bien plus loin. `const closeBtn = getElementById('online-close')` puis,
  // cinquante lignes apres, `closeBtn.addEventListener(...)`. Une fenetre de
  // caracteres apres l'appel ne peut pas le voir.
  for (const m of js.matchAll(/(?:const|let|var)\s+([\w$]+)\s*=\s*document\.(?:getElementById|querySelector)\(\s*['"`]#?([\w-]+)['"`]\s*\)/g)) {
    const [, variable, cible] = m;
    const motif = new RegExp('\\b' + variable + '\\s*\\.\\s*(?:addEventListener|onclick\\s*=)');
    if (motif.test(js)) ids.add(cible);
  }
  return { ids, classes, attributs };
}

/** Le bouton à l'index i est-il à l'intérieur d'un form ouvert ? */
function dansUnForm(html, i) {
  const avant = html.slice(0, i);
  const ouv = avant.lastIndexOf('<form');
  const fer = avant.lastIndexOf('</form>');
  return ouv !== -1 && ouv > fer;
}

(async () => {
  const muets = new Map();
  let examines = 0;
  const vues = new Set();

  for (const [, vue, locaux] of views) {
    let html;
    try { html = await ejs.renderFile('views/' + vue + '.ejs', locaux, opts); }
    catch { continue; }
    vues.add(vue);

    const js = scriptsDe(html);
    const { ids, classes, attributs } = cibles(js);

    for (const m of html.matchAll(/<button\b([^>]*)>([\s\S]*?)<\/button>/g)) {
      examines++;
      const attrs  = m[1];
      const texte  = m[2].replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
      const balise = ('<button' + attrs + '>').slice(0, 150);

      if (/\son[a-z]+\s*=/.test(attrs)) continue;
      if (/\sform\s*=/.test(attrs)) continue;

      const type = (/\stype\s*=\s*['"]([^'"]*)['"]/.exec(attrs) || [, ''])[1].toLowerCase();
      if (type !== 'button' && dansUnForm(html, m.index)) continue;

      const id = (/\sid\s*=\s*['"]([^'"]*)['"]/.exec(attrs) || [, ''])[1];
      if (id && ids.has(id)) continue;

      const cls = (/\sclass\s*=\s*['"]([^'"]*)['"]/.exec(attrs) || [, ''])[1].split(/\s+/);
      if (cls.some((c) => classes.has(c))) continue;

      const sesAttrs = [...attrs.matchAll(/\s([\w-]+)\s*=/g)].map((a) => a[1]);
      if (sesAttrs.some((a) => attributs.has(a))) continue;

      const signature = vue + '|' + balise;
      if (!muets.has(signature)) muets.set(signature, { vue, texte, balise });
    }
  }

  // Sans ce garde-fou, une fixture cassée ou un chemin de vues changé rendrait
  // zéro bouton — et le contrôle passerait au vert en n'ayant rien regardé.
  if (examines < 500) {
    console.log(`\n❌ ${examines} boutons seulement : le rendu des vues a échoué, `
              + 'ce contrôle ne prouve rien en l\'état.\n');
    process.exit(1);
  }

  console.log(`\n${examines} boutons rendus, ${vues.size} vues\n`);
  console.log(`── Boutons sans chemin d'action (${muets.size}) ──`);
  for (const { vue, texte, balise } of muets.values()) {
    console.log(`  ! ${vue} — « ${texte || '(sans texte)'} »`);
    console.log(`      ${balise}`);
  }
  if (!muets.size) console.log('  aucun');

  console.log(muets.size === 0
    ? '\n✅ Chaque bouton du panneau mène quelque part\n'
    : `\n❌ ${muets.size} bouton(s) dont le clic ne fera rien. Si l'un d'eux est `
    + 'relié par un motif que ce contrôle ne connaît pas, ajoutez ce motif à '
    + '`cibles()` — délibérément, en le décrivant.\n');
  process.exit(muets.size === 0 ? 0 : 1);
})();
