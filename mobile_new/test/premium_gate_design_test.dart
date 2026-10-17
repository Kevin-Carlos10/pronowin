import 'package:pronowin/features/abonnement/presentation/providers/iap_provider.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/shared/widgets/premium_gate_sheet.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';
import 'package:pronowin/features/pronostics/presentation/providers/bilan_premium_provider.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'aides/banc_ecran.dart';

void main() {
  setUpAll(preparerBanc);
  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('Premium dark=$dark scale=$scale', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...donneesCommunes(),
                  iapProductsProvider.overrideWithValue(const []),
              currentSubscriptionProvider.overrideWith(
                (ref) async => <String, dynamic>{},
              ),
              bilanPremiumProvider.overrideWith((ref) async => null),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: dark ? AppTheme.dark : AppTheme.light,
                locale: const Locale('fr'),
                supportedLocales: AppStrings.supportedLocales,
                localizationsDelegates: const [
                  AppStrings.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                ],
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showPremiumGateSheet(
                        context,
                        matchLabel: 'Arsenal vs Leeds United',
                      ),
                      child: const Text('Ouvrir'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Ouvrir'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Découvrir les offres Premium'), findsOneWidget);
        expect(find.text('Arsenal vs Leeds United'), findsOneWidget);
        if (!dark && scale == 1 && Platform.environment['PRONOWIN_CAPTURE'] != null) {
          await tester.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(Platform.environment['PRONOWIN_CAPTURE']!).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Fermer'));
        await tester.pumpAndSettle();
        expect(find.text('Découvrir les offres Premium'), findsNothing);
      });
    }
  }
}
