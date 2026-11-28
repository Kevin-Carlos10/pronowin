import crypto from 'crypto';
import axios from 'axios';
import jwt from 'jsonwebtoken';

import { journal } from '../utils/logger';

/**
 * « Se connecter avec Apple ».
 *
 * La règle 4.8 de l'App Store l'exige de toute app qui propose une connexion
 * tierce comme Google : une option où l'on peut masquer son adresse.
 *
 * Le jeton d'identité reçu du téléphone est vérifié ici, comme celui de
 * Google : signature par une clé publiée par Apple, émetteur, audience (notre
 * identifiant de lot), expiration, et le nonce — sans lui, un jeton intercepté
 * pourrait être rejoué. Rien de ce que le client affirme d'autre n'est cru.
 */

const EMETTEUR = 'https://appleid.apple.com';
const URL_CLES = 'https://appleid.apple.com/auth/keys';

/** Les identifiants de lot acceptés comme audience. */
function audiences(): string[] {
  return (process.env.APPLE_CLIENT_IDS ?? 'com.pronowin.app')
    .split(',').map((s) => s.trim()).filter(Boolean);
}

// ─── Clés publiques d'Apple ──────────────────────────────────────────────────

type Jwk = { kid: string; kty: string; n: string; e: string; alg?: string };
let cles: { lues: number; parKid: Map<string, crypto.KeyObject> } | null = null;
const DUREE_CLES_MS = 60 * 60 * 1000;

/** Pour les bancs : d'où viennent les clés, et l'oubli du cache. */
export const _banc = {
  lireCles: async (): Promise<Jwk[]> => (await axios.get(URL_CLES, { timeout: 5000 })).data.keys,
  oublier: () => { cles = null; },
};

async function clePublique(kid: string): Promise<crypto.KeyObject> {
  const perimees = !cles || Date.now() - cles.lues > DUREE_CLES_MS;
  // Une clé inconnue fait relire la liste : Apple en publie de nouvelles.
  if (perimees || !cles!.parKid.has(kid)) {
    const liste = await _banc.lireCles();
    cles = {
      lues: Date.now(),
      parKid: new Map(liste.map((k) => [k.kid, crypto.createPublicKey({ key: k as any, format: 'jwk' })])),
    };
  }
  const cle = cles!.parKid.get(kid);
  if (!cle) throw new Error('Jeton Apple invalide.');
  return cle;
}

/** L'empreinte que l'app a transmise à Apple : SHA-256 du nonce brut, en hexadécimal. */
export function empreinteNonce(nonceBrut: string): string {
  return crypto.createHash('sha256').update(nonceBrut).digest('hex');
}

export interface IdentiteApple {
  sub: string;
  email: string | null;
  /** L'adresse est un relais @privaterelay.appleid.com : la personne l'a masquée. */
  relais: boolean;
}

/** Vérifie le jeton d'identité et en rend ce qui fait foi. */
export async function verifierJetonApple(jeton: string, nonceBrut: string): Promise<IdentiteApple> {
  const entete = jwt.decode(jeton, { complete: true })?.header;
  if (!entete?.kid || entete.alg !== 'RS256') throw new Error('Jeton Apple invalide.');

  let charge: jwt.JwtPayload;
  try {
    charge = jwt.verify(jeton, await clePublique(entete.kid), {
      algorithms: ['RS256'],
      issuer:     EMETTEUR,
      audience:   audiences() as [string, ...string[]],
    }) as jwt.JwtPayload;
  } catch {
    throw new Error('Jeton Apple invalide.');
  }

  if (!nonceBrut || charge.nonce !== empreinteNonce(nonceBrut)) {
    throw new Error('Jeton Apple invalide.');
  }
  if (typeof charge.sub !== 'string' || !charge.sub) throw new Error('Jeton Apple invalide.');

  // Apple écrit parfois ces booléens en texte.
  const verifiee = charge.email_verified === true || charge.email_verified === 'true';
  const email = typeof charge.email === 'string' && verifiee ? charge.email.toLowerCase() : null;
  const relais = charge.is_private_email === true || charge.is_private_email === 'true';
  return { sub: charge.sub, email, relais };
}

// ─── Révocation à la suppression du compte ───────────────────────────────────
//
// Apple demande qu'une app qui propose sa connexion révoque l'autorisation
// quand la personne supprime son compte. Il faut pour cela un jeton de
// rafraîchissement, obtenu en échangeant le code d'autorisation à la
// connexion, et une clé « Sign in with Apple » (developer.apple.com → Keys).
// Sans cette clé, la connexion fonctionne ; seule la révocation est sautée.

function configurationCle(): { equipe: string; kid: string; cle: string } | null {
  const equipe = process.env.APPLE_TEAM_ID;
  const kid = process.env.APPLE_SIWA_KEY_ID;
  const cle = process.env.APPLE_SIWA_PRIVATE_KEY?.replace(/\\n/g, '\n');
  return equipe && kid && cle ? { equipe, kid, cle } : null;
}

/** Le « secret client » qu'Apple attend : un JWT ES256 signé par notre clé. */
function secretClient(conf: { equipe: string; kid: string; cle: string }): string {
  return jwt.sign({}, conf.cle, {
    algorithm: 'ES256', keyid: conf.kid, issuer: conf.equipe,
    audience: EMETTEUR, subject: audiences()[0], expiresIn: '5m',
  });
}

/** Clé de chiffrement du jeton stocké, dérivée d'un secret déjà présent. */
function cleChiffrement(): Buffer {
  const secret = process.env.JWT_REFRESH_SECRET;
  if (!secret) throw new Error('JWT_REFRESH_SECRET absent');
  return Buffer.from(crypto.hkdfSync('sha256', secret, 'pronowin', 'apple-refresh-token', 32));
}

export function chiffrer(clair: string): string {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', cleChiffrement(), iv);
  const corps = Buffer.concat([c.update(clair, 'utf8'), c.final()]);
  return [iv, c.getAuthTag(), corps].map((b) => b.toString('base64')).join('.');
}

export function dechiffrer(chiffre: string): string {
  const [iv, tag, corps] = chiffre.split('.').map((p) => Buffer.from(p, 'base64'));
  const d = crypto.createDecipheriv('aes-256-gcm', cleChiffrement(), iv);
  d.setAuthTag(tag);
  return Buffer.concat([d.update(corps), d.final()]).toString('utf8');
}

/** Pour les bancs : l'appel HTTP vers Apple. */
export const _http = {
  poster: async (url: string, champs: Record<string, string>) =>
    (await axios.post(url, new URLSearchParams(champs).toString(), {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, timeout: 8000,
    })).data,
};

/**
 * Échange le code d'autorisation contre un jeton de rafraîchissement,
 * chiffré, prêt à être gardé. `null` : pas de clé configurée, ou échec — la
 * connexion ne doit jamais en dépendre.
 */
export async function obtenirJetonRevocable(code: string | undefined): Promise<string | null> {
  const conf = configurationCle();
  if (!conf || !code) return null;
  try {
    const r = await _http.poster(`${EMETTEUR}/auth/token`, {
      client_id: audiences()[0], client_secret: secretClient(conf),
      code, grant_type: 'authorization_code',
    });
    return typeof r?.refresh_token === 'string' ? chiffrer(r.refresh_token) : null;
  } catch (e: any) {
    journal.warn('[Apple] Échange du code impossible', { message: e?.message });
    return null;
  }
}

/** Révoque l'autorisation Apple d'un compte supprimé. Ne lève jamais. */
export async function revoquer(jetonChiffre: string | null | undefined): Promise<boolean> {
  const conf = configurationCle();
  if (!conf || !jetonChiffre) return false;
  try {
    await _http.poster(`${EMETTEUR}/auth/revoke`, {
      client_id: audiences()[0], client_secret: secretClient(conf),
      token: dechiffrer(jetonChiffre), token_type_hint: 'refresh_token',
    });
    return true;
  } catch (e: any) {
    journal.warn('[Apple] Révocation impossible', { message: e?.message });
    return false;
  }
}
