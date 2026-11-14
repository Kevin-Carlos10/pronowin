import fs from 'fs';
import path from 'path';

/**
 * Aucune notification ne porte d'emoji.
 *
 * Dix-neuf titres en portaient un, répartis dans sept services :
 * « ✅ Résultat : Pronostic gagnant ! », « 🎉 Premium activé ! »,
 * « 💰 Parrainage récompensé ! », « ⚠️ Compte suspendu »… Sur l'écran de
 * verrouillage d'un téléphone, à côté des notifications d'une banque ou d'un
 * opérateur, la coche verte fait amateur — et sur une application liée aux
 * paris, le confetti fait pire : il célèbre l'issue d'une mise.
 *
 * ── Pourquoi un contrôle, et pas seulement une correction ──────────────────
 *
 * Parce que ces titres sont écrits à sept endroits différents, par sept
 * services qui ne se lisent pas entre eux. La règle ne tiendra pas d'elle-même
 * : le prochain service qui enverra une notification recopiera le style du
 * voisin, et personne ne le verra passer en relecture.
 *
 * Le panneau d'administration disait d'ailleurs exactement l'inverse à
 * l'opérateur — « Un emoji en tête de titre booste l'ouverture » — et ses cinq
 * modèles rapides en pré-remplissaient un. Il a sa propre vérification.
 *
 * Les traces serveur (`console.log`) gardent les leurs : elles ne s'affichent
 * sur l'écran de personne.
 */
describe('titres de notification', () => {
  const services = path.join(__dirname, '..', 'services');

  // Plages Unicode des pictogrammes et symboles décoratifs. Les lettres
  // accentuées, les guillemets français et les tirets cadratins n'y sont pas :
  // ce n'est pas la ponctuation qu'on chasse.
  const EMOJI =
    /[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2300}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]/u;

  /** Les lignes qui composent un titre ou un corps de notification. */
  function lignesDeNotification(fichier: string): { n: number; texte: string }[] {
    const brut = fs.readFileSync(path.join(services, fichier), 'utf8');
    return brut
      .split('\n')
      .map((texte, i) => ({ n: i + 1, texte }))
      .filter(({ texte }) => {
        const nu = texte.trim();
        if (nu.startsWith('//') || nu.startsWith('*')) return false;
        // Une trace serveur n'est lue que dans un terminal.
        if (nu.includes('console.')) return false;
        return /\b(title|body)\s*:/.test(texte);
      });
  }

  const fichiers = fs
    .readdirSync(services)
    .filter((f) => f.endsWith('.service.ts'));

  it('les services étudiés existent bien', () => {
    // Sans ce point, un dossier renommé ferait passer le contrôle suivant sur
    // une liste vide — vert, et sans avoir rien regardé.
    expect(fichiers.length).toBeGreaterThan(5);
    expect(fichiers).toContain('notification.service.ts');
  });

  it.each(fichiers)('%s : aucun emoji dans un titre ni un corps', (fichier) => {
    const fautifs = lignesDeNotification(fichier).filter(({ texte }) =>
      EMOJI.test(texte),
    );

    expect(fautifs.map((l) => `${fichier}:${l.n} ${l.texte.trim()}`)).toEqual([]);
  });

  it('le motif reconnaît bien un emoji', () => {
    // Contrepartie indispensable : une expression qui ne reconnaîtrait rien
    // ferait passer les sept fichiers sans avoir rien détecté.
    expect(EMOJI.test("title: '✅ Résultat'")).toBe(true);
    expect(EMOJI.test("title: '🎉 Premium activé !'")).toBe(true);
    expect(EMOJI.test("title: '⚠️ Compte suspendu'")).toBe(true);

    // Et qu'il ne confond pas la ponctuation française avec un pictogramme.
    expect(EMOJI.test("title: 'Résultat : Pronostic gagnant !'")).toBe(false);
    expect(EMOJI.test("title: `Commission L${n} reçue !`")).toBe(false);
    expect(EMOJI.test("body: 'Score final — 2-1 · Prono : 1N2'")).toBe(false);
  });
});
