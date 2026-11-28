/**
 * Les résumés d'actualités : coupés à un mot entier, avec « … ».
 */
import { extraitTexte } from '../utils/extrait';

describe('extraitTexte', () => {
  it('un texte court reste tel quel', () => {
    expect(extraitTexte('  La France  bat la Belgique.  ')).toBe('La France bat la Belgique.');
    expect(extraitTexte(null)).toBe('');
  });

  it('un texte long se coupe au dernier mot entier, avec « … »', () => {
    const texte = 'La sélection affrontera la Belgique samedi soir au Stade de France';
    const r = extraitTexte(texte, 40);
    expect(r).toBe('La sélection affrontera la Belgique…');
    expect(r.length).toBeLessThanOrEqual(41);
  });

  it('pas de ponctuation orpheline avant les points de suspension', () => {
    expect(extraitTexte('Victoire nette, sans appel, des Bleus hier soir', 27)).toBe('Victoire nette, sans appel…');
  });

  it('les marques de coupure des flux deviennent « … »', () => {
    expect(extraitTexte('Le sélectionneur a tranché [...]')).toBe('Le sélectionneur a tranché…');
    expect(extraitTexte('Le sélectionneur a tranché [&#8230;]')).toBe('Le sélectionneur a tranché…');
  });

  it('un mot unique trop long est coupé quand même', () => {
    expect(extraitTexte('a'.repeat(50), 10)).toBe('a'.repeat(10) + '…');
  });
});
