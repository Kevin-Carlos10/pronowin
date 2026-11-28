import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// Les fichiers temporaires de l'application : surtout les logos, photos et
/// images d'articles téléchargés (7 novembre 2026).
///
/// « Vider le cache » effaçait les préférences enregistrées mais pas ces
/// images, qui sont l'essentiel de la place occupée ; et la ligne ne disait
/// pas combien. Elle affiche désormais la taille, comme 1xBet (« 84,3 Mo »),
/// et le bouton libère vraiment cette place.
///
/// Le dossier d'une mise à jour en cours de téléchargement (`maj`, voir
/// `installateur_maj.dart`) n'est jamais compté ni effacé.
class CacheFichiers {
  const CacheFichiers._();

  static const _exclus = {'maj'};

  /// Le dossier temporaire ; remplaçable pour les bancs d'essai.
  static Future<Directory> Function() dossier = getTemporaryDirectory;

  static Iterable<FileSystemEntity> _contenu(Directory d) =>
      d.listSync(followLinks: false).where((e) => !_exclus.contains(e.uri.pathSegments.where((s) => s.isNotEmpty).last));

  /// Taille en octets ; 0 si le dossier est illisible.
  static Future<int> taille() async {
    try {
      final d = await dossier();
      if (!d.existsSync()) return 0;
      var total = 0;
      for (final e in _contenu(d)) {
        if (e is File) {
          total += e.lengthSync();
        } else if (e is Directory) {
          for (final f in e.listSync(recursive: true, followLinks: false).whereType<File>()) {
            total += f.lengthSync();
          }
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Efface les fichiers temporaires et les images gardées en mémoire. Un
  /// fichier en cours d'usage qui résiste est laissé : il partira la fois
  /// suivante.
  static Future<void> vider() async {
    PaintingBinding.instance.imageCache.clear();
    try {
      final d = await dossier();
      if (!d.existsSync()) return;
      for (final e in _contenu(d)) {
        try {
          e.deleteSync(recursive: true);
        } catch (_) {/* en cours d'usage */}
      }
    } catch (_) {/* dossier illisible */}
  }

  /// « 84,3 Mo », « 512 Ko », « 0 Ko » — en anglais « 84.3 MB ».
  static String lisible(int octets, {String langue = 'fr'}) {
    final en = langue == 'en';
    if (octets < 1024 * 1024) {
      return '${(octets / 1024).round()} ${en ? 'KB' : 'Ko'}';
    }
    final mo = (octets / (1024 * 1024)).toStringAsFixed(1);
    return '${en ? mo : mo.replaceAll('.', ',')} ${en ? 'MB' : 'Mo'}';
  }
}
