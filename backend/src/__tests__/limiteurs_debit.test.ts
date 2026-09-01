import fs from 'fs';
import path from 'path';

/**
 * Les limiteurs de débit doivent distinguer les utilisateurs.
 *
 * Le serveur tourne derrière nginx, qui transmet l'adresse réelle du client
 * dans `X-Forwarded-For`. Express ne l'exploite que si on le lui dit :
 * `app.set('trust proxy', …)`. Ce réglage manquait.
 *
 * Conséquence, mesurable dans les journaux de production
 * (`ERR_ERL_UNEXPECTED_X_FORWARDED_FOR`, à chaque requête) : `req.ip` valait
 * l'adresse du proxy — identique pour tout le monde. Or c'est la clé de tous
 * les limiteurs, et le plus strict autorise trois demandes d'OTP par dix
 * minutes. Trois personnes demandaient un code, la quatrième était bloquée :
 * pas la quatrième depuis la même adresse, la quatrième de toute l'application.
 *
 * Un déni de service permanent sur l'inscription, servi par la protection
 * censée l'empêcher.
 */
const SRC = fs.readFileSync(
  path.join(__dirname, '..', 'index.ts'), 'utf8');

/** Le fichier sans ses commentaires : ils décrivent le défaut, ils ne le portent pas. */
const code = SRC
  .split('\n')
  .filter(l => {
    const t = l.trimStart();
    return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
  })
  .join('\n');

describe('limiteurs de débit — une clé par utilisateur, pas par proxy', () => {
  it('express fait confiance au proxy', () => {
    expect(/app\.set\(\s*['"]trust proxy['"]/.test(code)).toBe(true);
  });

  it('la confiance est bornée à un seul maillon', () => {
    // `true` ferait confiance à toute la chaîne : n'importe qui pourrait alors
    // usurper une adresse via son propre en-tête et contourner les limiteurs.
    // Le remède serait pire que le mal.
    const m = /app\.set\(\s*['"]trust proxy['"]\s*,\s*([^)]+)\)/.exec(code);
    expect(m).not.toBeNull();

    const valeur = m![1].trim();
    expect(valeur).not.toBe('true');
    expect(Number.isInteger(Number(valeur))).toBe(true);
    expect(Number(valeur)).toBeGreaterThanOrEqual(1);
  });

  it('le réglage précède la déclaration des limiteurs', () => {
    // Posé après, il n'aurait aucun effet sur eux.
    const posTrust = code.indexOf('trust proxy');
    const posLimit = code.indexOf('rateLimit(');

    expect(posTrust).toBeGreaterThan(-1);
    expect(posLimit).toBeGreaterThan(-1);
    expect(posTrust).toBeLessThan(posLimit);
  });

  it('les limiteurs sensibles existent toujours', () => {
    // Le correctif porte sur la clé, pas sur les quotas : les retirer ou les
    // desserrer serait une autre décision, qui n'a pas été prise ici.
    for (const nom of ['globalLim', 'otpLim', 'authLim', 'payLim', 'publicLim']) {
      expect(code).toContain(`const ${nom} = rateLimit(`);
    }
  });

  it('la clé retombe sur l\'adresse quand il n\'y a pas de jeton', () => {
    // C'est précisément ce chemin que le proxy rendait inopérant.
    expect(code).toContain("return req.ip ?? 'unknown';");
  });
});
