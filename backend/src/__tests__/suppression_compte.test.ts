import fs from 'fs';
import path from 'path';

/**
 * Ce que « Supprimer le compte » doit réellement effacer.
 *
 * L'écran mobile promet « toutes tes données [...] définitivement supprimées »
 * et la page légale annonce que les données identifiantes sont supprimées ou
 * anonymisées. Ces deux phrases engagent, et rien ne les reliait au code.
 *
 * Le risque n'est pas la version d'aujourd'hui — elle est correcte. C'est
 * celle de dans six mois : on ajoute `firstName`, `xbetId` ou un identifiant
 * de portefeuille au modèle `User`, on oublie l'anonymisation, et personne ne
 * le voit. Un compte « supprimé » garde alors un nom, ou continue de recevoir
 * des notifications parce que son jeton push est resté en base.
 *
 * La liste des champs est donc **lue dans le schéma**, pas recopiée ici :
 * toute colonne nouvelle doit être classée explicitement, sinon ce test tombe.
 */
const SCHEMA = fs.readFileSync(
  path.join(__dirname, '..', '..', 'prisma', 'schema.prisma'), 'utf8');
const CTRL = fs.readFileSync(
  path.join(__dirname, '..', 'controllers', 'profile.controller.ts'), 'utf8');

const SCALAIRES = new Set([
  'String', 'Int', 'Float', 'Boolean', 'DateTime', 'Json', 'BigInt', 'Decimal', 'Bytes',
]);

/** Noms d'énumérations déclarées dans le schéma — ce sont aussi des colonnes. */
const ENUMS = new Set(
  [...SCHEMA.matchAll(/^enum\s+(\w+)\s*\{/gm)].map(m => m[1]));

/**
 * Colonnes scalaires du modèle, relations exclues.
 *
 * Les relations (`Comment[]`, `UserBankroll?`) ne portent pas de donnée
 * personnelle par elles-mêmes : elles pointent vers d'autres tables, dont la
 * suppression relève d'une autre décision que celle-ci.
 */
function colonnes(modele: string): string[] {
  const debut = SCHEMA.indexOf(`model ${modele} {`);
  if (debut === -1) throw new Error(`modèle ${modele} introuvable`);
  const fin = SCHEMA.indexOf('\n}', debut);
  if (fin === -1) throw new Error(`fin du modèle ${modele} introuvable`);

  return SCHEMA.slice(debut, fin)
    .split('\n')
    .slice(1)
    .map(l => l.trim())
    .filter(l => l && !l.startsWith('//') && !l.startsWith('@@'))
    .map(l => l.split(/\s+/))
    .filter(([, type]) => {
      if (!type) return false;
      const nu = type.replace(/[?[\]]/g, '');
      return (SCALAIRES.has(nu) || ENUMS.has(nu)) && !type.endsWith('[]');
    })
    .map(([nom]) => nom);
}

/** Données personnelles : la suppression doit les effacer ou les remplacer. */
const EFFACER = new Set([
  'phoneNumber',   // joignabilité directe
  'email',         // joignabilité directe
  'passwordHash',  // matière d'authentification d'un compte supprimé
  'pseudo',        // affiché publiquement sous chaque commentaire
  'avatarUrl',     // photo
  'firstName',
  'lastName',
  'birthDate',
  'xbetId',        // rattache la personne à un compte bookmaker
  'fcmToken',      // sans quoi un compte supprimé continue de recevoir des push
]);

/** Champs que la suppression doit positionner, sans être des données personnelles. */
const MARQUER = new Set(['isActive', 'deletedAt']);

/**
 * Conservations assumées. Chaque entrée est une décision, pas un oubli :
 * l'identifiant technique porte l'historique des paris, le code de parrainage
 * rattache les filleuls, l'abonnement relève d'une obligation comptable, et
 * l'acceptation des conditions est une preuve qu'on ne détruit pas.
 */
const CONSERVER = new Set([
  'id', 'countryCode',
  'subscriptionPlan', 'subscriptionExpiresAt',
  'referralCode', 'referredBy', 'referralEarnings',
  'createdAt', 'updatedAt', 'lastLoginAt', 'lastSeenAt',
  'notificationPrefs',
  'acceptedTermsAt', 'termsVersion',
  'phoneVerified', 'emailVerified',
  'streakDays', 'streakLastDate', 'xpTotal',
]);

/** Le corps de `deleteAccount`, borné au handler suivant. */
function corpsDeleteAccount(): string {
  const debut = CTRL.indexOf('export const deleteAccount');
  expect(debut).toBeGreaterThan(-1);
  const suivant = CTRL.indexOf('export const ', debut + 1);
  return CTRL.slice(debut, suivant === -1 ? CTRL.length : suivant);
}

describe('suppression de compte — ce que l\'écran promet', () => {
  it('chaque colonne de User est classée explicitement', () => {
    const inconnues = colonnes('User').filter(
      c => !EFFACER.has(c) && !MARQUER.has(c) && !CONSERVER.has(c));

    expect(inconnues).toEqual([]);
  });

  it('aucun champ n\'est classé deux fois', () => {
    for (const c of colonnes('User')) {
      const dans = [EFFACER, MARQUER, CONSERVER].filter(s => s.has(c)).length;
      expect(dans).toBeLessThanOrEqual(1);
    }
  });

  it('les listes ne mentionnent pas de champ disparu du schéma', () => {
    // Sans ce contrôle, renommer une colonne laisserait une garde qui protège
    // un champ qui n'existe plus, tout en paraissant verte.
    const reelles = new Set(colonnes('User'));
    const fantomes = [...EFFACER, ...MARQUER, ...CONSERVER].filter(c => !reelles.has(c));

    expect(fantomes).toEqual([]);
  });

  it('toute donnée personnelle est effacée par la suppression', () => {
    const corps = corpsDeleteAccount();

    for (const champ of EFFACER) {
      expect(corps).toMatch(new RegExp(`\\b${champ}:\\s*\\S`));
    }
  });

  it('la suppression est marquée, pas seulement subie', () => {
    const corps = corpsDeleteAccount();

    for (const champ of MARQUER) {
      expect(corps).toMatch(new RegExp(`\\b${champ}:\\s*\\S`));
    }
    // `deletedAt` sans date serait une marque vide.
    expect(corps).toMatch(/deletedAt:\s*new Date\(\)/);
    expect(corps).toMatch(/isActive:\s*false/);
  });

  it('les jetons de session sont révoqués', () => {
    // Anonymiser la ligne sans invalider les jetons laisse l'application
    // ouverte sur l'appareil : le compte est « supprimé » et continue de
    // répondre aux appels authentifiés jusqu'à expiration.
    const corps = corpsDeleteAccount();

    expect(corps).toContain('refreshToken');
    expect(corps).toMatch(/used:\s*true/);
  });

  it('il n\'existe qu\'une seule implémentation de la suppression', () => {
    // `ProfileService` portait un second `deleteAccount`, plus ancien et
    // incomplet — il laissait nom, prénom, date de naissance, xbetId et le
    // jeton push en base. Personne ne l'appelait ; son nom était exactement
    // celui vers lequel on tend la main.
    const services = path.join(__dirname, '..', 'services');
    const doublons = fs.readdirSync(services)
      .filter(f => f.endsWith('.ts'))
      .filter(f => /async\s+deleteAccount\s*\(/.test(
        fs.readFileSync(path.join(services, f), 'utf8')));

    expect(doublons).toEqual([]);
  });
});
