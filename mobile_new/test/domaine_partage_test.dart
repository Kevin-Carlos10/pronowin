import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/constants/app_constants.dart';

/// Le domaine des liens partagés, écrit une seule fois.
///
/// Il l'était trois fois, et il nommait `pronowin.app` — un domaine qui
/// n'existe pas. Vérifié depuis le serveur lui-même : injoignable en racine
/// comme en API. Chaque partage envoyait donc les gens dans le vide, sur le
/// canal de croissance le plus naturel de cette application.
///
/// Ce n'est pas une constante comme les autres. Un lien partagé vit pour
/// toujours dans une conversation WhatsApp : le jour où l'on change de domaine,
/// tout ce qui a déjà été envoyé meurt. C'est le seul endroit de l'application
/// où changer d'avis coûte cher — d'où un contrôle.
void main() {
  final lib = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  /// Un fichier sans ses commentaires : ils citent l'ancien domaine pour
  /// expliquer le défaut, et un contrôle qui se valide sur sa propre prose ne
  /// contrôle rien. La leçon a déjà été apprise deux fois cette semaine.
  String codeSeul(File f) => f
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .join('\n');

  group('domaine public', () {
    test('la constante nomme le domaine réellement servi', () {
      expect(AppConstants.domaine, 'pronowin.space');
      expect(AppConstants.siteUrl, 'https://pronowin.space');
    });

    test('plus aucune mention du domaine mort', () {
      // `com.pronowin.app` est l'identifiant de paquet Android, pas un
      // domaine — il ressemble au domaine mort et n'a rien à voir. Ma première
      // version l'attrapait : une assertion trop large accuse le code correct
      // au lieu de trouver le défaut.
      final domaineMort = RegExp(r'(?<!com\.)\bpronowin\.app\b');

      final fautifs = <String>[];
      for (final f in lib) {
        if (domaineMort.hasMatch(codeSeul(f))) {
          fautifs.add(f.path.replaceAll(RegExp(r'\\'), '/'));
        }
      }

      expect(fautifs, isEmpty,
        reason: 'domaine mort encore mentionné :\n${fautifs.join('\n')}');
    });

    test('l\'identifiant de paquet Android n\'a pas été touché', () {
      // Le contre-test. `com.pronowin.app` ressemble au domaine mort et n'a
      // rien à voir : le renommer casserait la fiche Play et l'achat intégré.
      final constantes = File('lib/core/constants/app_constants.dart')
          .readAsStringSync();

      expect(constantes, contains('id=com.pronowin.app'));
    });

    test('aucun écran ne réécrit le domaine à la main', () {
      // Trois fichiers l'écrivaient. La forme littérale ne doit plus exister
      // ailleurs que dans la constante.
      final fautifs = <String>[];
      for (final f in lib) {
        if (f.path.endsWith('app_constants.dart')) continue;
        final code = codeSeul(f);
        if (RegExp("'pronowin\\.space'").hasMatch(code) ||
            RegExp("https://pronowin\\.space").hasMatch(code)) {
          fautifs.add(f.path.replaceAll(RegExp(r'\\'), '/'));
        }
      }

      expect(fautifs, isEmpty,
        reason: 'domaine réécrit au lieu d\'être lu :\n${fautifs.join('\n')}');
    });
  });
}
