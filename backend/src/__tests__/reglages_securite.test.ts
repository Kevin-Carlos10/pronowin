import fs from 'fs';
import path from 'path';

const SRC = path.join(__dirname, '..');

/** Tous les fichiers TypeScript du serveur, hors tests. */
function sources(): string[] {
  const out: string[] = [];
  (function parcourir(d: string) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) { if (e.name !== '__tests__') parcourir(p); }
      else if (e.name.endsWith('.ts')) out.push(p);
    }
  })(SRC);
  return out;
}

/**
 * Une comparaison contre une variable d'environnement doit avoir un côté
 * littéral.
 *
 * `secret !== process.env.ADMIN_SETUP_SECRET` paraît juste et ne l'est pas :
 * l'en-tête absent vaut `undefined`, la variable non définie aussi, et
 * `undefined !== undefined` est **faux**. Le garde laisse alors passer, et il
 * le fait précisément dans la configuration la moins surveillée — celle où
 * personne n'a rien renseigné.
 *
 * `process.env.NODE_ENV === 'production'` ne souffre pas du problème : le côté
 * droit est une constante, donc une variable absente échoue toujours.
 *
 * La règle porte donc sur la forme, pas sur l'intention : comparer à un
 * littéral, ou lier la variable à un local et vérifier sa présence d'abord.
 */
describe('réglages de sécurité — les gardes échouent fermés', () => {
  it('aucune comparaison ne met une variable d\'environnement à droite', () => {
    // `X === process.env.Y` : le motif dangereux.
    const dangereux = /(?:!==|===|!=|==)\s*process\.env\.\w+/g;
    // `process.env.Y === 'literal'` : la forme sûre, à ne pas confondre.
    const sur = /process\.env\.\w+\s*(?:!==|===|!=|==)\s*['"`]/;

    const fautifs: string[] = [];
    for (const f of sources()) {
      const lignes = fs.readFileSync(f, 'utf8').split('\n');
      lignes.forEach((l, i) => {
        const t = l.trimStart();
        if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) return;
        if (!dangereux.test(l)) { dangereux.lastIndex = 0; return; }
        dangereux.lastIndex = 0;
        if (sur.test(l)) return;
        fautifs.push(`${path.relative(SRC, f).replace(/\\/g, '/')}:${i + 1}  ${t}`);
      });
    }

    expect(fautifs).toEqual([]);
  });

  it('l\'analyseur lit bien quelque chose', () => {
    // Sans ce contrôle, un parcours qui ne trouve aucun fichier rendrait le
    // test précédent vert par vacuité.
    const fichiers = sources();
    expect(fichiers.length).toBeGreaterThanOrEqual(40);
    expect(fichiers.some(f => f.endsWith('index.ts'))).toBe(true);

    const total = fichiers
      .map(f => fs.readFileSync(f, 'utf8'))
      .join('\n');
    expect(total).toContain('process.env.NODE_ENV');
  });

  it('un réglage explicite n\'est pas écrasé par un repli', () => {
    // `IAP_ACCEPT_SANDBOX=false` était annulé par `|| NODE_ENV !== production`.
    // Un `.env` qui dit « non » se comportait comme s'il disait « oui ».
    const src = fs.readFileSync(path.join(SRC, 'services', 'iap.service.ts'), 'utf8');

    expect(src).toContain("process.env.IAP_ACCEPT_SANDBOX !== undefined");
    expect(src).not.toMatch(
      /IAP_ACCEPT_SANDBOX === 'true'\s*\n?\s*\|\|\s*process\.env\.NODE_ENV/);
  });

  it('le secret d\'amorçage est documenté dans .env.example', () => {
    // Il n'y figurait pas. Le README demande `cp .env.example .env` : la
    // variable manquante restait donc non définie, ce qui est exactement la
    // condition qui ouvrait la faille.
    const exemple = fs.readFileSync(
      path.join(SRC, '..', '.env.example'), 'utf8');

    expect(exemple).toMatch(/^ADMIN_SETUP_SECRET=/m);
  });
});
