import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// La session doit survivre à ce qui est normal.
///
/// Symptôme rapporté : « je redémarre le téléphone et le compte se déconnecte ».
/// Deux causes, indépendantes, et le même geste dans les deux cas — effacer les
/// identifiants au lieu de les réutiliser.
///
/// **1. Le jeton d'accès expiré effaçait tout.**
/// `isLoggedIn()` décodait le jeton d'accès et, s'il était périmé, appelait
/// `deleteAll()` — donc supprimait aussi le jeton de rafraîchissement. Or le
/// premier vit quinze minutes et le second trente jours : le second existe
/// exactement pour survivre au premier. Fermer l'application un quart d'heure
/// suffisait à perdre la session. Après un redémarrage, c'était systématique.
///
/// **2. Une coupure réseau effaçait tout.**
/// `_doRefresh()` appelait `deleteAll()` dans un `catch (e)` sans condition. Un
/// délai dépassé, une absence de réseau — le cas le plus probable juste après un
/// démarrage d'Android — détruisait la session définitivement : plus de jetons,
/// donc rien à restaurer au retour de la connexion.
///
/// Le point commun mérite d'être nommé : dans les deux cas, un état
/// **récupérable** était traité comme une invalidation définitive.
void main() {
  String sansCommentaires(String chemin) => File(chemin)
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .join('\n');

  final depot = sansCommentaires(
      'lib/features/auth/data/repositories/auth_repository_impl.dart');
  final reseau = sansCommentaires('lib/core/network/dio_client.dart');

  group('un jeton d\'accès expiré ne détruit pas la session', () {
    test('le jeton de rafraîchissement est consulté en premier', () {
      final debut = depot.indexOf('Future<bool> isLoggedIn()');
      expect(debut, greaterThan(-1));
      final fin = depot.indexOf('\n  @override', debut + 1);
      final corps = depot.substring(debut, fin == -1 ? depot.length : fin);

      final posRefresh = corps.indexOf('refreshTokenKey');
      final posAccess  = corps.indexOf('accessTokenKey');

      expect(posRefresh, greaterThan(-1),
        reason: 'sans cette lecture, une session renouvelable passe pour morte');
      expect(posRefresh, lessThan(posAccess),
        reason: 'le renouvelable doit être vu avant le périmé');
      expect(corps, contains('if (refresh != null && refresh.isNotEmpty) return true;'));
    });

    test('l\'effacement n\'a lieu qu\'en dernier recours', () {
      final debut = depot.indexOf('Future<bool> isLoggedIn()');
      final fin = depot.indexOf('\n  @override', debut + 1);
      final corps = depot.substring(debut, fin == -1 ? depot.length : fin);

      // Un seul `deleteAll` subsiste, et il est placé après le retour
      // anticipé qui protège les sessions renouvelables.
      expect('deleteAll'.allMatches(corps).length, 1);
      expect(corps.indexOf('return true;'),
             lessThan(corps.indexOf('deleteAll')));
    });
  });

  group('une coupure réseau ne détruit pas la session', () {
    test('l\'effacement exige un refus explicite du serveur', () {
      // Le cœur du correctif : distinguer « le serveur me refuse » de
      // « le serveur ne répond pas ».
      expect(reseau, contains('final refuse = e is DioException'));
      expect(reseau, contains('e.response != null'));
      expect(reseau, contains('statusCode == 401 || e.response!.statusCode == 403'));
    });

    test('le catch ne peut plus effacer sans condition', () {
      final debut = reseau.indexOf('Future<bool> _doRefresh()');
      expect(debut, greaterThan(-1));
      final corps = reseau.substring(debut);

      // Chaque `deleteAll` de cette méthode doit être gouverné par `refuse`.
      final posRefuse = corps.indexOf('if (refuse)');
      final posDelete = corps.indexOf('deleteAll');

      expect(posRefuse, greaterThan(-1));
      expect(posRefuse, lessThan(posDelete),
        reason: 'l\'effacement doit être sous condition, pas au fil du catch');
    });

    test('l\'échec réseau ne rétrograde pas non plus en invité', () {
      final debut = reseau.indexOf('Future<bool> _doRefresh()');
      final corps = reseau.substring(debut);

      // `_onRefreshFailed` bascule l'interface en mode invité. Il ne doit
      // s'exécuter que sur un refus, sinon une simple coupure fait disparaître
      // le compte à l'écran.
      final blocRefus = corps.substring(
          corps.indexOf('if (refuse)'),
          corps.indexOf('} else {', corps.indexOf('if (refuse)')));

      expect(blocRefus, contains('_onRefreshFailed()'));
      // `_onRefreshFailed();` avec le point-virgule : c'est un appel. La
      // déclaration s'écrit `void _onRefreshFailed() {` et ne doit pas compter —
      // ma première version la comptait et attendait donc un appel de moins.
      expect(RegExp(r'_onRefreshFailed\(\);').allMatches(corps).length, 2,
        reason: 'un appel pour l\'absence de jeton, un pour le refus — '
                'pas un troisième au fil du catch');
    });
  });
}
