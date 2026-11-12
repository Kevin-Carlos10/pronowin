import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:pronowin/core/constants/app_constants.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/parametres/presentation/pages/reglages_sous_pages.dart';
import 'package:pronowin/shared/utils/partage_parrainage.dart';

import 'aides/banc_ecran.dart';

/// Les partages mènent à la page de téléchargement du site (11 novembre
/// 2026), avec le code de parrainage quand il y en a un : le site l'affiche,
/// à saisir à l'inscription. Ils visaient l'accueil, qui n'en faisait rien.
void main() {
  setUpAll(() async => preparerBanc());

  test('la page de téléchargement, avec ou sans code', () {
    expect(lienTelechargement(), '${AppConstants.siteUrl}/telecharger');
    expect(lienTelechargement(parrain: ''), '${AppConstants.siteUrl}/telecharger');
    expect(lienTelechargement(parrain: 'AWA226'), '${AppConstants.siteUrl}/telecharger?parrain=AWA226');
    expect(lienQrParrainage('AB C'), endsWith('/telecharger?parrain=AB+C'), reason: 'le code est encodé');
  });

  test('le message de parrainage porte le lien avec le code', () {
    expect(messageParrainage('AWA226'), contains('/telecharger?parrain=AWA226'));
    expect(messageParrainage('AWA226'), isNot(contains('.apk')));
  });

  testWidgets('le QR code de « Partager l\'application » porte le code du compte', (t) async {
    await t.pumpWidget(MaterialApp(theme: AppTheme.dark, home: const PartageQrPage(parrain: 'AWA226')));
    await t.pump();
    final qr = t.widget<QrImageView>(find.byType(QrImageView));
    expect(qr, isNotNull);
    expect(find.byKey(const Key('qr-code-parrain')), findsOneWidget);
    expect(find.text('AWA226'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('sans compte, le QR code mène à la page, sans code', (t) async {
    await t.pumpWidget(MaterialApp(theme: AppTheme.dark, home: const PartageQrPage()));
    await t.pump();
    expect(find.byKey(const Key('qr-code-parrain')), findsNothing);
    expect(find.textContaining('page de téléchargement'), findsOneWidget);
  });
}
