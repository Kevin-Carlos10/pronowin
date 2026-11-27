/**
 * Ce que la bankroll a engagé, et son plafond (constat B2).
 *
 * Sorti de `bankroll.service.ts` le 27 novembre 2026 : les combinés et les
 * couvertures enregistrées engagent aussi le solde. La réinitialisation, le
 * plafond et le bilan doivent les compter tous les trois, sinon une mise
 * serait rendue deux fois (voir `resetBankroll`).
 */
import { prisma } from '../lib/prisma';
import { nomDevise } from '../utils/devise';
import { ErreurMetier } from '../utils/erreurs';
import { lireConfig } from './app_config.service';
import type { Tx } from './bankroll_journal';

/**
 * La part de la bankroll que les mises en cours peuvent engager ensemble, ou
 * `null` : pas de plafond.
 *
 * Chaque mise respecte le barème, mais rien ne limitait leur somme : cinq
 * pronostics notés 5 le même soir engageaient 25 % du solde. Le seuil est une
 * décision produit, réglée dans le panneau (BANKROLL_PLAFOND_EXPOSITION) ;
 * vide, il n'y a pas de plafond.
 */
export async function plafondExposition(): Promise<number | null> {
  const { valeurs } = await lireConfig();
  const brut = (valeurs as Record<string, string>).BANKROLL_PLAFOND_EXPOSITION ?? '';
  const pct = Number(brut);
  return brut.trim() !== '' && Number.isFinite(pct) && pct > 0 && pct <= 100 ? pct / 100 : null;
}

export class PlafondExposition extends ErreurMetier {
  constructor(plafond: number, engage: number, capital: number, devise: string) {
    const fmt = (n: number) => `${Math.round(n).toLocaleString('fr-FR')} ${nomDevise(devise)}`;
    super(
      `Tes paris en cours engagent déjà ${fmt(engage)} sur ${fmt(capital)}. ` +
      `Le plafond est de ${Math.round(plafond * 100)} % de ta bankroll : ` +
      'attends le résultat d\'un pari en cours avant d\'en ajouter un.',
      409, 'EXPOSURE_CAP');
    this.name = 'PlafondExposition';
  }
}

/**
 * Les mises non tranchées : simples, combinés, couvertures enregistrées.
 * Toutes déjà sorties du solde disponible.
 */
export async function engageEnCours(bankrollId: string, client: Tx | typeof prisma = prisma) {
  const [paris, combines, couvertures] = await Promise.all([
    client.bankrollBet.aggregate({ where: { bankrollId, result: null }, _sum: { stakedAmount: true } }),
    client.bankrollCombine.aggregate({ where: { bankrollId, result: null }, _sum: { stakedAmount: true } }),
    client.bankrollCouverture.aggregate({ where: { bankrollId, result: null }, _sum: { mise: true } }),
  ]);
  const p = paris._sum.stakedAmount ?? 0;
  const c = combines._sum.stakedAmount ?? 0;
  const h = couvertures._sum.mise ?? 0;
  return { paris: p, combines: c, couvertures: h, total: p + c + h };
}

/**
 * Le plafond laisse-t-il passer une nouvelle mise de [mise] ? Lève
 * `PlafondExposition` sinon. Rapporté à tout ce que la bankroll contient : le
 * disponible plus ce qui est déjà engagé — rapporté au seul disponible, le
 * plafond se resserrerait à chaque mise.
 */
export async function verifierPlafond(
  bankroll: { id: string; currentBalance: number; currency: string }, mise: number,
): Promise<void> {
  const plafond = await plafondExposition();
  if (plafond === null) return;
  const { total: engage } = await engageEnCours(bankroll.id);
  const capital = bankroll.currentBalance + engage;
  if (engage + mise > plafond * capital + 1e-9) {
    throw new PlafondExposition(plafond, engage, capital, bankroll.currency);
  }
}
