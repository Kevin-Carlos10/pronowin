import { validerUssd, MARQUEURS_USSD } from '../services/payment_method.service';

/**
 * Le code USSD que l'abonné compose pour payer.
 *
 * ── Ce que cette fonctionnalité ajoute, et le risque qu'elle porte ────────
 *
 * L'écran de paiement affichait un numéro à recopier. Il affiche désormais,
 * quand l'opérateur en a un, le code complet — « *144*10*45568158*6000# » —
 * que l'abonné compose directement.
 *
 * Le modèle est saisi dans l'administration parce qu'il varie d'un opérateur à
 * l'autre. C'est précisément ce qui le rend dangereux : un administrateur qui
 * recopie le numéro de réception dans le modèle obtient quelque chose qui
 * fonctionne le jour même.
 *
 * Et qui devient faux dès que le numéro change dans `phone`, **sans que rien
 * ne le signale**. Le code composerait, aboutirait, et l'argent partirait chez
 * quelqu'un d'autre. Il n'y a pas d'erreur à attraper, pas de journal à
 * relire : le versement réussit, simplement pas au bon endroit. C'est la seule
 * erreur de cet écran qui ne se rattrape pas.
 *
 * D'où l'interdiction d'écrire une longue suite de chiffres : le numéro doit
 * venir de `{numero}`, donc de la table, qui reste sa source unique.
 */
describe('modèle de code USSD', () => {
  describe('ce qui est accepté', () => {
    it('le code Orange Money, avec ses deux marqueurs', () => {
      expect(validerUssd('*144*10*{numero}*{montant}#'))
        .toBe('*144*10*{numero}*{montant}#');
    });

    it('un code sans montant — tous les opérateurs n\'en prennent pas', () => {
      expect(validerUssd('*555*{numero}#')).toBe('*555*{numero}#');
    });

    it('un code commençant par dièse', () => {
      expect(validerUssd('#150*{numero}*{montant}#')).toBe('#150*{numero}*{montant}#');
    });

    it('les espaces autour sont retirés', () => {
      expect(validerUssd('  *144*{numero}#  ')).toBe('*144*{numero}#');
    });
  });

  describe('l\'absence de modèle est une réponse, pas une erreur', () => {
    // Tous les opérateurs n'ont pas de code composable, et l'écran doit alors
    // afficher le numéro seul — comme il le faisait avant cette fonctionnalité.
    it.each([null, undefined, '', '   '])('%p donne null', (valeur) => {
      expect(validerUssd(valeur as string | null | undefined)).toBeNull();
    });
  });

  describe('le numéro ne peut pas être écrit à la main', () => {
    it('un numéro complet est refusé', () => {
      expect(() => validerUssd('*144*10*22645568158*{montant}#'))
        .toThrow(/numéro écrit à la main/);
    });

    it('un numéro local aussi — huit chiffres suffisent', () => {
      // C'est la forme la plus tentante : c'est exactement ce que l'écran
      // affiche, donc ce qu'on recopie.
      expect(() => validerUssd('*144*10*45568158*{montant}#'))
        .toThrow(/numéro écrit à la main/);
    });

    it('mais les préfixes courts restent permis', () => {
      // « 144 », « 10 » : ce sont les codes du service de l'opérateur, pas des
      // numéros d'abonné. Les interdire rendrait la fonctionnalité inutile.
      expect(validerUssd('*144*10*{numero}*{montant}#')).not.toBeNull();
      expect(validerUssd('*1234567*{numero}#')).not.toBeNull();
    });

    it('le message dit quoi faire, pas seulement ce qui est refusé', () => {
      expect(() => validerUssd('*144*45568158#')).toThrow(/\{numero\}/);
    });
  });

  describe('ce qui serait affiché tel quel est refusé', () => {
    it('un marqueur inconnu', () => {
      // Il ne serait pas remplacé : l'abonné verrait « {somme} » au milieu du
      // code et composerait quelque chose d'invalide.
      expect(() => validerUssd('*144*{numero}*{somme}#'))
        .toThrow(/Marqueur inconnu/);
    });

    it('des lettres hors marqueur', () => {
      expect(() => validerUssd('*144*ORANGE*{numero}#'))
        .toThrow(/chiffres/);
    });

    it('ce qui ne ressemble pas à un code USSD', () => {
      expect(() => validerUssd('144*{numero}#')).toThrow(/commence par/);
      expect(() => validerUssd('*144*{numero}')).toThrow(/termine par/);
    });

    it('un code interminable', () => {
      expect(() => validerUssd('*' + '1*'.repeat(40) + '#')).toThrow(/trop long/);
    });
  });

  describe('les marqueurs sont une liste fermée', () => {
    it('elle ne contient que ce que l\'application sait remplacer', () => {
      // Ajouter un marqueur ici sans l'implémenter côté mobile le laisserait
      // s'afficher littéralement dans le code composé.
      expect([...MARQUEURS_USSD]).toEqual(['{numero}', '{montant}']);
    });
  });
});
