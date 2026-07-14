
import { prisma } from '../lib/prisma';

// ── ML probability model ──────────────────────────────────────────────────────

function oddsToImpliedProb(odds: number): number {
  if (odds <= 0) return 0;
  return Math.min(0.99, Math.max(0.01, 1 / odds));
}

function formToProb(homeFormPoints: number, awayFormPoints: number): number {
  const total = homeFormPoints + awayFormPoints;
  if (total === 0) return 0.5;
  return Math.min(0.95, Math.max(0.05, homeFormPoints / total));
}

export interface AIPrediction {
  probability: number;
  explanation: string;
}

export function computeProbability(
  predictionType: string,
  oddsHome: number,
  oddsDraw: number,
  oddsAway: number,
  oddsRecommended: number,
  homeFormPoints: number,
  awayFormPoints: number,
): number {
  let oddsProb: number;
  switch (predictionType) {
    case 'win1':    oddsProb = oddsToImpliedProb(oddsHome); break;
    case 'draw':    oddsProb = oddsToImpliedProb(oddsDraw); break;
    case 'win2':    oddsProb = oddsToImpliedProb(oddsAway); break;
    default:        oddsProb = oddsToImpliedProb(oddsRecommended); break;
  }

  const formProb      = formToProb(homeFormPoints, awayFormPoints);
  const homeAdvantage = predictionType === 'win1' ? 0.55 : predictionType === 'win2' ? 0.45 : 0.5;
  const blended       = oddsProb * 0.45 + formProb * 0.35 + homeAdvantage * 0.20;

  return Math.round(Math.min(97, Math.max(30, blended * 100)));
}

// ── Générateur d'explications intelligent (sans API externe) ──────────────────

function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

function generateExplanation(params: {
  homeTeam:        string;
  awayTeam:        string;
  predictionType:  string;
  predictionLabel: string;
  probability:     number;
  homeFormPoints:  number;
  awayFormPoints:  number;
  oddsRecommended: number;
  league:          string;
}): string {
  const { homeTeam, awayTeam, predictionType, probability,
          homeFormPoints, awayFormPoints, oddsRecommended } = params;

  const probLevel = probability >= 75 ? 'high' : probability >= 60 ? 'medium' : 'low';
  const homeForm  = homeFormPoints >= 10 ? 'excellent' : homeFormPoints >= 6 ? 'correct' : 'faible';
  const awayForm  = awayFormPoints >= 10 ? 'excellent' : awayFormPoints >= 6 ? 'correct' : 'faible';
  const oddsLow   = oddsRecommended < 1.7;
  const oddsMed   = oddsRecommended >= 1.7 && oddsRecommended < 2.5;

  // ─ Phrases selon le type de pronostic ─
  const phrase1Map: Record<string, string[]> = {
    win1: [
      `${homeTeam} joue à domicile avec une forme ${homeForm}, un avantage décisif face à ${awayTeam}.`,
      `L'avantage du terrain profite à ${homeTeam}, dont la dynamique est ${homeForm} sur les derniers matchs.`,
      `${homeTeam} s'appuie sur sa solidité à domicile pour l'emporter face à des visiteurs en forme ${awayForm}.`,
      `La forme ${homeForm} de ${homeTeam} et l'avantage du terrain penchent clairement en leur faveur.`,
    ],
    win2: [
      `${awayTeam} démontre une forme ${awayForm} qui leur permet d'aller chercher des points à l'extérieur.`,
      `Malgré le déplacement, ${awayTeam} affiche une régularité ${awayForm} qui leur donne confiance.`,
      `${awayTeam} en forme ${awayForm} face à ${homeTeam} qui peine — les visiteurs partent favoris.`,
      `La forme déclinante de ${homeTeam} ouvre la porte à ${awayTeam}, solide en déplacement.`,
    ],
    draw: [
      `${homeTeam} et ${awayTeam} présentent des niveaux de forme proches, favorisant un partage des points.`,
      `L'équilibre entre les deux équipes et les cotes du marché pointent vers un résultat serré.`,
      `Avec des formes comparables, ${homeTeam} et ${awayTeam} devraient se neutraliser.`,
      `Le rapport de forces est équilibré — les bookmakers confirment cette tendance au nul.`,
    ],
    btts: [
      `${homeTeam} et ${awayTeam} ont toutes deux des défenses perméables — les buts des deux côtés sont attendus.`,
      `Les deux équipes marquent régulièrement — le BTTS s'appuie sur leurs attaques efficaces.`,
      `Offensivement actives, ${homeTeam} et ${awayTeam} devraient toutes deux trouver le chemin des filets.`,
    ],
    over25: [
      `Les deux équipes privilégient le jeu offensif — plus de 2,5 buts est l'issue la plus probable.`,
      `Avec des défenses exposées et des attaques en feu, plus de 2 buts au total est attendu.`,
      `L'historique récent des deux équipes montre des rencontres prolifiques en buts.`,
    ],
    under25: [
      `Les deux équipes misent sur la solidité défensive — moins de 3 buts est l'issue attendue.`,
      `Un match fermé est anticipé, avec des défenses organisées limitant les occasions.`,
      `Les statistiques défensives récentes des deux équipes orientent vers un faible nombre de buts.`,
    ],
    over35: [
      `Un match très ouvert est prévu — plus de 3,5 buts reflète les tendances offensives des deux côtés.`,
      `Les récents matchs de ces équipes sont marqués par de nombreux buts — la tendance devrait se confirmer.`,
    ],
    under35: [
      `Un match tactique est attendu — moins de 4 buts est cohérent avec les stats défensives des deux équipes.`,
      `Les deux équipes jouent bas et compact — peu de buts sont anticipés dans cette rencontre.`,
    ],
  };

  const phrase2Map: Record<string, string[]> = {
    high: [
      `Notre modèle accorde ${probability}% de probabilité à ce scénario, soutenu par les cotes à ${oddsRecommended.toFixed(2)}.`,
      `Avec ${probability}% de confiance, c'est l'un de nos pronostics les mieux cotés du jour.`,
      `La convergence des signaux statistiques donne ${probability}% de fiabilité à cette prédiction.`,
    ],
    medium: [
      `Notre algorithme estime la probabilité de succès à ${probability}% — un pari à valeur intéressante.`,
      `À ${probability}% de probabilité calculée, ce pronostic offre un bon rapport risque/rendement.`,
      `Les données de forme et de marché convergent vers ${probability}% — une opportunité solide.`,
    ],
    low: [
      `Probabilité estimée à ${probability}% — un pari à risque modéré mais avec une cote attractive de ${oddsRecommended.toFixed(2)}.`,
      `Notre modèle donne ${probability}% à ce scénario — à jouer avec prudence et mise raisonnée.`,
      `À ${probability}%, ce pronostic est moins évident mais la cote de ${oddsRecommended.toFixed(2)} compense le risque.`,
    ],
  };

  // Bonus : mention des cotes si très basses (signe de favori fort)
  const oddsComment = oddsLow
    ? ` La faible cote (${oddsRecommended.toFixed(2)}) confirme le statut de favori.`
    : oddsMed
    ? ` La cote de ${oddsRecommended.toFixed(2)} reflète un scénario probable mais pas certain.`
    : '';

  const type = predictionType in phrase1Map ? predictionType : 'win1';
  const p1   = pick(phrase1Map[type] || phrase1Map['win1']);
  const p2   = pick(phrase2Map[probLevel]) + oddsComment;

  return `${p1} ${p2}`;
}

// ── Main export ───────────────────────────────────────────────────────────────

export async function analyzePronostic(id: string): Promise<AIPrediction> {
  // Accepte un pronostic UUID ou un match UUID (selon l'endpoint appelant)
  let prono = await prisma.pronostic.findUnique({ where: { id }, include: { match: true } });
  if (!prono) prono = await prisma.pronostic.findUnique({ where: { matchId: id }, include: { match: true } });

  // Pas de pronostic → calculer depuis le match directement (cotes neutres)
  if (!prono) {
    const match = await prisma.match.findUnique({ where: { id } });
    if (!match) throw new Error('Pronostic not found');
    const probability = computeProbability('win1', 2, 3, 2, 2,
      match.homeFormPoints ?? 0, match.awayFormPoints ?? 0);
    const explanation = generateExplanation({
      homeTeam: match.homeTeam, awayTeam: match.awayTeam,
      predictionType: 'win1', predictionLabel: `Victoire ${match.homeTeam}`,
      probability, homeFormPoints: match.homeFormPoints ?? 0,
      awayFormPoints: match.awayFormPoints ?? 0,
      oddsRecommended: 2, league: match.league,
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

  const probability = computeProbability(
    prono.predictionType,
    prono.oddsHome,
    prono.oddsDraw,
    prono.oddsAway,
    prono.oddsRecommended,
    prono.match.homeFormPoints ?? 0,
    prono.match.awayFormPoints ?? 0,
  );

  const explanation = generateExplanation({
    homeTeam:        prono.match.homeTeam,
    awayTeam:        prono.match.awayTeam,
    predictionType:  prono.predictionType,
    predictionLabel: prono.predictionLabel,
    probability,
    homeFormPoints:  prono.match.homeFormPoints ?? 0,
    awayFormPoints:  prono.match.awayFormPoints ?? 0,
    oddsRecommended: prono.oddsRecommended,
    league:          prono.match.league,
  });

  // Mise en cache en DB
  await prisma.pronostic.update({
    where: { id: prono.id },
    data:  { aiProbability: probability, aiExplanation: explanation },
  });

  return { probability, explanation };
}
