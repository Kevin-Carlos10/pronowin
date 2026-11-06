import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/services/prono_share_service.dart';

import 'aides/code_seul.dart';

/// Sur iPhone, l'image d'un pronostic partagé n'arrivait pas.
///
/// Le PNG et le message partaient ensemble. Android remet les deux ; sur iOS,
/// la feuille de partage les présente comme deux éléments, et WhatsApp — comme
/// d'autres — n'en garde qu'un : le texte. Le destinataire recevait le lien
/// sans la carte. Sur iOS, le fichier part donc seul.
void main() {
  test('iOS : le fichier part sans texte', () {
    expect(PronoShareService.texteAvecFichiers('Pronostic', TargetPlatform.iOS), isNull);
  });

  test('Android : le texte accompagne toujours l\'image', () {
    expect(PronoShareService.texteAvecFichiers('Pronostic', TargetPlatform.android), 'Pronostic');
  });

  test('tout partage de fichier passe par cette règle', () {
    // Un `Share.shareXFiles` appelé directement ailleurs referait l'erreur :
    // c'est ce qu'il faisait dans l'historique (export CSV).
    final fautes = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('prono_share_service.dart')) continue;
      if (f.readAsStringSync().pipeCodeSeul().contains('shareXFiles(')) fautes.add(f.path);
    }
    expect(fautes, isEmpty, reason: 'passer par PronoShareService.partagerFichiers');
  });
}
