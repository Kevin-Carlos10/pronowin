import * as fs from 'fs';
import * as path from 'path';

import { estVerrouille } from '../services/verrou_pronostic';

/**
 * Le contenu payant ne quitte pas le serveur sans passer par `estVerrouille`.
 *
 * Le paywall est une règle unique — `verrou_pronostic.ts` — et elle était
 * appliquée sur certains endpoints seulement. Trois surfaces la contournaient
 * le même jour :
 *
 *   - la notification « nouveau pronostic publié », diffusée au topic global,
 *     mettait `predictionLabel` dans son corps quel que soit `isPremium`. Un
 *     utilisateur gratuit lisait le pronostic VIP dans son fil, sans ouvrir
 *     l'application — et le préfixe « 👑 [VIP] » lui annonçait la valeur de ce
 *     qu'il obtenait pour rien ;
 *
 *   - `GET /favorites` renvoyait `prediction_label`, `confidence_score`,
 *     `analyst_note` et `ai_probability` pour n'importe quel match mis en
 *     favori, en signalant `is_premium: true` à côté. Sa route ne porte que
 *     `authMiddleware` : il suffisait de mettre un match VIP en favori et de
 *     lire la réponse HTTP.
 *
 * Ni l'une ni l'autre n'était rattrapable côté client : le serveur livrait le
 * contenu.
 *
 * Une troisième surface — l'onglet « Pour Toi » — a d'abord été comptée parmi
 * elles à tort. Sa route porte `premiumMiddleware`, donc un non-abonné reçoit
 * un 403 et jamais la charge utile. La verrouiller « par prudence » aurait
 * renvoyé des `null` que le modèle Dart ne sait pas lire, c'est-à-dire échangé
 * une fuite inexistante contre un plantage réel. Elle figure dans les
 * exceptions ci-dessous, avec ce que devrait faire quiconque ouvrirait la
 * route aux comptes gratuits.
 *
 * Ce contrôle est textuel — il vérifie que chaque endroit où l'API expose
 * `prediction_label` le conditionne, ou figure dans la liste des exceptions
 * ci-dessous, chacune justifiée. Ajouter une exception est un acte délibéré,
 * ce qui est précisément le but.
 */

const RACINE = path.resolve(__dirname, '..');

/**
 * Les endroits où exposer la décision est légitime.
 *
 * La clé est le chemin relatif ; la valeur, les lignes autorisées telles
 * qu'elles apparaissent (espaces de début retirés), avec leur raison.
 */
const EXCEPTIONS: Record<string, { ligne: string; raison: string }[]> = {
  'controllers/bankroll.controller.ts': [
    {
      ligne:  'prediction_label: b.pronostic.predictionLabel,',
      raison: 'paris que l\'utilisateur a lui-même posés — il connaît déjà la '
            + 'décision, la lui cacher rendrait son propre historique illisible',
    },
  ],
  'controllers/pronostics.controller.ts': [
    {
      ligne:  'prediction_label:  p.predictionLabel,',
      raison: 'formulaire d\'administration (pronostic_form.ejs), derrière '
            + 'l\'authentification admin',
    },
  ],
  'services/personalized_ai.service.ts': [
    {
      ligne:  'prediction_label: p.predictionLabel,',
      raison: 'l\'onglet « Pour Toi » est protégé au niveau de la route — '
            + '`/for-you` passe par authMiddleware ET premiumMiddleware, donc '
            + 'un non-abonné reçoit un 403 et jamais cette charge utile. '
            + 'Conditionner ici en plus renverrait des `null` que '
            + '`ForYouProno.fromJson` ne sait pas lire : le client planterait. '
            + 'SI LA ROUTE S\'OUVRE AUX GRATUITS, il faudra verrouiller ici '
            + '*et* rendre le modèle Dart tolérant aux nuls, dans le même '
            + 'changement.',
    },
  ],
  'services/pronostics.service.ts': [
    {
      ligne:  'prediction_label:  prono.predictionLabel,',
      raison: 'liste d\'administration — l\'admin doit voir ce qu\'il publie',
    },
    {
      ligne:  'prediction_label: p.predictionLabel,',
      raison: '_formatDailyProno : le pronostic gratuit du jour, dont '
            + '`isPremium` vaut false par construction (setDailyFreePronostic)',
    },
  ],
};

function fichiersSources(depuis: string, acc: string[] = []): string[] {
  for (const e of fs.readdirSync(depuis, { withFileTypes: true })) {
    if (e.name === '__tests__' || e.name === 'node_modules') continue;
    const complet = path.join(depuis, e.name);
    if (e.isDirectory()) fichiersSources(complet, acc);
    else if (e.name.endsWith('.ts')) acc.push(complet);
  }
  return acc;
}

describe('verrou du contenu payant', () => {
  it('la règle refuse un premium à venir pour un non-abonné', () => {
    expect(estVerrouille(true, 'SCHEDULED', false)).toBe(true);
  });

  it('la règle laisse passer dans les trois cas prévus', () => {
    // Sans ces trois-là, une règle qui verrouillerait tout passerait le test
    // précédent sans rien servir.
    expect(estVerrouille(false, 'SCHEDULED', false)).toBe(false); // gratuit
    expect(estVerrouille(true,  'SCHEDULED', true)).toBe(false);  // abonné
    expect(estVerrouille(true,  'FINISHED',  false)).toBe(false); // match joué
  });

  it('toute exposition de prediction_label est conditionnée', () => {
    const fautes: string[] = [];

    for (const fichier of fichiersSources(RACINE)) {
      const relatif = path.relative(RACINE, fichier).replace(/\\/g, '/');
      const permises = EXCEPTIONS[relatif] ?? [];

      fs.readFileSync(fichier, 'utf8').split('\n').forEach((ligne, i) => {
        if (!ligne.includes('prediction_label:')) return;
        const nue = ligne.trim();
        // Les commentaires citent le champ pour expliquer le correctif.
        if (nue.startsWith('//') || nue.startsWith('*')) return;
        // Insensible à la casse : une des gardes existantes nomme sa variable
        // `mLocked`. Chercher « locked » en minuscules l'accusait — un
        // contrôle qui signale du code correct finit désarmé, pas corrigé.
        if (/locked/i.test(nue)) return;
        if (permises.some((p) => p.ligne === nue)) return;

        fautes.push(`${relatif}:${i + 1} ${nue}`);
      });
    }

    expect(fautes).toEqual([]);
  });

  it('les routes rattachées à un match s\'ouvrent après le coup de sifflet', () => {
    // `estVerrouille` déverrouille un match joué, mais deux routes
    // protégeaient leur contenu par `premiumMiddleware`, où la notion de match
    // terminé n'existe pas. Sur une fiche de match joué, l'application
    // affichait le score, les cotes et le pronostic, puis « Débriefing du
    // modèle » sous un cadenas : elle ouvrait tout sauf ce qui expliquait le
    // reste.
    //
    // `/for-you` garde `premiumMiddleware` : elle n'est rattachée à aucun
    // match, donc « terminé » n'y veut rien dire. Publier et voter aussi —
    // participer à la discussion reste un avantage d'abonné, indépendamment
    // du calendrier. Seule la *lecture* d'un contenu de match s'ouvre.
    const routes = (nom: string) =>
      fs.readFileSync(path.join(RACINE, 'routes', nom), 'utf8');

    const pronos = routes('pronostics.routes.ts');
    expect(pronos).toMatch(/ai-analyze[^\n]*premiumSaufMatchTermine/);
    expect(pronos).toMatch(/for-you[^\n]*premiumMiddleware/);

    const comments = routes('comments.routes.ts');
    expect(comments).toMatch(/r\.get[^\n]*premiumSaufMatchTermine/);
    expect(comments).toMatch(/r\.post\('\/:pronosticId',[^\n]*premiumMiddleware/);
  });

  it('la notification de publication ne révèle pas un pronostic VIP', () => {
    const source = fs.readFileSync(
      path.join(RACINE, 'services', 'notification.service.ts'), 'utf8');

    const bloc = source.slice(source.indexOf('notifyPronosticPublished'));
    const corps = bloc.slice(0, bloc.indexOf('sendToTopic'));

    // Le corps ne doit employer `predictionLabel` que sous condition
    // d'`isPremium` — la variable intermédiaire porte le choix.
    expect(corps).toContain('params.isPremium ?');
    expect(corps.includes('const affiche')).toBe(true);

    // Et la décision ne doit plus apparaître dans une chaîne inconditionnelle.
    const gabarits = corps.match(/`[^`]*\$\{params\.predictionLabel\}[^`]*`/g);
    expect(gabarits).toBeNull();
  });
});
