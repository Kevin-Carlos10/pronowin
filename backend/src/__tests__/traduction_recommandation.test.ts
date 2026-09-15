import { traduireRecommandation } from '../services/traduction_recommandation';

/**
 * Les six formes ci-dessous ont été relevées sur des réponses réelles
 * d'API-Football (La Liga, saison 2026), pas imaginées.
 */
describe('traduireRecommandation', () => {
  describe('formes observées en production', () => {
    const cas: Array<[string, string]> = [
      ['Winner : Alaves',
       'Vainqueur : Alaves'],
      ['Double chance : Atletico Madrid or draw',
       'Double chance : Atletico Madrid ou match nul'],
      ['Double chance : draw or Real Madrid',
       'Double chance : match nul ou Real Madrid'],
      ['Combo Double chance : draw or Barcelona and -2.5 goals',
       'Double chance : match nul ou Barcelona, combiné avec moins de 2,5 buts'],
      ['Combo Double chance : Athletic Club or draw and -3.5 goals',
       'Double chance : Athletic Club ou match nul, combiné avec moins de 3,5 buts'],
      ['No predictions available',
       'Aucune recommandation disponible'],
    ];

    it.each(cas)('%s', (anglais, attendu) => {
      expect(traduireRecommandation(anglais)).toBe(attendu);
    });
  });

  describe('formes documentées par le fournisseur', () => {
    it('traduit un combiné vainqueur', () => {
      expect(traduireRecommandation('Combo Winner : Barcelona and +1.5 goals'))
        .toBe('Vainqueur : Barcelona, combiné avec plus de 1,5 but');
    });

    it('traduit un seuil de buts seul', () => {
      expect(traduireRecommandation('+2.5 goals')).toBe('Plus de 2,5 buts');
      expect(traduireRecommandation('-1.5 goals')).toBe('Moins de 1,5 but');
    });

    it('traduit « no bet »', () => {
      expect(traduireRecommandation('No bet')).toBe('Aucun pari conseillé');
    });
  });

  describe('les noms d\'équipes ne sont jamais altérés', () => {
    // Un nom d'équipe peut contenir n'importe quoi — y compris les mots que
    // l'analyseur cherche. Les toucher produirait un conseil sur une équipe
    // qui n'existe pas.
    it('conserve un nom contenant un mot-clé anglais', () => {
      expect(traduireRecommandation('Winner : Drawsko Pomorskie'))
        .toBe('Vainqueur : Drawsko Pomorskie');
    });

    it('conserve les accents et traits d\'union', () => {
      expect(traduireRecommandation('Winner : Saint-Étienne'))
        .toBe('Vainqueur : Saint-Étienne');
    });

    it('conserve un nom composé de plusieurs mots', () => {
      expect(traduireRecommandation('Double chance : Real Sociedad or draw'))
        .toBe('Double chance : Real Sociedad ou match nul');
    });
  });

  describe('accord du pluriel sur les buts', () => {
    it('« 1,5 but » reste au singulier', () => {
      expect(traduireRecommandation('+1.5 goals')).toContain('1,5 but');
      expect(traduireRecommandation('+1.5 goals')).not.toContain('1,5 buts');
    });

    it('« 2,5 buts » prend le pluriel', () => {
      expect(traduireRecommandation('+2.5 goals')).toContain('2,5 buts');
    });
  });

  describe('une forme inconnue n\'est jamais approximée', () => {
    it('renvoie le texte d\'origine intact', () => {
      // Inventer une traduction sur un conseil de pari serait pire que de
      // laisser l'anglais : le lecteur miserait sur autre chose que ce que le
      // modèle recommande.
      const inconnu = 'Handicap : Barcelona -1 and both teams to score';
      expect(traduireRecommandation(inconnu)).toBe(inconnu);
    });

    it('journalise la forme manquante pour qu\'elle remonte', () => {
      const espion = jest.spyOn(console, 'warn').mockImplementation(() => {});
      traduireRecommandation('Une forme totalement nouvelle');
      expect(espion).toHaveBeenCalledWith(
        expect.stringContaining('Forme non traduite'));
      espion.mockRestore();
    });
  });

  describe('entrées vides', () => {
    it.each([[null], [undefined], ['']])('%p donne null', (v) => {
      expect(traduireRecommandation(v as any)).toBeNull();
    });
  });
});
