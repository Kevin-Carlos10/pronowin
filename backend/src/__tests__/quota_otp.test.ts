import express from 'express';
import fs from 'fs';
import jwt from 'jsonwebtoken';
import path from 'path';

import {
  decisionEnvoiOtp,
  OTP_ENVOIS_MAX,
  OTP_FENETRE_MS,
  QuotaOtpDepasse,
} from '../utils/quota_otp';

/**
 * Le chemin d'envoi d'un code n'avait aucun quota.
 *
 * Deux défauts superposés, chacun invisible à cause de l'autre :
 *
 *  - `otpLim` était branché sur `/auth/send-otp` et pas sur
 *    `/auth/send-email-otp`, alors qu'un commentaire, juste au-dessus du
 *    branchement, affirmait le contraire ;
 *  - `_checkOtpBrute` était bien appelé à l'envoi, mais son compteur n'est
 *    incrémenté qu'à la **vérification** d'un code faux. Demander cent codes
 *    ne faisait donc monter aucun compteur.
 *
 * Et chaque envoi invalide le précédent. Marteler cette route pour l'adresse
 * de quelqu'un d'autre lui envoie cent courriels, les facture, et surtout
 * l'empêche de se connecter : son code est périmé avant qu'il l'ait tapé.
 */
describe('quota d\'envoi des codes', () => {
  const maintenant = new Date('2026-09-15T12:00:00Z');
  const ilYa = (minutes: number) =>
    new Date(maintenant.getTime() - minutes * 60000);

  it('laisse passer les premiers envois', () => {
    expect(decisionEnvoiOtp([], maintenant).autorise).toBe(true);
    expect(decisionEnvoiOtp([ilYa(1)], maintenant).autorise).toBe(true);
    expect(decisionEnvoiOtp([ilYa(1), ilYa(2)], maintenant).autorise).toBe(true);
  });

  it('refuse au-delà du quota', () => {
    const envois = [ilYa(1), ilYa(2), ilYa(3)];
    expect(envois.length).toBe(OTP_ENVOIS_MAX);

    const d = decisionEnvoiOtp(envois, maintenant);
    expect(d.autorise).toBe(false);
    // Le plus ancien des trois sort de la fenêtre dans sept minutes.
    expect(d.attendreMinutes).toBe(7);
  });

  it('ignore ce qui est sorti de la fenêtre', () => {
    // Contrepartie : un quota qui compterait tout l'historique bloquerait
    // définitivement une adresse après trois demandes, un jour quelconque.
    const vieux = [ilYa(60), ilYa(61), ilYa(62)];
    expect(decisionEnvoiOtp(vieux, maintenant).autorise).toBe(true);

    const limite = [ilYa(9), ilYa(11), ilYa(12)];
    expect(decisionEnvoiOtp(limite, maintenant).autorise).toBe(true);
  });

  it('n\'annonce jamais « réessayez dans 0 minute »', () => {
    // Une seconde avant la réouverture, arrondir vers le bas inviterait à
    // réessayer tout de suite, pour rien.
    const presque = [
      new Date(maintenant.getTime() - OTP_FENETRE_MS + 1000),
      ilYa(1), ilYa(2),
    ];
    const d = decisionEnvoiOtp(presque, maintenant);
    expect(d.autorise).toBe(false);
    expect(d.attendreMinutes).toBeGreaterThanOrEqual(1);
  });

  it('le refus porte son code HTTP', () => {
    // Sans lui, le contrôleur rendait 500 pour toute erreur d'envoi : un quota
    // atteint se présentait comme une panne du serveur.
    const e = new QuotaOtpDepasse(7);
    expect(e.statut).toBe(429);
    expect(e.message).toContain('7 minutes');
    expect(new QuotaOtpDepasse(1).message).toContain('1 minute.');
  });
});

/**
 * La clé de limitation ne se déduit plus d'un jeton non vérifié.
 *
 * Elle était calculée avec `jwt.decode`, qui lit un jeton sans contrôler qu'il
 * vient de nous. Fabriquer un jeton non signé portant un `userId` au hasard
 * donnait un compteur neuf à chaque requête, depuis la même adresse.
 */
describe('clé de limitation', () => {
  const SECRET = 'secret-de-banc';
  const source = fs.readFileSync(
    path.join(__dirname, '..', 'index.ts'), 'utf8');

  /** Rejoue la règle du générateur, telle qu'elle est écrite dans index.ts. */
  function cle(entete: string | undefined, ip = '10.0.0.1'): string {
    if (entete?.startsWith('Bearer ')) {
      try {
        const token = entete.split(' ')[1];
        const verifie = jwt.verify(token, SECRET) as { userId?: string };
        if (verifie?.userId) return `user:${verifie.userId}`;
      } catch (_) { /* jeton absent, expiré ou forgé → on limite par IP */ }
    }
    return ip;
  }

  it('un jeton forgé ne donne pas de compteur neuf', () => {
    // `alg: none` : le jeton se décode parfaitement, et ne prouve rien.
    const forge = jwt.sign({ userId: 'invente' }, '', { algorithm: 'none' });
    expect(cle(`Bearer ${forge}`)).toBe('10.0.0.1');

    // Signé avec un autre secret : même conclusion.
    const autre = jwt.sign({ userId: 'invente' }, 'pas-le-bon-secret');
    expect(cle(`Bearer ${autre}`)).toBe('10.0.0.1');
  });

  it('un jeton valide garde son compteur d\'un bout à l\'autre', () => {
    // Contrepartie : un générateur qui rendrait toujours l'IP ferait passer le
    // contrôle précédent, et perdrait ce que la clé par utilisateur apporte —
    // un abonné mobile qui change de relais garde sa limite.
    const vrai = jwt.sign({ userId: 'u-42' }, SECRET);
    expect(cle(`Bearer ${vrai}`, '10.0.0.1')).toBe('user:u-42');
    expect(cle(`Bearer ${vrai}`, '10.0.0.2')).toBe('user:u-42');
  });

  it('sans jeton, on limite par adresse', () => {
    expect(cle(undefined)).toBe('10.0.0.1');
    expect(cle('Bearer')).toBe('10.0.0.1');
  });

  it('le générateur réel vérifie bien la signature', () => {
    // Les trois contrôles ci-dessus rejouent la règle ; celui-ci vérifie que
    // c'est bien celle qu'on emploie. Sans lui, `index.ts` pourrait revenir à
    // `jwt.decode` sans qu'aucun ne bronche.
    const generateur = source.slice(
      source.indexOf('const keyGenerator'),
      source.indexOf('const globalLim'));

    // Sans ses commentaires : ils nomment `jwt.decode` pour expliquer le
    // défaut, et un contrôle qui se valide sur sa propre prose ne contrôle
    // rien.
    const codeSeul = generateur
      .split('\n')
      .filter((l) => !l.trimStart().startsWith('//'))
      .join('\n');

    expect(codeSeul).toContain('jwt.verify');
    expect(codeSeul).not.toContain('jwt.decode');
  });
});

/**
 * Les limiteurs sont branchés là où ils doivent l'être.
 *
 * Contrôle de source, et il faut le dire : il n'envoie aucune requête. Il
 * attrape un branchement oublié — ce qui est exactement ce qui s'est produit —
 * pas une limite mal réglée.
 */
describe('branchement des limiteurs', () => {
  const source = fs.readFileSync(
    path.join(__dirname, '..', 'index.ts'), 'utf8');

  it.each([
    ['/auth/send-otp',       'otpLim'],
    ['/auth/send-email-otp', 'otpLim'],
    ['/auth/verify-email-otp', 'authLim'],
    ['/admin/login',         'authLim'],
  ])('%s est protégé par %s', (route, limiteur) => {
    const ligne = source
      .split('\n')
      .find((l) => l.includes(`${route}\``) && l.includes('app.use'));
    expect(ligne).toBeDefined();
    expect(ligne).toContain(limiteur);
  });

  it('express est bien la forme attendue', () => {
    // Contrepartie : si le fichier changeait de forme, les contrôles ci-dessus
    // ne trouveraient plus rien et passeraient pour de mauvaises raisons.
    expect(typeof express).toBe('function');
    expect(source).toContain('app.use(globalLim);');
  });
});
