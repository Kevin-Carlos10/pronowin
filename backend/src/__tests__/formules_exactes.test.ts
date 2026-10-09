/**
 * Les formules décrivent ce que le produit fait.
 *
 * C'est la liste que l'écran d'abonnement affiche : le dernier texte lu avant
 * de payer. Elle portait quatre écarts, tous vérifiés dans le code avant
 * correction.
 *
 *   « 3 pronostics par jour »  — aucun quota n'existe, ni serveur ni mobile.
 *   « Sans publicité »          — aucune régie n'est intégrée au projet.
 *   « 2 mois offerts »          — l'annuel en économise trois.
 *   l'espace communauté         — absent, alors que c'est un vrai avantage.
 *
 * Le second est le plus retors : listé en `locked_features` du gratuit, il
 * disait à l'utilisateur qu'il voyait des publicités. Une formule peut mentir
 * en défaveur du produit, et personne ne s'en plaint jamais.
 */
jest.mock('../lib/prisma', () => ({ prisma: {} }));

// L'écran lit ces plans sans jamais toucher au code promo ; on isole donc la
// lecture de configuration, qui irait sinon chercher la base.
jest.mock('../services/app_config.service', () => ({
  codePromoPour:        async () => '',
  codesPromoParPlateforme: async () => ({}),
  lireConfig:           async () => ({}),
}));

describe('exactitude des formules', () => {
  let plans: any[];
  let PRIX: any;

  beforeAll(async () => {
    PRIX  = await import('../services/subscription.service');
    plans = await new PRIX.SubscriptionService().getPlans();
  });

  const par = (id: string) => plans.find((p) => p.id === id);
  const tout = (p: any) => [...(p.features ?? []), ...(p.locked_features ?? [])].join(' | ');

  it('aucune formule n\'annonce un quota quotidien', () => {
    // `estVerrouille()` est la seule règle d'accès : elle ne compte rien.
    for (const p of plans) {
      expect(tout(p)).not.toMatch(/\d+\s+pronostics?\s+par\s+jour/i);
    }
  });

  it('aucune formule ne parle de publicité', () => {
    // Tant qu'aucune régie n'est intégrée, la promesse est vide côté Premium
    // et mensongère côté gratuit.
    for (const p of plans) {
      expect(tout(p)).not.toMatch(/publicit/i);
    }
  });

  it('l\'économie annoncée pour l\'annuel est celle que les prix donnent', () => {
    // Le garde qui se maintient tout seul : si un tarif bouge, c'est la
    // description qui devient fausse, et c'est ici qu'on l'apprend — pas dans
    // une réclamation d'abonné.
    const mensuel = PRIX.PREMIUM_PRICE_FCFA_MONTHLY;
    const annuel  = PRIX.PREMIUM_PRICE_FCFA_ANNUAL;
    const moisOfferts = Math.round((mensuel * 12 - annuel) / mensuel);

    const annonce = par('premium_annual').description;
    const chiffre = annonce.match(/(\d+)\s+mois\s+offert/i);

    expect(chiffre).not.toBeNull();
    expect(Number(chiffre![1])).toBe(moisOfferts);
  });

  it('l\'espace communauté est présenté comme un avantage Premium', () => {
    // Décision produit : la communauté reste Premium (premiumMiddleware sur
    // les trois routes de commentaires). L'onboarding le dit désormais ; les
    // formules doivent le dire aussi, sans quoi l'avantage ne se vend pas.
    expect(par('premium_monthly').features.join(' ')).toMatch(/communaut/i);
    expect(par('free').locked_features.join(' ')).toMatch(/communaut/i);
  });

  it('les deux formules Premium ouvrent exactement le même accès', () => {
    // Le contre-test : elles ne diffèrent que par la durée et le prix. Un
    // avantage listé sur l'une seulement se lirait comme une restriction.
    expect(par('premium_annual').features).toEqual(par('premium_monthly').features);
  });
});
