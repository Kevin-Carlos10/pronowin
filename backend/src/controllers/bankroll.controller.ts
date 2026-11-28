import { Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { AdminRequest } from '../middleware/admin.middleware';
import { prisma } from '../lib/prisma';
import * as svc from '../services/bankroll.service';
import { partSelonConfiance } from '../services/mise_suggeree';
import { ErreurMetier, repondreErreur } from '../utils/erreurs';
import { couvertureCombinePourAbonne, couverturePourAbonne } from '../services/couverture.service';
import * as combines from '../services/combines.service';
import { couverturePourApi, enregistrerCouverture as enregistrer } from '../services/couvertures_enregistrees.service';
import { pourcentageConfiance, pourcentageDepuisNiveau } from '../utils/confiance';
import { bilanSemaine, courbeResultats, resultatsRegles } from '../services/bankroll_historique';

export const getBankroll = async (req: AuthRequest, res: Response) => {
  try {
    const bankroll = await svc.getBankroll(req.userId!);
    if (!bankroll) { res.json(null); return; }

    // Le bilan porte sur tout l'historique, la liste sur ce qu'on affiche.
    //
    // L'écran calculait ses compteurs, son taux et sa courbe depuis les
    // cinquante paris renvoyés, et les présentait comme le bilan complet. Au
    // cinquante-et-unième, les chiffres devenaient faux en silence.
    const resume = await svc.resumeParis(bankroll.id);
    const plafond = await svc.plafondExposition();
    const listeCombines = await combines.lireCombines(bankroll.id);
    // La courbe et la semaine aussi, sur tout l'historique, combinés et
    // couvertures compris (27 novembre 2026).
    const regles = await resultatsRegles(bankroll.id);

    res.json({
      id:             bankroll.id,
      total_budget:   bankroll.totalBudget,
      current_balance: bankroll.currentBalance,
      currency:       bankroll.currency,
      resume,
      // Part de la bankroll que les paris en cours peuvent engager ensemble
      // (B2) ; null : pas de plafond.
      plafond_exposition: plafond,
      // Combien de lignes accompagnent ce bilan — pour que l'écran puisse dire
      // « 50 des 128 paris » au lieu de laisser croire qu'il les montre tous.
      paris_affiches: bankroll.bets.length,
      bets: bankroll.bets.map(b => ({
        id:              b.id,
        pronostic_id:    b.pronosticId,
        staked_amount:   b.stakedAmount,
        suggested_amount: b.suggestedAmount,
        odds_used:       b.oddsUsed,
        potential_gain:  b.potentialGain,
        result:          b.result,
        profit:          b.profit,
        settled_at:      b.settledAt,
        created_at:      b.createdAt,
        // M1 : la mise réelle se confirme au résultat, pendant quelques jours.
        mise_confirmee:  b.miseConfirmeeLe !== null,
        a_confirmer:     svc.miseAConfirmer(b),
        // La mise sur l'inverse, si l'abonné l'a enregistrée (27 novembre 2026).
        couverture_enregistree: couverturePourApi(b.couvertureEnregistree),
        match: {
          id:          b.pronostic.match.id,
          home_team:   b.pronostic.match.homeTeam,
          away_team:   b.pronostic.match.awayTeam,
          match_date:  b.pronostic.match.matchDate,
          league:      b.pronostic.match.league,
          // Écussons, statut et score : la fiche d'un pari montre les équipes
          // comme le reste de l'application, et dit si le match est en cours.
          home_team_logo: b.pronostic.match.homeTeamLogo,
          away_team_logo: b.pronostic.match.awayTeamLogo,
          status:         statutPublic(b.pronostic.match.status),
          home_score:     b.pronostic.match.homeScore,
          away_score:     b.pronostic.match.awayScore,
        },
        prediction_label: b.pronostic.predictionLabel,
        prediction_label_en: b.pronostic.predictionLabelEn ?? null,
        confidence_score: b.pronostic.confidenceScore,
        confidence_pct: pourcentageConfiance(b.pronostic),
      })),
      // Les coupons combinés (27 novembre 2026), du plus récent au plus ancien.
      combines: listeCombines.map(combinePourApi),
      // Le résultat net cumulé, mise après mise, et les sept derniers jours.
      courbe:  courbeResultats(regles),
      semaine: bilanSemaine(regles),
    });
  } catch (e: any) { repondreErreur(res, e); }
};

/** Un combiné au format de l'application. */
function combinePourApi(c: Awaited<ReturnType<typeof combines.lireCombines>>[number]) {
  return {
    id:             c.id,
    staked_amount:  c.stakedAmount,
    odds_used:      c.oddsUsed,
    potential_gain: c.potentialGain,
    note_retenue:   c.noteRetenue,
    result:         c.result,
    retour:         c.retour,
    profit:         c.profit,
    settled_at:     c.settledAt,
    created_at:     c.createdAt,
    couverture_enregistree: couverturePourApi(c.couvertureEnregistree),
    selections: c.selections.map(l => ({
      id:           l.id,
      ordre:        l.ordre,
      pronostic_id: l.pronosticId,
      libre:        l.pronosticId === null,
      libre_match:  l.libreMatch,
      libre_selection: l.libreSelection,
      cote:         l.cote,
      note:         l.note,
      result:       l.annulee ? 'PUSH' : l.result,
      annulee:      l.annulee,
      prediction_label:    l.pronostic?.predictionLabel ?? null,
      prediction_label_en: l.pronostic?.predictionLabelEn ?? null,
      match: l.pronostic?.match ? {
        id:          l.pronostic.match.id,
        home_team:   l.pronostic.match.homeTeam,
        away_team:   l.pronostic.match.awayTeam,
        match_date:  l.pronostic.match.matchDate,
        league:      l.pronostic.match.league,
        home_team_logo: l.pronostic.match.homeTeamLogo,
        away_team_logo: l.pronostic.match.awayTeamLogo,
        status:      statutPublic(l.pronostic.match.status),
        home_score:  l.pronostic.match.homeScore,
        away_score:  l.pronostic.match.awayScore,
      } : null,
    })),
  };
}

/** POST /bankroll/couvertures — « J'ai couvert » (27 novembre 2026). */
export const enregistrerCouverture = async (req: AuthRequest, res: Response) => {
  try {
    const h = await enregistrer(req.userId!, req.body ?? {});
    res.status(201).json({ couverture: couverturePourApi(h), current_balance: h.current_balance });
  } catch (e: any) { repondreErreur(res, e); }
};

/** GET /bankroll/combines/:id/couverture — la couverture de la dernière sélection. */
export const getCouvertureCombine = async (req: AuthRequest, res: Response) => {
  try {
    const r = await couvertureCombinePourAbonne(req.userId!, req.params.id);
    if (!r) { res.status(404).json({ message: 'Combiné introuvable.' }); return; }
    res.json(r);
  } catch (e: any) { repondreErreur(res, e); }
};

/** POST /bankroll/combines/apercu — { selections } : la mise, la cote, le gain. */
export const apercuCombine = async (req: AuthRequest, res: Response) => {
  try { res.json(await combines.apercuCombine(req.userId!, req.body?.selections)); }
  catch (e: any) { repondreErreur(res, e); }
};

/** POST /bankroll/combines — { selections, staked_amount }. */
export const placerCombine = async (req: AuthRequest, res: Response) => {
  try {
    const c = await combines.placerCombine(req.userId!, req.body?.selections, Number(req.body?.staked_amount));
    res.status(201).json({ id: c.id, current_balance: c.current_balance });
  } catch (e: any) { repondreErreur(res, e); }
};

/** POST /bankroll/combines/:id/selections/:selectionId/resultat — { result } : une sélection libre. */
export const reglerSelectionLibre = async (req: AuthRequest, res: Response) => {
  try {
    res.json(await combines.reglerSelectionLibre(
      req.userId!, req.params.id, req.params.selectionId, req.body?.result ?? null));
  } catch (e: any) { repondreErreur(res, e); }
};

export const setBudget = async (req: AuthRequest, res: Response) => {
  try {
    const { total_budget, currency } = req.body ?? {};
    const budget = Number(total_budget);
    if (!Number.isFinite(budget) || budget <= 0 || budget > 1e12) {
      res.status(400).json({ message: 'Budget invalide.' }); return;
    }
    // Sans devise dans la demande, la bankroll garde la sienne : le défaut
    // « XOF » d'avant ré-étiquetait une bankroll en euros.
    const b = await svc.setBudget(req.userId!, budget, typeof currency === 'string' ? currency : undefined);
    res.json({ total_budget: b.totalBudget, current_balance: b.currentBalance, currency: b.currency });
  } catch (e: any) { repondreErreur(res, e, 400); }
};

export const resetBankroll = async (req: AuthRequest, res: Response) => {
  try {
    const b = await svc.resetBankroll(req.userId!);
    res.json({ current_balance: b.currentBalance });
  } catch (e: any) { repondreErreur(res, e, 400); }
};

/**
 * GET /bankroll/couverture/:pronosticId — combien miser sur l'évènement
 * inverse de sa sélection, aux cotes du moment (couverture.service.ts).
 */
export const getCouverture = async (req: AuthRequest, res: Response) => {
  try {
    res.json(await couverturePourAbonne(req.userId!, req.params.pronosticId));
  } catch (e: any) { repondreErreur(res, e); }
};

export const placeBet = async (req: AuthRequest, res: Response) => {
  try {
    const { pronostic_id, staked_amount, cote_obtenue } = req.body;
    if (!pronostic_id || !staked_amount) {
      res.status(400).json({ message: 'pronostic_id et staked_amount requis.' }); return;
    }
    const cote = cote_obtenue === undefined || cote_obtenue === null || cote_obtenue === ''
      ? undefined : parseFloat(cote_obtenue);
    const bet = await svc.placeBet(req.userId!, pronostic_id, parseFloat(staked_amount), cote);
    res.status(201).json(bet);
  } catch (e: any) {
    // La saisie fermée n'est pas une demande malformée : l'état du match a
    // changé. Le code permet au mobile de rafraîchir sa liste plutôt que
    // d'afficher une erreur que l'utilisateur ne peut pas corriger.
    if (e instanceof svc.PariFerme) {
      res.status(e.statut).json({
        message: e.message,
        code:    `BET_CLOSED_${e.motif.toUpperCase()}`,
      });
      return;
    }
    if (e instanceof svc.MiseAActualiser) {
      res.status(409).json({message:e.message, code:'STAKE_CHANGED'}); return;
    }
    if (e instanceof ErreurMetier) { repondreErreur(res, e); return; }
    const isDuplicate = e.message?.includes('déjà misé');
    res.status(isDuplicate ? 409 : 400).json({
      message: e.message,
      ...(isDuplicate ? { code: 'BET_ALREADY_PLACED' } : {}),
    });
  }
};

/** POST /bankroll/bet/:id/confirmer — { mise_reelle? } ; sans montant : « oui ». */
export const confirmerMise = async (req: AuthRequest, res: Response) => {
  try {
    const r = await svc.confirmerMise(req.userId!, req.params.id, req.body?.mise_reelle);
    res.json(r);
  } catch (e: any) { repondreErreur(res, e); }
};

export const getStats = async (req: AuthRequest, res: Response) => {
  try {
    const stats = await svc.getBankrollStats(req.userId!);
    res.json(stats);
  } catch (e: any) { repondreErreur(res, e); }
};

export const getSuggestedStake = async (req: AuthRequest, res: Response) => {
  try {
    const bankroll = await svc.getBankroll(req.userId!);
    if (!bankroll) { res.status(404).json({ message: 'Pas de bankroll configurée.' }); return; }

    // Le nouveau mobile transmet le pronostic : la note vient du serveur.
    // Compatibilité avec les versions déjà installées : confidence ne sert
    // qu'à l'aperçu ; placeBet impose toujours la vraie note du pronostic.
    let confidenceScore = Number(req.query.confidence ?? 3);
    let confidencePct: number | null = null;
    if (req.query.pronostic_id != null) {
      if (typeof req.query.pronostic_id !== 'string' || req.query.pronostic_id.length > 80) {
        res.status(400).json({message:'Pronostic invalide.'}); return;
      }
      const id = req.query.pronostic_id;
      const pro = await prisma.pronostic.findUnique({where:{id}}) ??
        await prisma.pronostic.findUnique({where:{principalMatchId:id}});
      if (!pro) { res.status(404).json({message:'Pronostic introuvable.'}); return; }
      confidenceScore = pro.confidenceScore;
      confidencePct   = pourcentageConfiance(pro);
    }
    if (!Number.isInteger(confidenceScore) || confidenceScore < 1 || confidenceScore > 5) {
      res.status(400).json({message:'Confiance invalide : note attendue de 1 à 5.'}); return;
    }
    const suggested = svc.suggestStake(
      bankroll.currentBalance, confidenceScore, bankroll.currency);
    res.json({
      suggested_amount: suggested,
      stake_percent:    partSelonConfiance(confidenceScore) * 100,
      confidence_score: confidenceScore,
      confidence_pct:   confidencePct ?? pourcentageDepuisNiveau(confidenceScore),
      stake_rule:       "analyst_confidence",
      current_balance:  bankroll.currentBalance,
      currency:         bankroll.currency,
    });
  } catch (e: any) { repondreErreur(res, e); }
};

// ── ADMIN ──────────────────────────────────────────────────────────────────────
/** GET /bankroll/admin/list — vue d'ensemble de toutes les bankrolls utilisateur */
export const adminListBankrolls = async (req: AdminRequest, res: Response) => {
  try {
    const result = await svc.listBankrolls({
      page:    parseInt(req.query.page as string ?? '1'),
      perPage: parseInt(req.query.per_page as string ?? '20'),
      search:  req.query.search as string,
      sortBy:  req.query.sort_by as any,
      sortDir: (req.query.sort_dir as 'asc' | 'desc') ?? 'desc',
    });
    res.json(result);
  } catch (e: any) { repondreErreur(res, e); }
};

/** GET /bankroll/admin/stats — agrégats sur toutes les bankrolls */
export const adminBankrollStats = async (_req: AdminRequest, res: Response) => {
  try { res.json(await svc.listBankrollsStats()); }
  catch (e: any) { repondreErreur(res, e); }
};

/** GET /bankroll/admin/:userId — détail complet de la bankroll d'un utilisateur */
export const adminGetBankrollDetail = async (req: AdminRequest, res: Response) => {
  try {
    const user = await prisma.user.findUnique({
      where:  { id: req.params.userId },
      select: { id: true, pseudo: true, phoneNumber: true, email: true, avatarUrl: true, createdAt: true },
    });
    if (!user) { res.status(404).json({ message: 'Utilisateur introuvable.' }); return; }

    const [bankroll, stats] = await Promise.all([
      svc.getBankroll(req.params.userId),
      svc.getBankrollStats(req.params.userId),
    ]);
    // Le journal des mouvements (B1) : ce qui permet de répondre à une
    // contestation, et la preuve qu'aucune écriture n'est passée à côté.
    const [journal, mouvements, listeCombines] = bankroll ? await Promise.all([
      svc.verifierMouvements(bankroll.id),
      prisma.bankrollMouvement.findMany({
        where: { bankrollId: bankroll.id }, orderBy: { creeLe: 'desc' }, take: 50 }),
      // Les combinés du compte (28 novembre 2026), au format de l'app.
      combines.lireCombines(bankroll.id),
    ]) : [null, [], []];

    res.json({
      user,
      bankroll: bankroll ? {
        id:              bankroll.id,
        total_budget:    bankroll.totalBudget,
        current_balance: bankroll.currentBalance,
        currency:        bankroll.currency,
        last_reset_at:   bankroll.lastResetAt,
        created_at:      bankroll.createdAt,
        journal,
        mouvements: mouvements.map(m => ({
          type: m.type, montant: m.montant, solde_apres: m.soldeApres,
          pari_id: m.pariId, motif: m.motif, cree_le: m.creeLe,
        })),
        bets: bankroll.bets.map(b => ({
          id:               b.id,
          staked_amount:    b.stakedAmount,
          suggested_amount: b.suggestedAmount,
          odds_used:        b.oddsUsed,
          potential_gain:   b.potentialGain,
          result:           b.result,
          profit:           b.profit,
          settled_at:       b.settledAt,
          created_at:       b.createdAt,
          match: {
            id:         b.pronostic.match.id,
            home_team:  b.pronostic.match.homeTeam,
            away_team:  b.pronostic.match.awayTeam,
            match_date: b.pronostic.match.matchDate,
            league:     b.pronostic.match.league,
            // Écussons, statut et score : la fiche d'un pari montre les équipes
            // comme le reste de l'application, et dit si le match est en cours.
            home_team_logo: b.pronostic.match.homeTeamLogo,
            away_team_logo: b.pronostic.match.awayTeamLogo,
            status:         statutPublic(b.pronostic.match.status),
            home_score:     b.pronostic.match.homeScore,
            away_score:     b.pronostic.match.awayScore,
          },
          prediction_label: b.pronostic.predictionLabel,
        prediction_label_en: b.pronostic.predictionLabelEn ?? null,
          confidence_score: b.pronostic.confidenceScore,
          confidence_pct: pourcentageConfiance(b.pronostic),
          // La mise sur l'inverse, si l'abonné l'a enregistrée.
          couverture_enregistree: couverturePourApi(b.couvertureEnregistree),
        })),
        combines: listeCombines.map(combinePourApi),
      } : null,
      stats,
    });
  } catch (e: any) { repondreErreur(res, e); }
};

/** Le statut d'un match tel que l'application le lit partout. */
function statutPublic(statut: string): 'live' | 'finished' | 'upcoming' {
  const s = statut.toLowerCase();
  return s === 'live' ? 'live' : s === 'finished' ? 'finished' : 'upcoming';
}
