import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/parametres/presentation/providers/sessions_provider.dart';
import 'package:pronowin/features/parametres/presentation/widgets/sessions_sheet.dart';
import 'aides/banc_ecran.dart';

void main() {
  setUpAll(preparerBanc);
  for (final sombre in [false, true]) {
    testWidgets('Sessions lisibles à 320px et texte 180%, sombre=$sombre', (
      tester,
    ) async {
      final result = await mesurerEcran(
        tester,
        ecran: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(height: 560, child: SessionsSheet()),
          ),
        ),
        theme: sombre ? AppTheme.dark : AppTheme.light,
        echelle: 1.8,
        largeur: 320,
        surcharges: [
          sessionsAppareilsProvider.overrideWith(
            (ref) async => [
              SessionAppareil(
                id: 'courant',
                plateforme: 'ios',
                actuelle: true,
                debut: DateTime(2026, 10, 1),
                derniereActivite: DateTime(2026, 10, 10, 13, 35),
              ),
              const SessionAppareil(id: 'autre', plateforme: 'android'),
              const SessionAppareil(id: 'ancien'),
            ],
          ),
        ],
        verifier: () {
          expect(find.text('Cet appareil'), findsOneWidget);
          expect(find.text('Appareil iOS'), findsOneWidget);
        },
      );
      expect(result.debordements, isEmpty);
      expect(result.autres, isEmpty);
    });
  }
  testWidgets('Une erreur propose de réessayer sans inventer un appareil', (
    tester,
  ) async {
    final result = await mesurerEcran(
      tester,
      ecran: const Scaffold(
        body: SizedBox(height: 600, child: SessionsSheet()),
      ),
      theme: AppTheme.light,
      echelle: 1,
      surcharges: [
        sessionsAppareilsProvider.overrideWith(
          (ref) async => throw Exception('offline'),
        ),
      ],
      verifier: () {
        expect(find.text('Cet appareil'), findsNothing);
        expect(find.byIcon(Icons.refresh_rounded), findsWidgets);
      },
    );
    expect(result.debordements, isEmpty);
    expect(result.autres, isEmpty);
  });
}
