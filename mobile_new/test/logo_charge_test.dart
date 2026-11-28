import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/config/bookmaker_affiliation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('le fichier declare dans la constante existe reellement', () async {
    // Un chemin faux ne casse rien : `errorBuilder` affiche le repli texte, et
    // la tuile reste presentable. Personne ne remarque que le logo officiel
    // n'est jamais parti en production.
    final data = await rootBundle.load(BookmakerAffiliation.logo);
    expect(data.lengthInBytes, greaterThan(1000));
  });
}
