const crypto = require('crypto');
const fs = require('fs');

/**
 * Double authentification du panneau : codes TOTP (RFC 6238).
 *
 * Aucun second facteur n'existait : un mot de passe hameçonné ou réutilisé
 * suffisait pour valider des paiements, bannir, publier (constat A1 de
 * l'audit du 24 septembre 2026). Les codes sont ceux des applications
 * d'authentification courantes — Google Authenticator, Microsoft
 * Authenticator, Aegis, 2FAS : HMAC-SHA1, pas de 30 secondes, 6 chiffres.
 *
 * ── Ce qui est conservé ────────────────────────────────────────────────────
 *
 * Le secret de chaque compte est chiffré (AES-256-GCM) avec une clé dérivée du
 * secret du panneau : une copie de `double_auth.json` seule ne permet pas de
 * générer des codes. Les codes de secours ne sont gardés que par leur
 * empreinte, et chacun ne sert qu'une fois.
 *
 * Un code déjà accepté ne l'est pas une seconde fois : le dernier pas de temps
 * utilisé est retenu. Sans cela, un code observé par-dessus l'épaule restait
 * valable le reste de sa fenêtre.
 */
const PAS_S = 30;
const CHIFFRES = 6;
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function base32(tampon) {
  let bits = 0, valeur = 0, sortie = '';
  for (const octet of tampon) {
    valeur = (valeur << 8) | octet; bits += 8;
    while (bits >= 5) { sortie += ALPHABET[(valeur >>> (bits - 5)) & 31]; bits -= 5; }
  }
  if (bits > 0) sortie += ALPHABET[(valeur << (5 - bits)) & 31];
  return sortie;
}

function deBase32(texte) {
  const propre = String(texte).toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bits = 0, valeur = 0;
  const octets = [];
  for (const c of propre) {
    valeur = (valeur << 5) | ALPHABET.indexOf(c); bits += 5;
    if (bits >= 8) { octets.push((valeur >>> (bits - 8)) & 255); bits -= 8; }
  }
  return Buffer.from(octets);
}

/** Un secret neuf, en base 32 — la forme que saisissent les applications. */
function genererSecret() { return base32(crypto.randomBytes(20)); }

/** Le code d'un pas de temps donné. */
function codeAuPas(secret, pas) {
  const compteur = Buffer.alloc(8);
  compteur.writeBigUInt64BE(BigInt(pas));
  const h = crypto.createHmac('sha1', deBase32(secret)).update(compteur).digest();
  const decalage = h[h.length - 1] & 0x0f;
  const nombre = ((h[decalage] & 0x7f) << 24) | (h[decalage + 1] << 16) | (h[decalage + 2] << 8) | h[decalage + 3];
  return String(nombre % 10 ** CHIFFRES).padStart(CHIFFRES, '0');
}

const pasCourant = (maintenant = Date.now()) => Math.floor(maintenant / 1000 / PAS_S);

/**
 * Vérifie un code : pas courant, précédent ou suivant (dérive d'horloge du
 * téléphone), et strictement après [dernierPas]. Rend le pas accepté, ou null.
 */
function verifierTotp(secret, code, dernierPas = -1, maintenant = Date.now()) {
  const saisi = String(code ?? '').replace(/\s+/g, '');
  if (!/^\d{6}$/.test(saisi)) return null;
  const courant = pasCourant(maintenant);
  for (const pas of [courant - 1, courant, courant + 1]) {
    if (pas <= dernierPas) continue;
    const attendu = codeAuPas(secret, pas);
    if (crypto.timingSafeEqual(Buffer.from(attendu), Buffer.from(saisi))) return pas;
  }
  return null;
}

/** L'adresse qu'ouvrent les applications (et que dessine le QR code). */
function uriOtpauth({ secret, compte, emetteur = 'PronoWin Admin' }) {
  const e = encodeURIComponent(emetteur);
  return `otpauth://totp/${e}:${encodeURIComponent(compte)}?secret=${secret}&issuer=${e}&algorithm=SHA1&digits=${CHIFFRES}&period=${PAS_S}`;
}

const empreinteSecours = (code) =>
  crypto.createHash('sha256').update(String(code).toLowerCase().replace(/[^a-z0-9]/g, '')).digest('hex');

/** Huit codes de secours, montrés une fois. */
function genererCodesSecours() {
  return Array.from({ length: 8 }, () => {
    const brut = crypto.randomBytes(5).toString('hex');
    return `${brut.slice(0, 5)}-${brut.slice(5)}`;
  });
}

/**
 * Le magasin des seconds facteurs, clé par compte : `main:<id API>` pour un
 * administrateur principal, `sub:<id>` pour un sous-admin.
 */
function creerMagasin2fa({ fichier, secretPanneau, ecrireJson, maintenant = () => Date.now() }) {
  const cle = crypto.createHash('sha256').update(`${secretPanneau}:double-authentification`).digest();

  const chiffrer = (texte) => {
    const iv = crypto.randomBytes(12);
    const c = crypto.createCipheriv('aes-256-gcm', cle, iv);
    const donnees = Buffer.concat([c.update(texte, 'utf8'), c.final()]);
    return [iv, c.getAuthTag(), donnees].map((b) => b.toString('base64')).join('.');
  };
  const dechiffrer = (enveloppe) => {
    const [iv, tag, donnees] = enveloppe.split('.').map((x) => Buffer.from(x, 'base64'));
    const d = crypto.createDecipheriv('aes-256-gcm', cle, iv);
    d.setAuthTag(tag);
    return Buffer.concat([d.update(donnees), d.final()]).toString('utf8');
  };

  const lire = () => { try { return JSON.parse(fs.readFileSync(fichier, 'utf8')); } catch { return {}; } };
  const ecrire = (tout) => {
    const r = ecrireJson(fichier, tout);
    try { fs.chmodSync(fichier, 0o600); } catch { /* système sans droits POSIX */ }
    return r;
  };

  return {
    estActive(compte) { return !!lire()[compte]; },

    /** Active le second facteur si [code] correspond à [secret]. Rend les codes de secours, ou null. */
    activer(compte, secret, code) {
      const pas = verifierTotp(secret, code, -1, maintenant());
      if (pas === null) return null;
      const secours = genererCodesSecours();
      const tout = lire();
      tout[compte] = {
        secret: chiffrer(secret), dernierPas: pas,
        secours: secours.map(empreinteSecours), activeLe: new Date(maintenant()).toISOString(),
      };
      const r = ecrire(tout);
      return r.ok ? secours : null;
    },

    /**
     * Vérifie un code TOTP, ou un code de secours (qui est alors consommé).
     * Rend `'totp'`, `'secours'`, ou null.
     */
    verifier(compte, code) {
      const tout = lire();
      const e = tout[compte];
      if (!e) return null;
      const pas = verifierTotp(dechiffrer(e.secret), code, e.dernierPas ?? -1, maintenant());
      if (pas !== null) {
        e.dernierPas = pas;
        ecrire(tout);
        return 'totp';
      }
      const empreinte = empreinteSecours(code);
      const i = (e.secours ?? []).indexOf(empreinte);
      if (String(code ?? '').replace(/[^a-z0-9]/gi, '').length === 10 && i >= 0) {
        e.secours.splice(i, 1);
        ecrire(tout);
        return 'secours';
      }
      return null;
    },

    /** Nombre de codes de secours restants. */
    secoursRestants(compte) { return (lire()[compte]?.secours ?? []).length; },

    desactiver(compte) {
      const tout = lire();
      if (!tout[compte]) return false;
      delete tout[compte];
      return ecrire(tout).ok;
    },
  };
}

module.exports = {
  creerMagasin2fa, genererSecret, uriOtpauth, verifierTotp, codeAuPas, pasCourant, base32, deBase32,
};
