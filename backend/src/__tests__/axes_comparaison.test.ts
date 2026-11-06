/**
 * Deux règles sur les axes de comparaison affichés sous « Pourquoi ce
 * pronostic ». Aucune n'est visible d'un test de type ou d'un rendu : l'écran
 * se charge parfaitement dans les deux cas — il dit simplement autre chose que
 * ce que la donnée dit.
 */

/**
 * Reproduit fidèlement la construction faite dans
 * `ApiFootballInsights.getPrediction` : mêmes axes, même filtre, même
 * conversion. Le service lui-même n'est pas instanciable sans client HTTP.
 */
const AXES: Array<[string, string]> = [
  ['form', 'Forme'],
  ['att', 'Attaque'],
  ['def', 'Défense'],
  ['goals', 'Buts'],
  ['h2h', 'Confrontations'],
  ['poisson_distribution', 'Poisson'],
  ['total', 'Synthèse'],
];

const pct = (v: unknown): number => {
  const n = parseFloat(String(v ?? '').replace('%', ''));
  return Number.isFinite(n) ? n : 0;
};

function construireAxes(comparison: Record<string, any>) {
  return AXES
    .filter(([cle]) => comparison[cle])
    .map(([cle, libelle]) => ({
      label: libelle,
      home: pct(comparison[cle].home),
      away: pct(comparison[cle].away),
    }))
    .filter(a => a.home > 0 || a.away > 0);
}

/** La réponse réelle observée sur Elche – Barcelona. */
const REPONSE_REELLE = {
  form:  { home: '100%', away: '0%' },
  att:   { home: '100%', away: '0%' },
  def:   { home: '0%',   away: '100%' },
  goals: { home: '17%',  away: '83%' },
  h2h:   { home: '0%',   away: '100%' },
  poisson_distribution: { home: '0%', away: '0%' },
  total: { home: '17%', away: '83%' },
};

describe('axes de comparaison', () => {
  it('écarte un axe sans aucune donnée', () => {
    const axes = construireAxes(REPONSE_REELLE);

    // « Modèle de Poisson : 0 / 0 » n'est pas une égalité, c'est une absence.
    // Affichée, elle occupait une ligne et — avec l'ancienne règle de couleur —
    // désignait un vainqueur.
    expect(axes.map(a => a.label)).not.toContain('Poisson');
  });

  it('conserve un axe dont une seule valeur est nulle', () => {
    // 100 / 0 est un écart maximal, pas une absence : il doit rester.
    const axes = construireAxes(REPONSE_REELLE);
    expect(axes.find(a => a.label === 'Forme')).toEqual(
      { label: 'Forme', home: 100, away: 0 });
  });

  it('l\'axe de synthèse ne s\'appelle plus « Total »', () => {
    const axes = construireAxes(REPONSE_REELLE);
    const libelles = axes.map(a => a.label);

    // Nommer « Total » une valeur qui n'est pas la somme ni la moyenne des
    // lignes du dessus invite à vérifier une arithmétique qui ne tombe pas
    // juste.
    expect(libelles).not.toContain('Total');
    expect(libelles).toContain('Synthèse');
  });

  it('la synthèse ne se déduit effectivement pas des autres axes', () => {
    // Ce test documente *pourquoi* le renommage était nécessaire : si un jour
    // le fournisseur alignait les deux, on pourrait revenir à « Total ».
    const axes = construireAxes(REPONSE_REELLE);
    const detail = axes.filter(a => a.label !== 'Synthèse');
    const synthese = axes.find(a => a.label === 'Synthèse')!;

    const moyenne = detail.reduce((s, a) => s + a.home, 0) / detail.length;
    expect(Math.round(moyenne)).not.toBe(Math.round(synthese.home));
  });

  it('un axe absent de la réponse n\'apparaît pas', () => {
    const axes = construireAxes({ form: { home: '60%', away: '40%' } });
    expect(axes).toHaveLength(1);
    expect(axes[0].label).toBe('Forme');
  });

  it('une réponse vide ne produit aucun axe', () => {
    expect(construireAxes({})).toEqual([]);
  });
});
