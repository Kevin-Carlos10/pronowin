import fs from 'fs';
import path from 'path';

/**
 * L'identifiant du compte partenaire se relève à la validation.
 *
 * ── Ce qui change, et pourquoi ────────────────────────────────────────────
 *
 * Le parcours « code promo » demandait à l'utilisateur de saisir l'ID de son
 * compte, puis de joindre une capture où **cet identifiant est visible**. Deux
 * fois le même travail, sur le dernier écran avant la conversion — là où
 * chaque champ supplémentaire fait renoncer.
 *
 * Le champ a donc été retiré de l'application. L'identifiant est relevé par
 * l'administrateur, qui regarde la capture de toute façon.
 *
 * ── Le piège de ce genre de déplacement ───────────────────────────────────
 *
 * Déplacer un travail sans l'exiger, c'est le supprimer. L'administrateur
 * l'aurait sauté une fois, par commodité, puis toujours — et l'identifiant
 * aurait disparu des dossiers sans que rien ne le signale : l'approbation
 * aurait réussi, l'abonné aurait reçu son mois, et le champ serait resté vide.
 *
 * Il sert à retrouver un abonné dans l'historique, et à prouver qu'un compte a
 * bien été ouvert avec notre code le jour où le partenaire conteste une
 * commission. Approuver, c'est attester de ce compte-là.
 *
 * ── Exigé à l'approbation, pas au refus ───────────────────────────────────
 *
 * Un refus n'atteste de rien. Une capture illisible doit pouvoir être refusée
 * sans inventer un numéro — c'est justement le cas où l'identifiant manque.
 *
 * Contrôle sur la source : ce qui doit être interdit, c'est qu'une future
 * version rende l'identifiant à nouveau facultatif à l'approbation, ou le
 * réclame de nouveau à la soumission.
 */
const SERVICE = path.join(__dirname, '..', 'services', 'subscription.service.ts');

/** Le fichier sans ses commentaires : ils expliquent le défaut, ils ne le
 *  corrigent pas, et un contrôle qui se valide sur sa propre prose ne contrôle
 *  rien. */
function codeSeul(): string {
  return fs.readFileSync(SERVICE, 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .filter((l) => !l.trimStart().startsWith('//'))
    .join('\n');
}

describe('identifiant du compte partenaire', () => {
  it("n'est plus réclamé à la soumission", () => {
    // L'application ne l'envoie plus. Le réclamer ici referait échouer toute
    // soumission, et l'écran afficherait « ID de compte requis » à propos d'un
    // champ qui n'existe plus.
    expect(codeSeul()).not.toMatch(/ID de compte requis/);
  });

  it('reste accepté quand une ancienne version l\'envoie encore', () => {
    // Les installations en circulation continuent de le poster. Le rejeter
    // casserait leur parcours pour un champ devenu facultatif.
    expect(codeSeul()).toMatch(/xbetId/);
  });

  it('est exigé pour approuver', () => {
    const code = codeSeul();
    const debut = code.indexOf('async reviewProof');
    expect(debut).toBeGreaterThan(-1);
    const corps = code.slice(debut, debut + 3000);

    expect(corps).toMatch(/approved\s*&&/);
    expect(corps).toMatch(/requis pour approuver/);
  });

  it("n'est pas exigé pour refuser", () => {
    // La garde porte sur `approved`, pas sur la revue en général : sinon une
    // capture illisible — le cas même où l'identifiant manque — deviendrait
    // impossible à refuser.
    const code = codeSeul();
    const debut = code.indexOf('async reviewProof');
    const corps = code.slice(debut, debut + 3000);

    const garde = corps.slice(corps.indexOf('requis pour approuver') - 400,
                              corps.indexOf('requis pour approuver'));
    expect(garde).toMatch(/if\s*\(\s*approved/);
  });

  it('est recopié sur le compte de l\'abonné', () => {
    // Relevé mais non enregistré, il serait perdu à la fermeture de l'écran —
    // et la recherche de l'administration, qui porte sur `user.xbetId`, ne le
    // trouverait jamais.
    const code = codeSeul();
    const debut = code.indexOf('async reviewProof');
    const corps = code.slice(debut, debut + 3000);

    expect(corps).toMatch(/prisma\.user\.update/);
    expect(corps).toMatch(/prisma\.subscriptionProof\.update/);
  });
});
