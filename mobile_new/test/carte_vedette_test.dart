import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';
import 'package:pronowin/features/accueil/presentation/pages/accueil_page.dart';
import 'package:pronowin/features/accueil/presentation/providers/accueil_provider.dart';
import 'package:pronowin/features/accueil/presentation/providers/carte_vedette.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';

import 'aides/banc_ecran.dart';

/// Une seule carte en tête de l'accueil, au lieu de « Prochain match » et
/// « Top prono du jour » qui montraient souvent la même rencontre.
///
/// Règle (décision du 1er octobre 2026, option A) : le meilleur pronostic du
/// jour, avec son compte à rebours ; à défaut, le prochain match de la
/// semaine. Les badges disent pourquoi.
void main() {
  final maintenant = DateTime(2026, 10, 1, 12);

  Map<String, dynamic> prono(String id, {required int pct, required int dansHeures, String statut = 'upcoming'}) => {
        ...pronoApi(id, status: statut),
        'confidence_pct': pct,
        'match_date': maintenant.add(Duration(hours: dansHeures)).toUtc().toIso8601String(),
      };

  test('le meilleur du jour, qui est aussi le prochain : deux badges', () {
    final a = prono('a', pct: 82, dansHeures: 2);
    final b = prono('b', pct: 64, dansHeures: 5);
    final v = choisirVedette(duJour: [b, a], prochain: a, maintenant: maintenant)!;
    expect(v.prono['id'], 'a');
    expect(v.estTopDuJour, isTrue);
    expect(v.estProchainMatch, isTrue);
  });

  test('le meilleur du jour commence plus tard : il reste en tête, badge TOP seul', () {
    final tot = prono('tot', pct: 55, dansHeures: 1);
    final top = prono('top', pct: 81, dansHeures: 6);
    final v = choisirVedette(duJour: [tot, top], prochain: tot, maintenant: maintenant)!;
    expect(v.prono['id'], 'top');
    expect(v.estTopDuJour, isTrue);
    expect(v.estProchainMatch, isFalse);
  });

  test('à égalité de confiance, celui qui commence le plus tôt', () {
    final tard = prono('tard', pct: 70, dansHeures: 8);
    final tot = prono('tot', pct: 70, dansHeures: 3);
    expect(choisirVedette(duJour: [tard, tot], maintenant: maintenant)!.prono['id'], 'tot');
  });

  test('un match commencé n\'est jamais en tête : il a sa section « En direct »', () {
    final enCours = prono('live', pct: 95, dansHeures: -1, statut: 'live');
    final passe = prono('passe', pct: 90, dansHeures: -1);
    final suivant = prono('suivant', pct: 40, dansHeures: 4);
    expect(choisirVedette(duJour: [enCours, passe, suivant], maintenant: maintenant)!.prono['id'], 'suivant');
  });

  test('rien aujourd\'hui : le prochain match de la semaine, comme avant', () {
    final demain = prono('demain', pct: 60, dansHeures: 26);
    final v = choisirVedette(duJour: const [], prochain: demain, maintenant: maintenant)!;
    expect(v.prono['id'], 'demain');
    expect(v.estTopDuJour, isFalse);
    expect(v.estProchainMatch, isTrue);
  });

  test('rien du tout : pas de carte', () {
    expect(choisirVedette(duJour: const [], maintenant: maintenant), isNull);
  });

  test('un serveur ancien sans pourcentage : classé par le milieu de son palier', () {
    final niveau5 = {...prono('n5', pct: 0, dansHeures: 4)}..remove('confidence_pct');
    niveau5['confidence_score'] = 5;
    final pct60 = prono('p60', pct: 60, dansHeures: 2);
    // Niveau 5 → 90 % : il passe devant un 60 % saisi.
    expect(choisirVedette(duJour: [pct60, niveau5], maintenant: maintenant)!.prono['id'], 'n5');
  });

  group("sur l'accueil", () {
    setUpAll(preparerBanc);

    testWidgets("une seule carte en tête, et son match n'est pas répété dessous", (t) async {
      Map<String, dynamic> du(String id, String dom, String ext, int pct, int dansHeures) => {
            ...pronoApi(id),
            'home_team': dom, 'away_team': ext, 'confidence_pct': pct,
            'match_date': DateTime.now().add(Duration(hours: dansHeures)).toUtc().toIso8601String(),
          };
      final top = du('1', 'Lyon', 'Lens', 82, 2);
      final jour = [top, du('2', 'Nice', 'Brest', 64, 5), du('3', 'Lille', 'Nantes', 50, 7)];

      final r = await mesurerEcran(t,
          ecran: const AccueilPage(), theme: AppTheme.light, echelle: 1,
          surcharges: [
            lastPronosSyncProvider.overrideWithValue(null),
            isServingFromCacheProvider.overrideWithValue(false),
            currentSubscriptionProvider.overrideWith((ref) async => {'plan': 'free'}),
            pronosticsJourProvider.overrideWith((ref) async => jour),
            nextPronosticProvider.overrideWith((ref) async => top),
            statsJourProvider.overrideWith((ref) async => {'winRate': 64, 'streak': 3, 'upcoming': 3}),
            performance30Provider.overrideWith((ref) async => null),
            hierProvider.overrideWith((ref) async => const []),
            actualitesProvider.overrideWith((ref) async => const []),
            favoritesListProvider.overrideWith((ref) async => const []),
            bankrollProvider.overrideWith((ref) async => null),
          ],
          verifier: () {
            expect(find.text('TOP DU JOUR'), findsOneWidget);
            expect(find.text('PROCHAIN MATCH'), findsOneWidget);
            // L'ancienne seconde grande carte.
            expect(find.text('Top prono du jour'), findsNothing);
            // Lyon–Lens : une fois, en tête — plus dans le carrousel.
            expect(find.text('Lyon'), findsOneWidget);
            expect(find.text('Nice'), findsWidgets);
          });
      expect(r.autres, isEmpty);
    });
  });
}
