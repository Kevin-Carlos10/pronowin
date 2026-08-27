import fs from 'fs';
import path from 'path';
import { nomDevise } from '../utils/devise';

/**
 * Un montant s'affiche avec le nom d'usage de sa devise, jamais son code ISO.
 *
 * Le Bankroll stocke `XOF` — la bonne donnée. Mais ce qui est écrit sur les
 * billets, et ce que les gens disent, c'est « FCFA ». Le mobile l'avait compris
 * et corrigé ses écrans ; les notifications, elles, partaient encore d'ici avec
 * le code brut :
 *
 *     🏆 Pronostic Gagnant !
 *     +2 000 XOF sur Lyon – Fenerbahçe
 *
 * Une notification n'est pas rattrapable : elle est déjà dans la barre du
 * téléphone quand on s'aperçoit qu'elle parle un langage de banque.
 */
describe('nom d\'usage des devises', () => {
  it('traduit les codes connus', () => {
    expect(nomDevise('XOF')).toBe('FCFA');
    expect(nomDevise('XAF')).toBe('FCFA');
    expect(nomDevise('GNF')).toBe('GNF');
    expect(nomDevise('EUR')).toBe('€');
  });

  it('accepte la casse minuscule', () => {
    // La base garantit des majuscules, mais un appelant peut recopier autrement.
    expect(nomDevise('xof')).toBe('FCFA');
  });

  it('rend un code inconnu tel quel', () => {
    // Mieux vaut un sigle qu'un montant sans unité, qui ne veut plus rien dire.
    expect(nomDevise('NGN')).toBe('NGN');
  });

  it('ne rend rien pour une devise absente', () => {
    expect(nomDevise(null)).toBe('');
    expect(nomDevise(undefined)).toBe('');
    expect(nomDevise('')).toBe('');
  });
});

describe('aucune notification n\'expédie un code ISO', () => {
  const src = fs.readFileSync(
    path.join(__dirname, '..', 'services', 'bankroll.service.ts'), 'utf8');

  it('les corps de notification passent par `nomDevise`', () => {
    // On isole les lignes `body:` : c'est le texte qui atterrit sur l'écran
    // verrouillé du téléphone.
    const corps = src.split('\n').filter(l => l.trimStart().startsWith('body:'));
    expect(corps.length).toBeGreaterThanOrEqual(3);

    const fautifs = corps.filter(l =>
      /\$\{\s*currency\s*\}/.test(l) && !l.includes('nomDevise('));

    expect(fautifs).toEqual([]);
  });
});

describe('les deux tables de devises ne divergent pas', () => {
  /**
   * Cette table existe aussi côté mobile, en Dart. Deux copies dans deux
   * langages, c'est précisément ce qui s'éloigne — et personne ne s'en aperçoit
   * avant qu'un montant s'affiche autrement sur l'écran et dans la
   * notification qui l'annonce.
   *
   * Ce contrôle lit les deux fichiers. Si le mobile n'est pas là (dépôt partiel
   * en intégration continue), il le dit au lieu de passer au vert sans avoir
   * rien comparé.
   */
  const cheminDart = path.join(
    __dirname, '..', '..', '..', 'mobile_new', 'lib', 'shared', 'utils', 'devise.dart');

  /** Extrait les paires `'CODE': 'nom'` d'une table, quel que soit le langage. */
  function paires(source: string, debutTable: string): Record<string, string> {
    const i = source.indexOf(debutTable);
    if (i === -1) throw new Error(`table introuvable : ${debutTable}`);
    const fin = source.indexOf('};', i);
    const bloc = source.slice(i, fin === -1 ? source.length : fin);

    const out: Record<string, string> = {};
    for (const m of bloc.matchAll(/'?([A-Z]{3})'?\s*:\s*'([^']*)'/g)) {
      out[m[1]] = m[2];
    }
    return out;
  }

  it('le mobile est bien présent', () => {
    expect(fs.existsSync(cheminDart)).toBe(true);
  });

  it('même ensemble de codes, mêmes noms', () => {
    const ts = paires(
      fs.readFileSync(path.join(__dirname, '..', 'utils', 'devise.ts'), 'utf8'),
      'const NOMS');
    const dart = paires(
      fs.readFileSync(cheminDart, 'utf8'), 'const Map<String, String> _nomsDevises');

    expect(Object.keys(ts).length).toBeGreaterThanOrEqual(4);
    expect(dart).toEqual(ts);
  });
});

describe('les montants de parrainage voyagent avec leur devise', () => {
  /// Le fichier **sans ses commentaires**.
  ///
  /// La première version lisait la source brute, et échouait sur la
  /// documentation que je venais d'écrire : elle cite `currency: 'XOF'` pour
  /// expliquer le défaut corrigé. Un contrôle qui se valide sur sa propre prose
  /// ne contrôle rien.
  const src = fs.readFileSync(
    path.join(__dirname, '..', 'services', 'referral.service.ts'), 'utf8')
    .split('\n')
    .filter(l => {
      const t = l.trimStart();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

  it('la charge utile publie une devise', () => {
    // Sans elle, l'ecran doit deviner — et deviner deux fois donne deux
    // reponses : « 0 FCFA » pour le solde, « 500 F » pour la commission, a
    // quatre centimetres d'ecart sur le meme ecran.
    expect(src).toMatch(/currency:\s*REFERRAL_CURRENCY/);
  });

  it('la devise du versement et celle annoncee sont la meme constante', () => {
    // Le virement Mobile Money etait cree avec `'XOF'` ecrit en dur, a un
    // autre endroit du fichier. Annoncer une devise et en verser une autre est
    // le genre d'ecart que personne ne voit avant un litige.
    expect(src).toContain('export const REFERRAL_CURRENCY');
    expect(src).not.toMatch(/currency:\s*'XOF'/);

    // On compte les **affectations**, pas les mentions du nom. La ligne de
    // declaration le contient deux fois (`export const X = process.env.X`) :
    // un seuil sur le nom restait donc atteint alors que la charge utile avait
    // disparu. Une injection l'a montre.
    const affectations = src.match(/currency:\s*REFERRAL_CURRENCY/g) ?? [];
    // Charge utile annoncee + transaction reellement creee.
    expect(affectations.length).toBeGreaterThanOrEqual(2);
  });
});
