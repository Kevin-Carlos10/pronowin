/**
 * Le filtre des commentaires (règle 1.2 de l'App Store).
 *
 * Deux échecs possibles, aussi coûteux l'un que l'autre : laisser passer
 * l'injure déguisée, ou bloquer un message honnête. Les deux sont mesurés.
 */
import { normaliser, refusContenu } from '../utils/filtre_contenu';

describe('le filtre des commentaires', () => {
  it('refuse les injures, même déguisées', () => {
    expect(refusContenu('T\'es un connard')).toBe('TERMES_INTERDITS');
    expect(refusContenu('C0NNNARD va')).toBe('TERMES_INTERDITS');
    expect(refusContenu('espèce d\'enculé')).toBe('TERMES_INTERDITS');
    expect(refusContenu('fils de pute')).toBe('TERMES_INTERDITS');
    expect(refusContenu('Nique ta mère')).toBe('TERMES_INTERDITS');
    expect(refusContenu('you are a fucking idiot')).toBe('TERMES_INTERDITS');
  });

  it('refuse les mots haineux', () => {
    expect(refusContenu('sale nègre')).toBe('TERMES_INTERDITS');
    expect(refusContenu('les pédés')).toBe('TERMES_INTERDITS');
  });

  it('refuse les liens et les numéros, vecteurs des arnaques aux coupons', () => {
    expect(refusContenu('coupon sûr sur https://exemple.test')).toBe('LIEN_INTERDIT');
    expect(refusContenu('rejoins t.me/coupons')).toBe('LIEN_INTERDIT');
    expect(refusContenu('va sur megapronos.com')).toBe('LIEN_INTERDIT');
    expect(refusContenu('écris-moi au +226 70 12 34 56')).toBe('TELEPHONE_INTERDIT');
    expect(refusContenu('WhatsApp 70123456')).toBe('TELEPHONE_INTERDIT');
  });

  it('laisse passer les messages honnêtes', () => {
    for (const message of [
      'Putain de match, quel retournement !',
      'Le match a commencé en retard à cause de la pluie',
      'Cotes 1.85 / 3.40 / 4.20, je pars sur le nul',
      'Score final 2-1, bien vu l\'analyste',
      'J\'ai misé 10 000 FCFA sur le 1N2',
      'Analyse solide, merci. Confiance 4/5 méritée.',
      'Great call on the away win, well done',
      'Le gardien a fait un baiser au poteau',
    ]) {
      expect(refusContenu(message)).toBeNull();
    }
  });

  it('la normalisation réduit les déguisements courants', () => {
    expect(normaliser('C0NNNARD!!')).toBe('conard');
    expect(normaliser('Enculé')).toBe('encule');
  });
});
