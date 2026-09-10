/**
 * Banc d'injection du canal de distribution.
 *
 * `test/canal_store_test.dart` a passé au vert pendant que le build store
 * affichait « 0 / 2000 FCFA avant de pouvoir retirer ». Un contrôle vert sur du
 * code correct ne prouve rien : celui-ci remet chaque défaut, exige l'échec,
 * restaure, et vérifie la restauration à l'octet près.
 *
 * Une injection « NON DETECTEE » est un échec du banc, pas un succès du code.
 *
 *     node tool/injections_canal.js
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const RACINE = path.join(__dirname, '..');
const COMPTE = 'lib/features/compte/presentation/pages/compte_page.dart';
const PARRAIN = 'lib/features/parrainage/presentation/pages/parrainage_page.dart';
const RETRAIT = 'lib/features/parrainage/presentation/pages/retrait_parrainage_page.dart';
const LEGAL = 'lib/features/parametres/presentation/pages/legal_page.dart';
const BANKROLL = 'lib/features/bankroll/presentation/pages/bankroll_page.dart';

const INJECTIONS = [
  {
    // Le conseil de discipline designait un guichet de paris, sur un ecran
    // que rien ne conditionne au canal. Il partait tel quel dans le paquet
    // soumis a Google.
    nom: 'un conseil de bankroll renomme un guichet de paris',
    fichier: BANKROLL,
    de: /'Respecte toujours la mise calculée\. Ne la dépasse jamais\.',/,
    vers: "'Respecte toujours la mise calculée. Ne mise jamais plus sur le bookmaker.',",
  },
  {
    // Le defaut exact observe sur l'emulateur : le seuil de retrait en francs
    // s'affiche dans un binaire compile avec STORE_BUILD=true.
    //
    // L'ancre est une expression reguliere : ecrite a la main, l'indentation
    // se compte mal, et une ancre qui ne mord pas ressemble a un succes.
    nom: "le seuil de retrait en francs revient dans l'onglet Compte",
    fichier: COMPTE,
    de: /estStore\s*\n\s*\? \(peutAgir/,
    vers: '(peutAgir',
  },
  {
    // La garde appliquee en mutilant le booleen : le bouton disparait, la
    // phrase de repli — celle du seuil — s'affiche.
    nom: 'l’unite de l’encart redevient une monnaie',
    fichier: PARRAIN,
    de: /child: Text\(estStore \? 'jours Premium' : 'FCFA',/,
    vers: "child: Text('FCFA',",
  },
  {
    // Le premier verrou : il fermait le versement *et* la conversion, en
    // annoncant une conversion qui n'existait plus nulle part.
    nom: 'le canal store redevient un cul-de-sac pour les recompenses',
    fichier: RETRAIT,
    de: /body: _buildCreditTab\(earnings, withdrawState\),/,
    vers: "body: const Center(child: Text('Indisponible sur cette version.')),",
  },
  {
    // L'article des CGU qui decrit l'offre d'activation par code partenaire.
    // L'interface la masquait ; le texte legal la detaillait encore.
    nom: "les CGU redecrivent l'offre d'activation partenaire",
    fichier: LEGAL,
    de: /if \(!estStore\)\s*\n\s*LegalSection\(null, 'Activation par code 1xBet',/,
    vers: "LegalSection(null, 'Activation par code 1xBet',",
  },
  {
    // Le taux recopie a la main, qui vivait en trois exemplaires.
    nom: 'le taux de conversion est recalcule sur place',
    fichier: RETRAIT,
    de: /final premiumDays = joursPremiumPour\(earnings\);/,
    vers: 'final premiumDays = ((earnings / 5000) * 30).floor();',
  },
];

function restaurer(chemin, contenu, essais = 12) {
  for (let i = 0; i < essais; i++) {
    try {
      fs.writeFileSync(chemin, contenu);
      return;
    } catch (e) {
      if (i === essais - 1) {
        console.error(`\n  ÉCHEC DE RESTAURATION : ${chemin} (${e.code})`);
        console.error(`  Restaurez-le : git checkout -- ${chemin}\n`);
        process.exit(2);
      }
      const fin = Date.now() + 120;
      while (Date.now() < fin) { /* patiente */ }
    }
  }
}

let echecs = 0;

for (const inj of INJECTIONS) {
  const chemin = path.join(RACINE, inj.fichier);
  const avant  = fs.readFileSync(chemin);
  const texte  = avant.toString('utf8');

  const global = new RegExp(inj.de.source, 'g');
  const occurrences = (texte.match(global) || []).length;
  if (occurrences !== 1) {
    console.log(`  ANCRE   ${inj.nom}`);
    console.log(`          ${occurrences} occurrence(s) dans ${inj.fichier} — attendu 1`);
    echecs++;
    continue;
  }

  let detecte;
  try {
    fs.writeFileSync(chemin, texte.replace(inj.de, inj.vers), 'utf8');
    try {
      execFileSync('flutter', ['test', 'test/canal_store_test.dart'],
        { cwd: RACINE, stdio: 'pipe', shell: true });
      detecte = false;
    } catch {
      detecte = true;
    }
  } finally {
    restaurer(chemin, avant);
  }

  if (!avant.equals(fs.readFileSync(chemin))) {
    console.log(`  SOUILLÉ ${inj.fichier} n'a pas été restauré à l'identique`);
    echecs++;
    continue;
  }

  if (detecte) {
    console.log(`  DETECTE ${inj.nom}`);
  } else {
    console.log(`  NON DETECTE ${inj.nom}`);
    console.log('          → le défaut passe : la garde ne garde rien');
    echecs++;
  }
}

console.log(`\n${INJECTIONS.length - echecs}/${INJECTIONS.length} injections détectées`);
process.exit(echecs ? 1 : 0);
