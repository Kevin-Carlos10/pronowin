import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// L'application n'invente pas de contenu.
///
/// Quatre articles d'actualité étaient écrits en dur :
///
///     « Coupe du Monde 2026 — Les groupes dévoilés »
///     « La FIFA a officialisé les groupes… »        Aujourd'hui
///     « Real Madrid vs Bayern et Arsenal vs PSG »   Hier
///
/// Datés en relatif, donc **jamais périmés en apparence**. C'est ce qui les
/// rendait dangereux : de l'information fabriquée sur des événements réels,
/// qu'aucun lecteur ne pouvait reconnaître comme fausse.
///
/// Et ce n'était pas un repli d'erreur. Ils sortaient aussi quand l'API
/// répondait correctement avec une liste vide — c'est-à-dire tant qu'aucune
/// actualité n'était publiée. L'état par défaut d'une installation neuve.
///
/// La distinction que ce contrôle protège : un **tarif** de repli est une
/// approximation, et l'écran le corrige dès que le serveur répond. Un
/// **article** de repli est un fait inventé, que rien ne corrige.
void main() {
  final providers = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  String codeSeul(File f) => f
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .join('\n');

  group('aucun contenu fabriqué', () {
    test('plus de liste d\'actualités écrite en dur', () {
      final f = File('lib/features/accueil/presentation/providers/'
                     'accueil_provider.dart');
      final code = codeSeul(f);

      expect(code.contains('_staticNews'), isFalse);
      // Les titres inventés, au cas où ils reviendraient sous un autre nom.
      for (final morceau in ['Coupe du Monde 2026', 'Demi-finales confirmées',
                             'Course au titre serrée']) {
        expect(code.contains(morceau), isFalse, reason: morceau);
      }
    });

    test('une liste vide reste vide', () {
      // Le défaut n'était pas seulement le contenu : c'était de substituer
      // quelque chose à une réponse **valide**. Une liste vide veut dire
      // « rien de publié », pas « échec ».
      final code = codeSeul(File('lib/features/accueil/presentation/providers/'
                                 'accueil_provider.dart'));

      expect(RegExp(r'list\.isNotEmpty\s*\?\s*list\s*:').hasMatch(code), isFalse);
      expect(code, contains('if (data == null) return const <Map<String, dynamic>>[];'));
    });

    test('aucune photo de banque d\'images ne sert de contenu', () {
      // Trois URL Unsplash accompagnaient les faux articles. Une photo de stock
      // presentée comme l'illustration d'un événement réel est du même ordre
      // que le texte inventé.
      final fautifs = <String>[];
      for (final f in providers) {
        if (codeSeul(f).contains('unsplash.com')) {
          fautifs.add(f.path.replaceAll(RegExp(r'\\'), '/'));
        }
      }

      expect(fautifs, isEmpty);
    });

    test('les dates relatives ne sont pas écrites dans des données', () {
      // « Aujourd'hui », « Hier », « Il y a 2j » écrits dans une structure de
      // données : c'est la signature d'un contenu fabriqué qui ne vieillit
      // jamais. Dans un widget qui formate une vraie date, c'est légitime.
      final fautifs = <String>[];
      for (final f in providers) {
        if (!f.path.contains('providers')) continue;
        final code = codeSeul(f);
        if (RegExp(r"'date'\s*:\s*.{0,2}(Aujourd|Hier|Il y a)").hasMatch(code)) {
          fautifs.add(f.path.replaceAll(RegExp(r'\\'), '/'));
        }
      }

      expect(fautifs, isEmpty);
    });
  });
}
