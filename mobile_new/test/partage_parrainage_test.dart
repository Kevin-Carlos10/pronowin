import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/shared/utils/partage_parrainage.dart';

/// « Partager mon code dans parrainage ne marche pas » (20 octobre 2026) :
/// les trois options de la page ne faisaient que copier le texte. Le bouton
/// ouvre désormais la feuille de partage du téléphone, ancrée sur lui —
/// sans ancrage, iOS la refuse sur iPad.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canal = MethodChannel('dev.fluttercommunity.plus/share');
  late List<MethodCall> appels;
  String? presse;

  setUp(() {
    appels = [];
    presse = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform, (c) async {
        if (c.method == 'Clipboard.setData') presse = (c.arguments as Map)['text'] as String?;
        return null;
      });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> monter(WidgetTester t) => t.pumpWidget(MaterialApp(home: Scaffold(body: Center(
    child: Builder(builder: (bouton) => ElevatedButton(
      onPressed: () => partagerParrainage(bouton, 'ABC123'),
      child: const Text('Partager mon code'))),
  ))));

  testWidgets('ouvre la feuille de partage, avec le message et un ancrage sur le bouton', (t) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (c) async {
      appels.add(c); return 'dev.fluttercommunity.plus/share/unavailable';
    });
    await monter(t);
    await t.tap(find.text('Partager mon code'));
    await t.pump();
    expect(appels.map((c) => c.method), ['share']);
    final p = appels.single.arguments as Map;
    expect(p['text'], allOf(contains('ABC123'), contains('https://')));
    final bouton = t.getRect(find.byType(ElevatedButton));
    expect([p['originX'], p['originY'], p['originWidth'], p['originHeight']],
        [bouton.left, bouton.top, bouton.width, bouton.height]);
    expect(presse, isNull);
  });

  testWidgets('la feuille ne peut pas s\'ouvrir : le message est copié, et on le dit', (t) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (c) async {
      throw PlatformException(code: 'indisponible');
    });
    await monter(t);
    await t.tap(find.text('Partager mon code'));
    await t.pump();
    await t.pump();
    expect(presse, contains('ABC123'));
    expect(find.text('Message copié : colle-le dans WhatsApp, un SMS…'), findsOneWidget);
  });

  test('la page Parrainage et la page Compte partagent par la feuille du téléphone', () {
    for (final chemin in [
      'lib/features/parrainage/presentation/pages/parrainage_page.dart',
      'lib/features/compte/presentation/pages/compte_page.dart',
    ]) {
      final source = File(chemin).readAsStringSync();
      expect(source, contains('partagerParrainage('), reason: chemin);
      expect(source, isNot(contains('Share.share(')), reason: '$chemin : partage sans ancrage');
    }
    expect(File('lib/features/parrainage/presentation/pages/parrainage_page.dart').readAsStringSync(),
        isNot(contains('_showShareSheet')));
  });
}
