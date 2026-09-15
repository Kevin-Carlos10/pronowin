import * as fs from 'fs';
import * as path from 'path';

import {
  RECHERCHE_MAX,
  RECHERCHE_MIN,
  construireRecherche,
} from '../services/recherche_matchs';

/**
 * Chercher un match, c'est interroger l'ensemble — pas ce qu'on a sous la main.
 *
 * L'écran filtrait la liste **déjà chargée** dans le provider : vingt matchs,
 * ceux de la page courante et des filtres courants. Il ne demandait ni les
 * pages suivantes, ni le serveur avec le terme saisi.
 *
 * Une équipe qui existe mais dont la page n'avait pas encore été téléchargée
 * était donc annoncée absente. Le résultat dépendait de l'endroit d'où l'on
 * venait et du nombre de fois qu'on avait fait défiler la liste — un compte
 * qui vient d'ouvrir l'application ne trouvait presque rien.
 */
describe('le fragment de recherche', () => {
  it('cherche dans les deux équipes et la compétition', () => {
    const w = construireRecherche('PSG') as any;

    const champs = (w.OR as any[]).map((c) => Object.keys(c)[0]);
    expect(champs).toEqual(expect.arrayContaining([
      'homeTeam', 'awayTeam', 'league',
    ]));
  });

  it('couvre aussi les noms complets', () => {
    // « Paris Saint-Germain » ne se trouve pas en cherchant dans `homeTeam`,
    // qui porte la forme courte.
    const w = construireRecherche('Saint-Germain') as any;
    const champs = (w.OR as any[]).map((c) => Object.keys(c)[0]);

    expect(champs).toEqual(expect.arrayContaining([
      'homeTeamFull', 'awayTeamFull',
    ]));
  });

  it('ignore la casse', () => {
    const w = construireRecherche('psg') as any;
    for (const clause of w.OR as any[]) {
      expect(Object.values(clause)[0]).toMatchObject({ mode: 'insensitive' });
    }
  });

  it('coupe les espaces de bord', () => {
    const w = construireRecherche('  Lyon  ') as any;
    expect(w.OR[0].homeTeam.contains).toBe('Lyon');
  });

  it('ne cherche pas sur un terme trop court', () => {
    // Contrepartie : deux lettres ramèneraient la moitié du catalogue, et
    // l'écran afficherait n'importe quoi pendant la frappe.
    for (const t of ['', ' ', 'a', ' x ']) {
      expect(construireRecherche(t)).toEqual({});
    }
    expect(RECHERCHE_MIN).toBe(2);
  });

  it('cherche dès le seuil atteint', () => {
    const w = construireRecherche('OM') as any;
    expect(w.OR).toBeDefined();
  });

  it('ignore une saisie démesurée', () => {
    // Au-delà, ce n'est plus un terme de recherche — un collage accidentel,
    // le plus souvent. On ne fabrique pas une requête pour cela.
    expect(construireRecherche('x'.repeat(RECHERCHE_MAX + 1))).toEqual({});
  });

  it('rend un objet vide plutôt que de lever', () => {
    // Un terme trop court n'est pas une erreur : c'est quelqu'un qui tape.
    expect(construireRecherche(null)).toEqual({});
    expect(construireRecherche(undefined)).toEqual({});
  });

  it('ne cherche pas dans le libellé du pronostic', () => {
    // Il est en français et très court : chercher « over » y ramènerait tous
    // les matchs de la journée. Décision assumée, pas un oubli.
    const w = construireRecherche('over') as any;
    const champs = (w.OR as any[]).map((c) => Object.keys(c)[0]);
    expect(champs).not.toContain('predictionLabel');
  });
});

/**
 * La fonction ne sert à rien si la requête ne l'appelle pas.
 *
 * Un banc qui n'éprouve que le fragment resterait vert pendant que la liste
 * repartirait sans filtre — vérifié en retirant l'appel.
 */
describe('la requête applique la recherche', () => {
  const service = fs.readFileSync(
    path.resolve(__dirname, '..', 'services', 'pronostics.service.ts'), 'utf8');

  it('le `where` du match porte le fragment', () => {
    expect(service).toContain('construireRecherche(params.recherche)');
  });

  it('le paramètre existe dans la signature', () => {
    expect(service).toContain('recherche?:');
  });
});

/**
 * Deux recherches différentes ne doivent pas se resservir la même réponse.
 *
 * La clé de cache ne portait que les filtres. Sans le terme, chercher « PSG »
 * puis « OM » aurait rendu deux fois le premier résultat.
 */
describe('le cache distingue les termes', () => {
  const controleur = fs.readFileSync(
    path.resolve(__dirname, '..', 'controllers', 'pronostics.controller.ts'),
    'utf8');

  it('le terme figure dans la clé', () => {
    expect(controleur).toContain("${params.recherche ?? ''}");
  });

  it('le terme est transmis au service', () => {
    expect(controleur).toContain('recherche:     req.query.q');
  });
});
