import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';
import 'package:pronowin/features/accueil/presentation/pages/accueil_page.dart';
import 'package:pronowin/features/accueil/presentation/providers/accueil_provider.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';

import 'aides/banc_ecran.dart';

/// L'accueil entier, à 360 px, texte agrandi à 180 %, dans les deux thèmes.
///
/// ── Ce qui débordait ──────────────────────────────────────────────────────
///
/// Les bancs de débordement existants rendaient des composants isolés : la
/// carte de match, les widgets partagés. L'accueil, lui, n'était jamais
/// assemblé. À 360 px et 180 % — le plafond que `main.dart` laisse au réglage
/// système — six éléments y débordaient : l'en-tête (hauteur et marge haute
/// fixes), « Plan Gratuit · Passer Premium ✨ », les carrousels, le nom de la
/// ligue de la carte « Top du jour », la date du prochain match.
///
/// Le banc (`aides/banc_ecran.dart`) charge la vraie police et un téléphone à
/// encoche ; ici, un compte gratuit connecté — celui qui voit le plus de
/// contenu.
void main() {
  setUpAll(preparerBanc);

  for (final (nomTheme, theme) in [('clair', AppTheme.light), ('sombre', AppTheme.dark)]) {
    for (final echelle in [1.0, 1.8]) {
      testWidgets('accueil · $nomTheme · texte ${(echelle * 100).round()} % · 360 px',
          (tester) async {
        final r = await mesurerEcran(tester,
            ecran: const AccueilPage(), theme: theme, echelle: echelle,
            surcharges: _donnees(), defilements: 12);
        expect(r.autres, isEmpty, reason: 'erreurs de rendu autres que des débordements');
        expect(r.debordements, isEmpty);
      });
    }
  }
}

List<Override> _donnees() => [
      lastPronosSyncProvider.overrideWithValue(null),
      isServingFromCacheProvider.overrideWithValue(false),
      currentSubscriptionProvider.overrideWith((ref) async => {'plan': 'free', 'days_left': 0}),
      pronosticsJourProvider.overrideWith((ref) async => [
            pronoApi('1', status: 'live', dans: const Duration(minutes: -30)),
            pronoApi('2'),
            pronoApi('3', dans: const Duration(hours: 3)),
          ]),
      nextPronosticProvider.overrideWith((ref) async => pronoApi('2')),
      statsJourProvider.overrideWith((ref) async =>
          {'winRate': 64, 'streak': 3, 'upcoming': 5, 'publishedToday': 6, 'totalFinished': 28}),
      performance30Provider.overrideWith((ref) async => {'total': 30, 'wins': 18, 'roi': 12.4}),
      hierProvider.overrideWith((ref) async => const []),
      actualitesProvider.overrideWith((ref) async => const []),
      favoritesListProvider.overrideWith((ref) async => const []),
      bankrollProvider.overrideWith((ref) async => BankrollData(
            id: 'b', totalBudget: 1000000, currentBalance: 997000, currency: 'XOF',
            bets: const [],
          )),
    ];
