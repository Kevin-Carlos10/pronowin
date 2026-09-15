import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// L'icône des notifications est celle de PronoWin, et elle est monochrome.
///
/// Elle affichait **le logo de Flutter**. Deux causes empilées :
///
///  1. `@mipmap/ic_launcher` est resté le fichier par défaut du jour de
///     création du projet. L'application, elle, déclare
///     `@mipmap/launcher_icon` — le trophée. Le manifeste et l'initialisation
///     des notifications locales pointaient tous deux sur le mauvais.
///
///  2. Corriger le nom n'aurait pas suffi. Depuis Android 5, la petite icône
///     d'une notification est rendue **en silhouette** : le système ne garde
///     que le canal alpha. Une icône de lanceur, dont le fond orange est
///     opaque, y devient un carré blanc uni.
///
/// Rien de tout cela n'apparaît à la compilation, ni dans l'application : le
/// défaut ne se voit que dans le volet des notifications, c'est-à-dire sur
/// l'écran de quelqu'un d'autre.
void main() {
  final manifeste = File('android/app/src/main/AndroidManifest.xml');
  final fcm = File('lib/features/notifications/presentation/providers/'
                   'fcm_service.dart');

  /// Le fichier sans ses commentaires : ils citent l'ancienne ressource pour
  /// expliquer le défaut, et un contrôle qui se valide sur sa propre prose ne
  /// contrôle rien.
  String sansCommentaires(File f) {
    return f.readAsStringSync()
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
  }

  group('icône de notification', () {
    test('le manifeste ne pointe plus sur le logo Flutter', () {
      final xml = sansCommentaires(manifeste);

      expect(xml, contains('default_notification_icon'));
      expect(xml.contains('@mipmap/ic_launcher'), isFalse,
        reason: 'ic_launcher.png est le logo Flutter par défaut du projet');
      expect(xml, contains('@drawable/ic_notification'));
    });

    test('les notifications locales utilisent la même icône', () {
      // Deux réglages distincts pour une même icône : le manifeste sert les
      // notifications reçues en arrière-plan, cette initialisation celles que
      // l'application affiche elle-même. Corriger l'un sans l'autre laisse la
      // moitié des notifications au logo Flutter.
      final src = sansCommentaires(fcm);

      expect(src.contains('@mipmap/ic_launcher'), isFalse);
      expect(src, contains('@drawable/ic_notification'));
    });

    test('l\'icône existe à toutes les densités', () {
      const densites = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
      final manquantes = <String>[];

      for (final d in densites) {
        final f = File('android/app/src/main/res/drawable-$d/ic_notification.png');
        if (!f.existsSync()) manquantes.add(d);
      }

      expect(manquantes, isEmpty,
        reason: 'densités absentes : ${manquantes.join(', ')} — Android '
                'redimensionnerait depuis une autre, en la floutant');
    });

    test('la couleur de teinte est déclarée', () {
      // Sans elle, Android repeint la silhouette dans un gris neutre.
      final couleurs = File('android/app/src/main/res/values/'
                            'couleurs_notification.xml');

      expect(couleurs.existsSync(), isTrue);
      expect(couleurs.readAsStringSync(), contains('couleur_notification'));
      expect(sansCommentaires(manifeste), contains('default_notification_color'));
    });
  });
}
