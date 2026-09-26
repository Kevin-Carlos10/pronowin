/**
 * Contrôle syntaxique du JavaScript embarqué dans les vues.
 *
 * `test_all_views.js` vérifie que les vues *rendent*. Mais un `<script>` est
 * du texte pour EJS : il peut contenir n'importe quoi et la vue rendra très
 * bien. Le navigateur, lui, abandonne le bloc entier à la première erreur —
 * et tout ce qu'il contient cesse de fonctionner en silence.
 *
 * Trois pannes de cette nature dans la même journée, toutes dues à la même
 * cause : une apostrophe française dans une chaîne délimitée par des
 * apostrophes (`'Il n'apparaît pas…'`). Aucune n'a été vue par les autres
 * contrôles, et la dernière avait supprimé toute notification de la page
 * Pronostics sans le moindre message.
 *
 *   node _check_scripts.js
 */
const ejs = require('ejs');
const { views, opts } = require('./test_all_views.js');

(async () => {
  let controles = 0;
  const echecs = [];

  for (const [label, vue, locals] of views) {
    let html;
    try {
      html = await ejs.renderFile('views/' + vue + '.ejs', locals, opts);
    } catch (e) {
      echecs.push(`${label} — rendu impossible : ${e.message.split('\n')[0]}`);
      continue;
    }

    // Uniquement les scripts inline : ceux qui portent `src` ne sont pas ici.
    const blocs = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)]
      .map(m => m[1]);

    blocs.forEach((code, i) => {
      if (!code.trim()) return;
      controles++;
      try {
        // `new Function` compile sans exécuter : exactement ce qu'on veut.
        new Function(code);
      } catch (e) {
        const ligne = _ligneFautive(code, e.message);
        echecs.push(`${label} — script #${i} : ${e.message}${ligne ? `\n      → ${ligne}` : ''}`);
      }
    });
  }

  console.log(`${controles} blocs <script> compilés sur ${views.length} vues`);

  if (echecs.length) {
    console.log('\nSCRIPTS INVALIDES :');
    echecs.forEach(e => console.log('  ' + e));
    console.log('\nRappel : une apostrophe française dans une chaîne \'…\' casse le bloc.');
    console.log('Utilisez des guillemets doubles pour tout texte français.');
  } else {
    console.log('\nTous les scripts embarqués compilent.');
  }

  process.exitCode = echecs.length ? 1 : 0;
})();

/** Meilleur effort pour montrer la ligne coupable, le message seul étant sec. */
function _ligneFautive(code, message) {
  const m = message.match(/Unexpected identifier '([^']+)'/)
         ?? message.match(/Unexpected token '([^']+)'/);
  if (!m) return null;
  const lignes = code.split('\n');
  const i = lignes.findIndex(l => l.includes(m[1]));
  return i >= 0 ? lignes[i].trim().slice(0, 100) : null;
}
