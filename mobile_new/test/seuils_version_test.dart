import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/services/version_service.dart';

/// Qui apprend qu'une nouvelle version existe.
///
/// ── Pourquoi ce banc existe ───────────────────────────────────────────────
///
/// Le canal direct n'a aucun magasin derrière lui : un APK installé depuis le
/// site ne se met jamais à jour tout seul. La seule chose qui prévient un
/// utilisateur, c'est cette comparaison. Si elle se trompe, personne n'est
/// alerté et rien ne le signale — ni à l'écran, ni dans les journaux. Le
/// défaut est parfaitement silencieux.
///
/// Au moment où ce banc est écrit, la production sert la 1.0.12 avec un seuil
/// minimum à 1.0.9, et des installations en 1.0.9 comme en 1.0.11 tournent
/// chez de vrais utilisateurs.
///
/// ── Le piège précis ───────────────────────────────────────────────────────
///
/// `1.0.9` contre `1.0.12` est le cas où une comparaison de chaînes donne la
/// mauvaise réponse : lexicalement `"9" > "1"`, donc `"1.0.9" > "1.0.12"`. Un
/// utilisateur en 1.0.9 serait déclaré **en avance** sur la dernière version,
/// et ne verrait jamais la mise à jour.
///
/// Tant que les versions restaient à un chiffre, une comparaison de chaînes et
/// une comparaison numérique donnaient le même résultat. Le passage à 1.0.10 a
/// fait diverger les deux pour toujours, sans rien changer d'observable le
/// jour où c'est arrivé.
void main() {
  ({bool obligatoire, bool disponible}) verdict({
    required String courante,
    String min = '1.0.9',
    String latest = '1.0.12',
    bool force = false,
  }) =>
      VersionService.decider(
          courante: courante, min: min, latest: latest, force: force);

  group('les seuils réellement en production', () {
    test('une installation 1.0.11 se voit proposer la 1.0.12', () {
      final v = verdict(courante: '1.0.11');
      expect(v.disponible, isTrue);
      expect(v.obligatoire, isFalse, reason: 'APK_FORCE_UPDATE vaut false');
    });

    test('une installation 1.0.9 aussi — deux chiffres contre un', () {
      // Le cas qui distingue une comparaison numérique d'une comparaison de
      // chaînes. Lexicalement, "1.0.9" passe pour supérieur à "1.0.12".
      expect(verdict(courante: '1.0.9').disponible, isTrue);
    });

    test('1.0.9 est au seuil minimum, donc pas enfermée', () {
      // Être *égal* au minimum n'est pas être en dessous. La confondre
      // bloquerait derrière un écran sans issue exactement les utilisateurs
      // que le seuil était censé laisser passer.
      expect(verdict(courante: '1.0.9').obligatoire, isFalse);
    });

    test('une installation 1.0.8 est sous le minimum, elle est bloquée', () {
      expect(verdict(courante: '1.0.8').obligatoire, isTrue);
    });

    test('la 1.0.12 elle-même ne se voit rien proposer', () {
      final v = verdict(courante: '1.0.12');
      expect(v.disponible, isFalse);
      expect(v.obligatoire, isFalse);
    });

    test('le numéro de build ne compte pas dans l\'ordre', () {
      // `pkg.version` peut arriver sous la forme `1.0.12+13`.
      expect(verdict(courante: '1.0.12+13').disponible, isFalse);
    });
  });

  group('la comparaison est numérique, position par position', () {
    test('10 est après 9, à chaque rang', () {
      expect(verdict(courante: '1.0.9', latest: '1.0.10').disponible, isTrue);
      expect(verdict(courante: '1.9.0', latest: '1.10.0').disponible, isTrue);
      expect(verdict(courante: '9.0.0', latest: '10.0.0').disponible, isTrue);
    });

    test('et elle ne se trompe pas de sens', () {
      expect(verdict(courante: '1.0.12', latest: '1.0.9').disponible, isFalse);
      expect(verdict(courante: '1.10.0', latest: '1.9.0').disponible, isFalse);
    });

    test('une version courte vaut la même complétée par des zéros', () {
      expect(verdict(courante: '1.0', latest: '1.0.0').disponible, isFalse);
      expect(verdict(courante: '1.0', latest: '1.0.1').disponible, isTrue);
    });
  });

  group('force ne bloque que s\'il y a où aller', () {
    // Régression déjà corrigée une fois, et qui avait enfermé tout le monde :
    // `force` activé alors que chacun était à jour affichait une fenêtre sans
    // issue, dont l'unique bouton retéléchargeait la version installée.
    test('tout le monde à jour : force ne bloque personne', () {
      final v = verdict(courante: '1.0.12', latest: '1.0.12', force: true);
      expect(v.disponible, isFalse);
      expect(v.obligatoire, isFalse);
    });

    test('une version en retard : force bloque', () {
      expect(verdict(courante: '1.0.11', force: true).obligatoire, isTrue);
    });
  });
}
