/**
 * Banc d'injection : chaque garde de `test_contenu.js` doit échouer quand on
 * réintroduit le défaut qu'elle prétend interdire.
 *
 * Un contrôle qui passe sur du code correct ne prouve rien. Celui-ci remet le
 * défaut, exige l'échec, puis restaure — et vérifie l'octet près que la
 * restauration est exacte. Une injection qui ne casse rien (« INJECTION
 * IMPOSSIBLE ») est un échec du banc, pas un succès du code.
 *
 *     node test_injections.js
 */
const fs = require('fs');
const { execFileSync } = require('child_process');

const INJECTIONS = [
  {
    // Le cas exact que l'on vient de retirer : un chiffre vrai, recopie du
    // serveur, qui devient faux le jour ou la constante bouge.
    nom: 'une cadence de synchronisation est republiee',
    fichier: 'server.js',
    de: "    title: 'Le score en direct.\\nPendant que le match se joue.',",
    vers: "    title: 'Le score en direct.\\nToutes les 30 secondes.',",
  },
  {
    // Ancre posee sur legal.ejs : index.ejs porte la marque deux fois (barre et
    // pied de page), et le banc exige une ancre unique. Le controle verifie les
    // deux pages, l'injection sur l'une suffit a le mettre en defaut.
    nom: 'le nom de la marque redevient un noeud de texte nu',
    fichier: 'views/legal.ejs',
    de: '<span class="brand-name">Prono<span class="brand-win">Win</span></span>',
    vers: 'Prono<span>Win</span>',
  },
  {
    nom: 'un montant de parrainage est republie',
    fichier: 'server.js',
    de: "      { value: 'Des gains',  label: 'à chaque filleul inscrit' },",
    vers: "      { value: '500 F',   label: 'par filleul inscrit' },",
  },
  {
    nom: 'un pourcentage de mise est republie',
    fichier: 'server.js',
    de: "      { value: 'Mise',  label: 'calculée, pas devinée' },",
    vers: "      { value: '1,5 – 5 %', label: 'du solde, selon la confiance' },",
  },
  {
    // L'ancre precedente visait une tuile du chapitre « Abonnement », lui-meme
    // retire depuis. Elle vise desormais la FAQ, qui reste le seul endroit du
    // site ou le delai est evoque.
    nom: 'le delai de validation est republie',
    fichier: 'server.js',
    de: "le délai annoncé s'affiche dans l'application au moment de l'envoi.",
    vers: "annoncée sous 30 minutes ouvrables.",
  },
  {
    nom: 'un faux témoignage revient',
    fichier: 'views/index.ejs',
    de: '  <!-- Pricing -->',
    vers: '  <p class="quote-attribution">Kader B. — Parieur amateur, Ouagadougou</p>\n  <!-- Pricing -->',
  },
  {
    nom: 'un sport que l\'app ne traite pas revient',
    fichier: 'server.js',
    de: "    eyebrow: 'Pronostics',",
    vers: "    eyebrow: 'Pronostics, basketball et tennis',",
  },
  {
    nom: 'le tarif du serveur cesse d\'être lu',
    fichier: 'server.js',
    de: '      if (p && typeof p.price_usd === \'number\' && p.price_usd > 0) par[p.id] = p.price_usd;',
    vers: '      if (false) par[p.id] = p.price_usd;',
  },
  {
    nom: 'un tarif de repli est inventé quand l\'API se tait',
    fichier: 'server.js',
    de: "    price: f.id === 'free' ? '0' : (tarifs[f.id] ? montant(tarifs[f.id]) : null),",
    vers: "    price: f.id === 'free' ? '0' : (tarifs[f.id] ? montant(tarifs[f.id]) : '9'),",
  },
  {
    nom: 'le grand chiffre redevient un index de position',
    fichier: 'views/index.ejs',
    de: '      <div class="mega-number"><%= bilan.taux_reussite %>%</div>',
    vers: '      <div class="mega-number">12%</div>',
  },
  {
    nom: 'la section du taux s\'affiche sans taux publié',
    fichier: 'views/index.ejs',
    de: '  <% if (bilan) { %>',
    vers: '  <% if (true) { %>',
  },
  {
    nom: 'un lien mort revient',
    fichier: 'views/index.ejs',
    de: '            <li><a href="#faq">FAQ</a></li>',
    vers: '            <li><a href="#faq">FAQ</a></li>\n            <li><a href="#">Nous contacter</a></li>',
  },
  {
    nom: 'une ancre vise une section supprimée',
    fichier: 'views/index.ejs',
    de: '    <a href="#faq">FAQ</a>\n    <a href="#telecharger"',
    vers: '    <a href="#temoignages">Témoignages</a>\n    <a href="#telecharger"',
  },
  {
    nom: "le site promet de l'IA alors que le modèle est statistique",
    fichier: 'server.js',
    de: "    eyebrow: 'Données du match',",
    vers: "    eyebrow: 'Analyse par IA',",
  },
  {
    nom: "l'annuel se voit attribuer un avantage que le mensuel n'a pas",
    fichier: 'server.js',
    de: "  { label: 'Support prioritaire',                   values: [false, true,  true] },",
    vers: "  { label: 'Support prioritaire',                   values: [false, true,  true] },\n"
        + "  { label: 'Historique complet des performances',    values: [false, false, true] },",
  },
  {
    nom: 'les mentions légales redécrivent un portefeuille de paris',
    fichier: 'views/legal.ejs',
    de: 'PronoWin ne collecte aucune mise et ne tient aucun compte de paris.',
    vers: 'Les dépôts et retraits passent par Orange Money, Moov Money et MTN MoMo.',
  },
];

/**
 * Réécrit `contenu` dans `chemin`, en réessayant.
 *
 * Sous Windows, un antivirus ou un processus qui lit le fichier au même
 * instant fait échouer l'ouverture en écriture avec `EBUSY`, `EPERM` ou
 * `UNKNOWN`. Ce sont des échecs transitoires : quelques essais espacés
 * suffisent. Si rien n'y fait, on le crie fort — le dépôt contient alors un
 * défaut volontaire, et le silence serait le pire des résultats.
 */
function restaurer(chemin, contenu, essais = 12) {
  for (let i = 0; i < essais; i++) {
    try {
      fs.writeFileSync(chemin, contenu);
      return;
    } catch (e) {
      if (i === essais - 1) {
        console.error(`\n  ÉCHEC DE RESTAURATION : ${chemin} (${e.code})`);
        console.error('  Le fichier contient encore le défaut injecté.');
        console.error(`  Restaurez-le : git checkout -- ${chemin}\n`);
        process.exit(2);
      }
      // Attente active courte : `execFileSync` interdit l'asynchrone ici.
      const fin = Date.now() + 120;
      while (Date.now() < fin) { /* patiente */ }
    }
  }
}

let echecs = 0;

for (const inj of INJECTIONS) {
  const avant = fs.readFileSync(inj.fichier);
  const texte = avant.toString('utf8');

  const occurrences = texte.split(inj.de).length - 1;
  if (occurrences !== 1) {
    console.log(`  ANCRE  ${inj.nom}`);
    console.log(`         ${occurrences} occurrence(s) de l'ancre dans ${inj.fichier} — attendu 1`);
    echecs++;
    continue;
  }

  let detecte;
  try {
    fs.writeFileSync(inj.fichier, texte.replace(inj.de, inj.vers), 'utf8');
    try {
      execFileSync('node', ['test_contenu.js'], { stdio: 'pipe' });
      detecte = false;                     // les contrôles ont tous passé
    } catch {
      detecte = true;                      // au moins un contrôle a échoué
    }
  } finally {
    // La restauration doit survivre à tout — y compris à l'échec du test.
    //
    // Elle a déjà lâché une fois : `EUNKNOWN` sur l'ouverture en écriture,
    // sous Windows, pendant qu'un serveur d'aperçu lisait le même fichier. Le
    // banc s'est arrêté sur l'exception et a laissé le défaut injecté dans
    // l'arbre de travail. Un outil qui remet volontairement un bug doit le
    // retirer même quand tout va mal, sinon il devient lui-même la panne.
    restaurer(inj.fichier, avant);
  }

  // Restauration vérifiée à l'octet près : une comparaison de texte masquerait
  // un changement de fin de ligne ou d'encodage.
  if (!avant.equals(fs.readFileSync(inj.fichier))) {
    console.log(`  SOUILLÉ ${inj.fichier} n'a pas été restauré à l'identique`);
    echecs++;
    continue;
  }

  if (detecte) {
    console.log(`  DETECTE ${inj.nom}`);
  } else {
    console.log(`  NON DETECTE ${inj.nom}`);
    console.log(`          → le défaut passe : la garde ne garde rien`);
    echecs++;
  }
}

console.log(`\n${INJECTIONS.length - echecs}/${INJECTIONS.length} injections détectées`);
process.exit(echecs ? 1 : 0);
