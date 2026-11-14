/**
 * Aucun script du panneau ne vient d'un tiers.
 *
 * Le tableau de bord chargeait Chart.js depuis cdn.jsdelivr.net. Le poste
 * depuis lequel on consulte le panneau ne joint pas ce domaine — code 000
 * après onze secondes, mesuré. `Chart` restait donc indéfini,
 * `applyChartDefaults()` levait une ReferenceError, et le bloc entier
 * s'arrêtait : trois panneaux noirs, badges figés sur « … », aucune erreur à
 * l'écran.
 *
 * Le service local existait déjà : `server.js` monte `/vendor/chart.js`
 * depuis `node_modules`, et la page Statistiques s'en servait. Le même défaut
 * vivait à deux endroits, corrigé à un seul — c'est ce que ce contrôle
 * empêche de refaire.
 *
 * **Scripts seulement.** Une feuille de style absente dégrade : la pile de
 * polices de repli prend le relais et la page reste lisible. Un script absent
 * n'a pas de repli — il emporte tout ce qui suit dans son bloc. Les deux
 * échouent en silence ; un seul rend la page inutilisable.
 *
 *   node _check_dependances_externes.js
 */
const fs   = require('fs');
const path = require('path');

const DOSSIER = path.join(__dirname, 'views');

/** `<script src="…">` dont la source est absolue (http, https ou //). */
const SCRIPT_EXTERNE = /<script[^>]*\ssrc\s*=\s*["'](https?:)?\/\/[^"']+["'][^>]*>/gi;

const fautifs = [];
const styles  = [];

function parcourir(dossier) {
  for (const entree of fs.readdirSync(dossier, { withFileTypes: true })) {
    const chemin = path.join(dossier, entree.name);
    if (entree.isDirectory()) { parcourir(chemin); continue; }
    if (!entree.name.endsWith('.ejs')) continue;

    const source = fs.readFileSync(chemin, 'utf8');

    // Les commentaires EJS (<%# … %>) citent l'ancienne URL pour expliquer le
    // défaut. Un contrôle qui se valide sur sa propre prose ne contrôle rien.
    const code = source.replace(/<%#[\s\S]*?%>/g, '');

    const relatif = path.relative(__dirname, chemin).replace(/\\/g, '/');

    for (const trouve of code.matchAll(SCRIPT_EXTERNE)) {
      fautifs.push(`${relatif} → ${trouve[0].slice(0, 110)}`);
    }
    if (/<link[^>]*\shref\s*=\s*["'](https?:)?\/\//i.test(code)) {
      styles.push(relatif);
    }
  }
}

parcourir(DOSSIER);

console.log('');
if (fautifs.length) {
  console.log('  ÉCHEC — script(s) chargé(s) depuis un tiers :\n');
  for (const f of fautifs) console.log(`    ${f}`);
  console.log('\n  Un script injoignable emporte tout son bloc, sans erreur visible.');
  console.log('  Servez-le depuis le panneau : voir /vendor/chart.js dans server.js.\n');
  process.exit(1);
}

console.log('  OK — aucun script chargé depuis un tiers');
if (styles.length) {
  console.log(`  (${styles.length} vue(s) chargent une feuille de style externe —`);
  console.log('   toléré : une police absente dégrade, elle ne casse rien)');
}
console.log('');
