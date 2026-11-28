import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/config/contact_support.dart';

/// Une seule adresse par canal, et elle vit dans `ContactSupport`.
///
/// La classe se présente comme la « source unique ». Elle ne l'était que dans
/// l'application : le Telegram y valait `t.me/carlospronost` — un canal
/// personnel — pendant que le site vitrine renvoyait vers `t.me/pronowin2026`,
/// celui qui porte la marque, sa description et son logo. Les deux vitrines de
/// la même application envoyaient les utilisateurs à deux endroits différents.
///
/// Le lien Facebook, lui, était resté écrit en dur dans l'écran Paramètres —
/// c'est-à-dire dans la position exacte qu'occupait le Telegram le jour où il
/// a divergé.
///
/// Ce contrôle ne peut pas comparer l'application au site : ce sont deux
/// projets. Il garde ce qu'il peut garder — qu'aucune adresse ne reparte vivre
/// ailleurs dans l'application.
void main() {
  test('le canal Telegram est celui de la marque', () {
    expect(ContactSupport.telegram, 'https://t.me/pronowin2026',
      reason: 'le site vitrine renvoie vers ce canal : deux adresses '
              'divergentes, c\'est celle qui n\'est plus relevée qui reçoit '
              'les demandes');
  });

  test('aucun lien de contact n\'est écrit en dur ailleurs', () {
    // Les motifs sont ceux des canaux réellement utilisés. Le fichier qui
    // porte la règle est évidemment exclu.
    final motifs = <String>['t.me/', 'whatsapp.com/', 'facebook.com/'];
    const source = 'lib/core/config/contact_support.dart';

    final fautes = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.replaceAll('\\', '/').endsWith(source)) continue;

      final lignes = f.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        final ligne = lignes[i];
        // Les commentaires citent les adresses pour expliquer l'histoire.
        if (ligne.trimLeft().startsWith('//')) continue;
        // `t.me/share/url` est l'endpoint de partage de Telegram, pas une
        // adresse de canal : il ne désigne personne et n'a donc rien à
        // centraliser. Le contrôle l'avait signalé — un garde-fou qui accuse
        // du code correct finit désarmé plutôt que corrigé.
        if (ligne.contains('t.me/share/')) continue;
        for (final m in motifs) {
          if (ligne.contains(m)) {
            fautes.add('${f.path}:${i + 1} ${ligne.trim()}');
          }
        }
      }
    }

    expect(fautes, isEmpty,
      reason: 'une adresse de contact vit hors de ContactSupport : elle '
              'divergera, et personne ne le verra avant qu\'un utilisateur '
              'écrive dans le vide');
  });
}
