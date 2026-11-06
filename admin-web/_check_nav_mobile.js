/**
 * Barre de navigation mobile : ce qu'elle ne doit plus faire.
 *
 * Trois défauts corrigés, qu'aucun autre contrôle ne verrait — la page rend
 * parfaitement dans les trois cas :
 *
 *   1. **La recherche en double.** Sur mobile, la loupe de la barre du haut et
 *      le gros bouton central appelaient tous deux `openSearch()`. Le contrôle
 *      le plus proéminent de l'écran redoublait un bouton situé à trois
 *      centimètres, pendant que le travail quotidien restait dans le menu
 *      latéral.
 *
 *   2. **Un créneau gaspillé.** « Utilisateurs » et « Stats » s'excluaient par
 *      un `if/else`, alors que la barre ne compte que cinq places pour
 *      vingt-trois destinations.
 *
 *   3. **Un bouton isolé étiré sur toute la largeur.** `flex: 1` appliqué sans
 *      condition faisait de « Actualiser » — une action secondaire — le plus
 *      large contrôle du tableau de bord.
 *
 *   node _check_nav_mobile.js
 */
const fs   = require('fs');
const ejs  = require('ejs');
const { views, opts } = require('./test_all_views.js');

const griefs = [];

function extraireNav(html) {
  return (html.match(/<nav class="bottom-nav"[\s\S]*?<\/nav>/) || [''])[0];
}

(async () => {
  // ── Vues rendues ─────────────────────────────────────────────────────────
  let examinees = 0;

  for (const [, vue, locals] of views) {
    let html;
    try { html = await ejs.renderFile('views/' + vue + '.ejs', locals, opts); }
    catch { continue; }

    const nav = extraireNav(html);
    if (!nav) continue;
    examinees++;

    // 1. La recherche ne doit pas être atteignable deux fois sur le même
    //    écran.
    //
    //    Première version de cette règle : « le bouton central ne doit pas à
    //    la fois mener quelque part et ouvrir la recherche ». Elle ne
    //    déclenchait pas quand on remettait simplement un bouton de recherche
    //    au centre — c'est-à-dire sur le défaut d'origine exactement. La règle
    //    porte maintenant sur ce qui compte : deux déclencheurs visibles en
    //    même temps.
    const loupeEnHaut = /class="search-trigger-btn"/.test(html);
    const rechercheEnBas = (nav.match(/openSearch/g) || []).length > 0;
    if (loupeEnHaut && rechercheEnBas) {
      griefs.push(`${vue} : la recherche est atteignable depuis la barre du ` +
                  `haut ET depuis la barre du bas.`);
    }

    // 2. La barre doit exposer plus de créneaux qu'avant. Quatre était le
    //    compte de l'ancienne version, dont un perdu en doublon.
    // Le gabarit interpole `active` dans l'attribut : `class="bottom-nav-item
    // active"` ou `class="bottom-nav-item "`. Chercher la valeur exacte ne
    // trouvait que le bouton central, seul à ne pas être interpolé.
    const creneaux = (nav.match(/class="bottom-nav-(item|fab)[ "]/g) || []).length;
    if (creneaux < 4) {
      griefs.push(`${vue} : seulement ${creneaux} créneaux dans la barre.`);
    }

    // 3. Aucun créneau ne doit imposer une largeur minimale qui déborderait :
    //    c'est le CSS qui borne, mais un `style=` en dur contournerait la règle.
    if (/bottom-nav-item[^>]*style="[^"]*min-width/.test(nav)) {
      griefs.push(`${vue} : largeur minimale forcée en ligne sur un créneau.`);
    }
  }

  // ── Feuille de style ─────────────────────────────────────────────────────
  const css = fs.readFileSync('public/style.css', 'utf8');

  // Le `flex: 1` inconditionnel sur les boutons de la topbar.
  if (/\.topbar\s*>\s*div:last-child\s+\.btn\s*\{[^}]*flex:\s*1\b/.test(css)) {
    griefs.push('style.css : `.topbar > div:last-child .btn { flex: 1 }` sans ' +
                'condition — un bouton isolé occupera toute la largeur.');
  }
  if (!/\.btn:not\(:only-child\)/.test(css)) {
    griefs.push('style.css : le partage de largeur ne distingue plus le cas ' +
                'du bouton unique (`:not(:only-child)` absent).');
  }

  // Le libellé d'un créneau doit pouvoir se tronquer.
  if (!/\.bottom-nav-item[^{]*\{[^}]*text-overflow:\s*ellipsis/.test(css)) {
    griefs.push('style.css : les libellés de la barre ne se tronquent pas — ' +
                '« Utilisateurs » débordera sur un écran de 320 px.');
  }

  // La barre du bas doit s'effacer quand le menu latéral s'ouvre.
  //
  // À un z-index supérieur, elle restait allumée et cliquable par-dessus le
  // tiroir : deux navigations en concurrence, et surtout ses 64 px
  // recouvraient le bas du menu — panneau Thème, Mon profil, Déconnexion. Sur
  // un écran court, se déconnecter devenait impossible.
  const couche = (selecteur) => {
    const bloc = css.match(
      new RegExp(`\\${selecteur}\\s*\\{[^}]*z-index:\\s*(-?\\d+)`));
    return bloc ? Number(bloc[1]) : null;
  };
  const zBarre   = couche('.bottom-nav');
  const zTiroir  = couche('.sidebar');
  const zVoile   = couche('.sidebar-overlay');

  if (zBarre === null || zTiroir === null || zVoile === null) {
    griefs.push('style.css : impossible de lire les z-index de la barre, du ' +
                'tiroir ou du voile — la superposition n\'est plus vérifiable.');
  } else if (zBarre >= zVoile || zBarre >= zTiroir) {
    griefs.push(`style.css : la barre du bas (z-index ${zBarre}) passe ` +
                `au-dessus du tiroir (${zTiroir}) ou de son voile (${zVoile}) ` +
                `— elle masquera la déconnexion.`);
  }

  console.log(`${examinees} vues avec barre mobile examinées`);
  if (griefs.length === 0) {
    console.log('\nLa barre mobile ne fait plus doublon et ne déborde pas.');
    process.exitCode = 0;
  } else {
    console.log(`\n${griefs.length} problème(s) :`);
    griefs.forEach(g => console.log('  · ' + g));
    process.exitCode = 1;
  }
})();
