
import { prisma } from '../lib/prisma';
import { apiFootballInsights } from './api_football.service';
import type { MatchPrediction } from './api_football_insights.service';

// ── Modèle statistique ────────────────────────────────────────────────────────
//
// Aucun modèle génératif n'intervient ici. La probabilité est une combinaison
// pondérée de deux signaux mesurés : la cote du bookmaker et, uniquement quand
// c'est pertinent, l'écart de forme entre les deux équipes. L'explication
// produite décrit ce calcul — elle n'affirme jamais un fait que le modèle n'a
// pas réellement mesuré (cf. `explainPrediction`).

/** Probabilité implicite d'une cote. Inclut la marge du bookmaker, elle
 *  surestime donc légèrement et de façon systématique. */
function oddsToImpliedProb(odds: number): number {
  if (odds <= 0) return 0;
  return Math.min(0.99, Math.max(0.01, 1 / odds));
}

export interface StatPrediction {
  probability: number;
  explanation: string;
}

/**
 * Signal de forme, orienté selon le marché — `null` quand la forme n'apporte
 * rien d'exploitable.
 *
 * L'écart de forme domicile/extérieur ne renseigne que sur *qui* gagne, pas
 * sur le nombre de buts : l'appliquer à un marché de totaux (over/under, BTTS)
 * ou à un marché personnalisé revient à injecter du bruit. Ces marchés se
 * reposent donc sur la seule cote.
 */
function formSignal(
  predictionType: string,
  homeFormPoints: number,
  awayFormPoints: number,
): number | null {
  const total = homeFormPoints + awayFormPoints;
  if (total === 0) return null; // aucune donnée de forme

  const homeShare = homeFormPoints / total;
  switch (predictionType) {
    case 'win1': return homeShare;
    // Corrigé : la part de forme du *domicile* était utilisée telle quelle pour
    // une victoire extérieure, si bien qu'un domicile en pleine forme
    // augmentait la probabilité prédite de la victoire de son adversaire.
    case 'win2': return 1 - homeShare;
    // Un nul est d'autant plus plausible que les deux formes sont proches.
    case 'draw': return 1 - 2 * Math.abs(homeShare - 0.5);
    default:     return null;
  }
}

/**
 * Probabilité que le modèle d'API-Football attribue à l'issue pronostiquée,
 * ou `null` si elle ne s'applique pas.
 *
 * L'API ne fournit des pourcentages que pour le marché « vainqueur »
 * (domicile / nul / extérieur). Les transposer à un total de buts ou à un
 * handicap serait une invention : on rend `null` et le calcul se passe de ce
 * signal, comme il se passe déjà de la forme sur ces marchés.
 */
export function modelSignal(
  predictionType: string,
  prediction: MatchPrediction | null,
): number | null {
  if (!prediction) return null;
  switch (predictionType) {
    case 'win1': return prediction.percentHome / 100;
    case 'draw': return prediction.percentDraw / 100;
    case 'win2': return prediction.percentAway / 100;
    default:     return null;
  }
}

export function computeProbability(
  predictionType: string,
  oddsHome: number,
  oddsDraw: number,
  oddsAway: number,
  oddsRecommended: number,
  homeFormPoints: number,
  awayFormPoints: number,
  /** Signal externe optionnel — voir `modelSignal`. */
  modelProb: number | null = null,
): number {
  let oddsProb: number;
  switch (predictionType) {
    case 'win1':    oddsProb = oddsToImpliedProb(oddsHome); break;
    case 'draw':    oddsProb = oddsToImpliedProb(oddsDraw); break;
    case 'win2':    oddsProb = oddsToImpliedProb(oddsAway); break;
    default:        oddsProb = oddsToImpliedProb(oddsRecommended); break;
  }

  // L'ancien terme constant « avantage du terrain » a été retiré : cet effet
  // est déjà intégré par le bookmaker dans la cote, l'ajouter le comptait deux
  // fois tout en rapprochant mécaniquement toutes les prédictions de 50 %.
  // Pondération : la cote garde le poids dominant — c'est le seul signal
  // adossé à de l'argent réel, donc le mieux informé. Le modèle statistique
  // d'API-Football est une seconde opinion indépendante, la forme reste le
  // signal le plus faible (trois derniers résultats, sans contexte).
  const form  = formSignal(predictionType, homeFormPoints, awayFormPoints);
  const model = modelProb;

  let blended: number;
  if (form !== null && model !== null) {
    blended = oddsProb * 0.55 + model * 0.30 + form * 0.15;
  } else if (model !== null) {
    blended = oddsProb * 0.70 + model * 0.30;
  } else if (form !== null) {
    blended = oddsProb * 0.65 + form * 0.35;
  } else {
    blended = oddsProb;
  }

  // Bornes volontairement larges : ramener une cote à 5.00 (20 % implicite) à
  // un plancher de 30 % gonflait artificiellement les pronostics risqués.
  return Math.round(Math.min(95, Math.max(15, blended * 100)));
}

// ── Explication ──────────────────────────────────────────────

/**
 * Décrit le calcul réellement effectué, avec ses chiffres.
 *
 * La version précédente tirait au sort des phrases de commentaire sportif qui
 * affirmaient des faits jamais mesurés — « défenses perméables », « historique
 * prolifique en buts » — alors qu'aucune statistique défensive ni aucun
 * historique de buts n'est consulté ici. Sur une fonctionnalité payante, cela
 * revenait à vendre des affirmations inventées.
 *
 * Cette version est déterministe (mêmes entrées → même texte) et ne mentionne
 * que des grandeurs effectivement utilisées par `computeProbability`.
 */
export function explainPrediction(params: {
  homeTeam:        string;
  awayTeam:        string;
  predictionType:  string;
  probability:     number;
  homeFormPoints:  number;
  awayFormPoints:  number;
  oddsRecommended: number;
  /** Pourcentage du modèle API-Football pour l'issue pronostiquée, 0–100. */
  modelPercent?:   number | null;
}): string {
  const { homeTeam, awayTeam, predictionType, probability,
          homeFormPoints, awayFormPoints, oddsRecommended } = params;
  const modelPercent = params.modelPercent ?? null;

  const parts: string[] = [];

  // 1. Ce que dit le marché.
  if (oddsRecommended > 0) {
    const implied = Math.round(oddsToImpliedProb(oddsRecommended) * 100);
    parts.push(
      `La cote de ${oddsRecommended.toFixed(2)} correspond à une probabilité implicite ` +
      `de ${implied}% (marge du bookmaker incluse).`);
  }

  // 2. Ce que dit la forme — et, si elle n'est pas utilisée, pourquoi.
  const form = formSignal(predictionType, homeFormPoints, awayFormPoints);
  if (form === null && homeFormPoints + awayFormPoints === 0) {
    parts.push(
      `Aucune donnée de forme récente n'est disponible pour ces équipes : ` +
      `l'estimation repose uniquement sur la cote.`);
  } else if (form === null) {
    parts.push(
      `Ce marché ne dépend pas de l'écart de forme entre les deux équipes ` +
      `(celui-ci indique qui gagne, pas le nombre de buts) : l'estimation ` +
      `repose uniquement sur la cote.`);
  } else {
    const leader = homeFormPoints === awayFormPoints
      ? null
      : (homeFormPoints > awayFormPoints ? homeTeam : awayTeam);
    parts.push(
      `Sur la forme récente, ${homeTeam} totalise ${homeFormPoints} points ` +
      `contre ${awayFormPoints} à ${awayTeam}` +
      (leader === null
        ? `, soit un équilibre parfait.`
        : ` — avantage ${leader}.`));
  }

  // 3. La seconde opinion, quand elle existe. Le fournisseur n'est plus
  //    nommé dans le texte affiché, mais on continue de dire que le calcul est
  //    externe : c'est un modèle tiers, pas une mesure de PronoWin, et
  //    l'utilisateur a le droit de savoir d'où sort le chiffre.
  if (modelPercent !== null) {
    parts.push(
      `Un modèle statistique externe, qui croise forme, attaque, ` +
      `défense et confrontations directes, donne ${modelPercent}% à cette issue.`);
  }

  // 4. Le résultat, sans surinterprétation.
  parts.push(
    `En combinant ces signaux, le modèle retient ${probability}% de probabilité ` +
    `de réussite pour ce pronostic.`);

  return parts.join(' ');
}

// ── Main export ───────────────────────────────────────────────────────────────

export async function analyzePronostic(id: string): Promise<StatPrediction> {
  // Accepte un pronostic UUID ou un match UUID (selon l'endpoint appelant)
  let prono = await prisma.pronostic.findUnique({ where: { id }, include: { match: true } });
  if (!prono) prono = await prisma.pronostic.findUnique({ where: { matchId: id }, include: { match: true } });

  // Pas de pronostic → calculer depuis le match directement (cotes neutres)
  if (!prono) {
    const match = await prisma.match.findUnique({ where: { id } });
    if (!match) throw new Error('Pronostic not found');
    const probability = computeProbability('win1', 2, 3, 2, 2,
      match.homeFormPoints ?? 0, match.awayFormPoints ?? 0);
    const explanation = explainPrediction({
      homeTeam: match.homeTeam, awayTeam: match.awayTeam,
      predictionType: 'win1',
      probability, homeFormPoints: match.homeFormPoints ?? 0,
      awayFormPoints: match.awayFormPoints ?? 0,
      oddsRecommended: 2,
    });
    return { probability, explanation };
  }

  // Résultat déjà en cache → retourner directement
  if (prono.aiProbability !== null && prono.aiExplanation !== null) {
    return {
      probability: Math.round(prono.aiProbability!),
      explanation: prono.aiExplanation!,
    };
  }

  // Seconde opinion — best effort : `getPrediction` rend `null` sur panne, sur
  // quota épuisé ou sur un match d'une source sans identifiant API-Football.
  // Le calcul retombe alors exactement sur son comportement précédent.
  const prediction = prono.match.source === 'API_FOOTBALL' && prono.match.externalId
    ? await apiFootballInsights.getPrediction(prono.match.externalId)
    : null;
  const model = modelSignal(prono.predictionType, prediction);

  const probability = computeProbability(
    prono.predictionType,
    prono.oddsHome,
    prono.oddsDraw,
    prono.oddsAway,
    prono.oddsRecommended,
    prono.match.homeFormPoints ?? 0,
    prono.match.awayFormPoints ?? 0,
    model,
  );

  const explanation = explainPrediction({
    homeTeam:        prono.match.homeTeam,
    awayTeam:        prono.match.awayTeam,
    predictionType:  prono.predictionType,
    probability,
    homeFormPoints:  prono.match.homeFormPoints ?? 0,
    awayFormPoints:  prono.match.awayFormPoints ?? 0,
    oddsRecommended: prono.oddsRecommended,
    modelPercent:    model === null ? null : Math.round(model * 100),
  });

  // Mise en cache en DB
  await prisma.pronostic.update({
    where: { id: prono.id },
    data:  { aiProbability: probability, aiExplanation: explanation },
  });

  return { probability, explanation };
}
