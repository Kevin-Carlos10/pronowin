/**
 * Une preuve de paiement prévient l'administrateur dès son arrivée.
 *
 * Le client lit « validation sous 30 minutes ouvrables ». La seule alerte
 * partait après 6 heures d'attente, et le premier paiement Mobile Money
 * d'octobre a attendu 3 h sans que personne soit prévenu (3 octobre 2026).
 */
let preuve: any = null;
const envois: Array<{ sujet: string; corps: string }> = [];

jest.mock('../lib/prisma', () => ({
  prisma: {
    subscriptionProof: {
      findUnique: jest.fn(async () => preuve),
    },
  },
}));

jest.mock('../services/email.service', () => ({
  envoyerAlerteAdmin: jest.fn(async (sujet: string, corps: string) => {
    envois.push({ sujet, corps });
    return true;
  }),
}));

import fs from 'fs';
import path from 'path';
import { alerterNouvellePreuve } from '../services/subscription.service';
import { codeSeul } from './aides/code_seul';

beforeEach(() => { envois.length = 0; });

const base = {
  id: 'p1', createdAt: new Date('2026-10-03T14:47:00Z'),
  user: { pseudo: 'RASBOUOFFICIEL', phoneNumber: '+22674604270', email: null },
};

it('paiement direct : formule, montant, numéro d\'envoi et lien vers la file', async () => {
  preuve = { ...base, type: 'payment_screenshot', planId: 'premium_monthly', amount: 6000, senderPhone: '+22674604270' };

  expect(await alerterNouvellePreuve('p1')).toBe(true);
  expect(envois).toHaveLength(1);
  const { sujet, corps } = envois[0];
  expect(sujet).toBe('[PronoWin] Paiement à valider — Premium mensuel, RASBOUOFFICIEL');
  expect(corps).toMatch(/Montant déclaré : 6\s000 FCFA/);
  expect(corps).toContain("Numéro d'envoi : +22674604270");
  expect(corps).toContain('Délai annoncé au client : 30 minutes ouvrables.');
  expect(corps).toContain('https://pronowin.space/admin/abonnements');
});

it('compte partenaire : la plateforme, pas de montant', async () => {
  preuve = { ...base, type: 'xbet_account_screenshot', planId: null, amount: null, senderPhone: null, platform: '1xbet' };

  await alerterNouvellePreuve('p1');
  expect(envois[0].sujet).toBe('[PronoWin] Compte partenaire à vérifier — RASBOUOFFICIEL');
  expect(envois[0].corps).toContain('Plateforme partenaire : 1xbet');
  expect(envois[0].corps).not.toContain('Montant');
});

it('un numéro anonymisé n\'est pas recopié', async () => {
  preuve = { ...base, type: 'payment_screenshot', planId: 'premium_annual', amount: 54000, senderPhone: null,
    user: { pseudo: 'deleted_1', phoneNumber: '+00000000000_deleted_1', email: null } };

  await alerterNouvellePreuve('p1');
  expect(envois[0].corps).not.toContain('deleted_1)');
  expect(envois[0].sujet).toContain('Premium annuel');
});

it('preuve introuvable : rien n\'est envoyé, rien ne lève', async () => {
  preuve = null;
  expect(await alerterNouvellePreuve('absente')).toBe(false);
  expect(envois).toHaveLength(0);
});

it('la soumission déclenche l\'alerte sans l\'attendre', () => {
  // Un e-mail lent ou en échec ne doit ni retarder ni faire échouer une
  // preuve déjà enregistrée : appel sans `await`, erreur journalisée.
  // Sans les commentaires : ils citent l'appel pour l'expliquer.
  const source = codeSeul(fs.readFileSync(path.join(__dirname, '../services/subscription.service.ts'), 'utf8'));
  const apres = source.slice(source.indexOf('prisma.subscriptionProof.create('));
  expect(apres).toMatch(/\n\s+alerterNouvellePreuve\(proof\.id\)\.catch\(/);
  expect(apres).not.toMatch(/await alerterNouvellePreuve/);
});
