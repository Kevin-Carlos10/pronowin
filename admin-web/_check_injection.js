/**
 * Deux classes de faille que ni `test_all_views.js` ni `_check_scripts.js` ne
 * voient, parce que la page rend sans erreur dans les deux cas.
 *
 * 1. **Texte utilisateur interpolé dans un gestionnaire inline.**
 *    `onclick="f('<%= nom %>')"` : EJS échappe l'apostrophe en `&#39;`, que le
 *    parseur HTML redécode AVANT que le JavaScript soit lu. Un sous-admin
 *    nommé « N'Diaye » rendait donc trois boutons inertes, sans le moindre
 *    message. `_check_scripts.js` ne regarde que les blocs `<script>`, pas les
 *    attributs — il ne pouvait pas le voir.
 *
 * 2. **`</script>` dans une valeur sérialisée en JSON.**
 *    `JSON.stringify` ne neutralise pas `<` : la séquence referme la balise et
 *    ce qui suit redevient du HTML. Le bloc tronqué compile encore, donc là
 *    aussi tous les autres contrôles restaient verts.
 *
 * On rend chaque vue avec des valeurs hostiles à la place des textes que
 * l'utilisateur contrôle, puis on vérifie ces deux points.
 *
 *   node _check_injection.js
 */
const ejs = require('ejs');
const { views, opts } = require('./test_all_views.js');

/** Ce qu'un navigateur fait des entités avant de livrer l'attribut au moteur JS. */
function decoderEntites(s) {
  return s
    .replace(/&#(\d+);/g,   (_, n) => String.fromCharCode(+n))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCharCode(parseInt(n, 16)))
    .replace(/&quot;/g, '"').replace(/&apos;/g, "'")
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');
}

/**
 * Attributs de gestionnaire, avec leur valeur brute.
 *
 * Le contenu des blocs `<script>` est retiré au préalable : du JavaScript qui
 * construit du HTML contient des `onclick="…"` à l'intérieur de gabarits, et
 * les lire comme des attributs produisait quatre fausses alertes par page.
 */
function gestionnaires(html) {
  const sansScripts = html.replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, '');
  const trouves = [];
  const re = /\s(on[a-z]+)="([^"]*)"/gi;
  let m;
  while ((m = re.exec(sansScripts))) trouves.push({ attr: m[1], code: m[2] });
  return trouves;
}

(async () => {
  const echecs = [];
  let vuesRendues = 0, attributsTestes = 0;

  for (const [label, vue, locals] of views) {
    let html;
    try {
      html = await ejs.renderFile('views/' + vue + '.ejs', locals, opts);
    } catch {
      continue; // `test_all_views.js` signale déjà les vues qui ne rendent pas.
    }
    vuesRendues++;

    // ── 1. Chaque gestionnaire inline doit rester du JavaScript valide une
    //       fois les entités décodées, comme le navigateur le verra.
    for (const { attr, code } of gestionnaires(html)) {
      if (!code.trim()) continue;
      attributsTestes++;
      try {
        new Function(decoderEntites(code));
      } catch (e) {
        echecs.push(
          `${label} — ${attr}="${code.slice(0, 70)}${code.length > 70 ? '…' : ''}"\n` +
          `      → après décodage HTML : ${e.message}`);
      }
    }

    // ── 2. Aucune valeur ne doit pouvoir refermer une balise <script>.
    //       Autant d'ouvertures que de fermetures, sinon une chaîne en a
    //       introduit une de plus.
    const ouvre = (html.match(/<script\b/gi)  || []).length;
    const ferme = (html.match(/<\/script\s*>/gi) || []).length;
    if (ouvre !== ferme) {
      echecs.push(
        `${label} — ${ouvre} balise(s) <script> ouverte(s) pour ${ferme} fermeture(s).\n` +
        `      → une valeur contient « </script> » : la sortie de contexte est possible.`);
    }
  }

  console.log(`${attributsTestes} gestionnaires inline compilés sur ${vuesRendues} vues rendues`);

  if (echecs.length) {
    console.log('\nINJECTIONS POSSIBLES :');
    echecs.forEach(e => console.log('  ' + e));
    console.log('\nRappel : ne jamais interpoler un texte utilisateur dans un attribut');
    console.log('on* ni dans du JSON déposé tel quel dans un <script>. Passez');
    console.log('l\'identifiant en attribut data-, et neutralisez « < » côté JSON.');
  } else {
    console.log('\nAucune interpolation dangereuse.');
  }

  process.exitCode = echecs.length ? 1 : 0;
})();
