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
    de: '      if (p && typeof p.price_fcfa === \'number\' && p.price_fcfa > 0) par[p.id] = p.price_fcfa;',
    vers: '      if (false) par[p.id] = p.price_fcfa;',
  },
  {
    nom: 'un tarif de repli est inventé quand l\'API se tait',
    fichier: 'server.js',
    de: "    price: f.id === 'free' ? '0' : (tarifs[f.id] ? fcfa(tarifs[f.id]) : null),",
    vers: "    price: f.id === 'free' ? '0' : (tarifs[f.id] ? fcfa(tarifs[f.id]) : '8 000'),",
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
    nom: 'les mentions légales redécrivent un portefeuille de paris',
    fichier: 'views/legal.ejs',
    de: 'PronoWin ne collecte aucune mise et ne tient aucun compte de paris.',
    vers: 'Les dépôts et retraits passent par Orange Money, Moov Money et MTN MoMo.',
  },
];

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

  fs.writeFileSync(inj.fichier, texte.replace(inj.de, inj.vers), 'utf8');

  let detecte;
  try {
    execFileSync('node', ['test_contenu.js'], { stdio: 'pipe' });
    detecte = false;                       // les contrôles ont tous passé
  } catch {
    detecte = true;                        // au moins un contrôle a échoué
  }

  // Restauration à l'octet près : c'est la seule preuve que le banc n'a rien
  // laissé derrière lui. Une comparaison de texte masquerait un changement de
  // fin de ligne ou d'encodage.
  fs.writeFileSync(inj.fichier, avant);
  const apres = fs.readFileSync(inj.fichier);
  if (!avant.equals(apres)) {
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
