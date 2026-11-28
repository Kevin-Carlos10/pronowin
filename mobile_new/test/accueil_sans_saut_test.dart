import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/abonnement/presentation/providers/subscription_provider.dart';
import 'package:pronowin/features/accueil/presentation/pages/accueil_page.dart';
import 'package:pronowin/features/accueil/presentation/providers/accueil_provider.dart';
import 'package:pronowin/features/auth/domain/entities/user_entity.dart';
import 'package:pronowin/features/bankroll/presentation/providers/bankroll_provider.dart';
import 'package:pronowin/features/competitions/competitions.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:pronowin/shared/widgets/code_promo.dart';

import 'aides/banc_ecran.dart';

/// L'accueil ne saute pas pendant son chargement.
///
/// Au démarrage, chaque bloc de l'accueil attend sa propre réponse du
/// serveur, et elles arrivent dans n'importe quel ordre. Un bloc qui apparaît
/// — ou qui change de hauteur — au-dessus de ce qu'on lit déjà le pousse vers
/// le bas, sous le doigt.
///
/// Le banc fait arriver chaque réponse **en dernier**, l'une après l'autre,
/// et relève tout texte déjà affiché qui s'est déplacé à son arrivée.
void main() {
  setUpAll(preparerBanc);

  for (final (nomCompte, compte) in [('gratuit', utilisateurGratuit), ('abonné', utilisateurPremium)]) {
    for (final (nomReponses, vides) in [('réponses pleines', false), ('réponses vides', true)]) {
    for (final dernier in _Arrivees.noms) {
      testWidgets('compte $nomCompte · $nomReponses · « $dernier » arrive en dernier : rien ne bouge', (t) async {
        final arrivees = _Arrivees(vides: vides);
        await _monter(t, arrivees, compte);
        for (final nom in _Arrivees.noms) {
          if (nom != dernier) arrivees.livrer(nom);
        }
        await _laisserSePoser(t);
        final avant = _positions(t);

        arrivees.livrer(dernier);
        await _laisserSePoser(t);
        final apres = _positions(t);

        final deplaces = <String>[
          for (final MapEntry(key: texte, value: y) in avant.entries)
            if (apres[texte] != null && (apres[texte]! - y).abs() > 1)
              '« $texte » : ${y.round()} → ${apres[texte]!.round()}',
        ];
        expect(deplaces, isEmpty, reason: 'ces textes ont bougé à l\'arrivée de « $dernier »');

        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(minutes: 1));
      });
    }
    }
  }

  testWidgets('en attendant : les squelettes seuls, sans les blocs fixes du bas', (t) async {
    await _monter(t, _Arrivees(), utilisateurGratuit);
    await _laisserSePoser(t);
    expect(find.byKey(const Key('accueil-chargement')), findsOneWidget);
    expect(find.text('Grandes compétitions'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(minutes: 1));
  });

  testWidgets("une réponse qui traîne : l'accueil s'affiche quand même après quatre secondes", (t) async {
    final arrivees = _Arrivees();
    await _monter(t, arrivees, utilisateurGratuit);
    for (final nom in _Arrivees.noms) {
      if (nom != 'code promo') arrivees.livrer(nom);
    }
    await _laisserSePoser(t);
    expect(find.byKey(const Key('accueil-chargement')), findsOneWidget);
    await t.pump(attenteHautMax);
    await t.pump();
    expect(find.byKey(const Key('accueil-chargement')), findsNothing);
    expect(find.text('TOP DU JOUR'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(minutes: 1));
  });

  test('prêt quand chaque réponse attendue est arrivée, données ou erreur', () {
    expect(hautDeLAccueilPret([const AsyncData(1), null, AsyncError('x', StackTrace.empty)]), isTrue);
    expect(hautDeLAccueilPret([const AsyncData(1), const AsyncLoading<int>()]), isFalse);
    // Un rafraîchissement garde la valeur précédente : pas de retour au squelette.
    expect(hautDeLAccueilPret([const AsyncLoading<int>().copyWithPrevious(const AsyncData(1))]), isTrue);
  });
}

/// Les réponses du serveur, que le banc livre quand il le décide.
class _Arrivees {
  static const noms = [
    'pronostics du jour', 'prochain pronostic', 'chiffres du jour', 'bilan sur 30 jours', 'bilan d\'hier',
    'actualités', 'matchs suivis', 'abonnement', 'bankroll', 'code promo', 'direct des compétitions',
  ];

  /// [vides] : les réponses qui ne montrent rien — pas de bilan d'hier, pas
  /// de code promo, trop peu de pronostics pour la bande de preuve. Un bloc
  /// qui tenait sa place pendant le chargement la rendait alors, et l'écran
  /// remontait.
  _Arrivees({this.vides = false});
  final bool vides;

  final _attentes = {for (final n in noms) n: Completer<Object?>()};

  Future<T> de<T>(String nom) async => (await _attentes[nom]!.future) as T;

  void livrer(String nom) =>
      _attentes[nom]!.complete(vides && _videsDe.containsKey(nom) ? _videsDe[nom] : _valeurs[nom]);

  static final Map<String, Object?> _videsDe = {
    'bilan sur 30 jours': <String, dynamic>{'total_pronostics': 3, 'wins': 1, 'roi': -4.0},
    "bilan d'hier": const <dynamic>[],
    'code promo': null,
    'chiffres du jour': <String, dynamic>{'winRate': 0, 'streak': 0, 'upcoming': 0, 'publishedToday': 0},
  };

  static final Map<String, Object?> _valeurs = {
    'pronostics du jour': <dynamic>[
      pronoApi('2'),
      pronoApi('3', dans: const Duration(hours: 3)),
      pronoApi('4', dans: const Duration(hours: 5)),
    ],
    'prochain pronostic': pronoApi('2'),
    'chiffres du jour': <String, dynamic>{'winRate': 64, 'streak': 3, 'upcoming': 5, 'publishedToday': 6, 'totalFinished': 28},
    'bilan sur 30 jours': <String, dynamic>{'total_pronostics': 30, 'wins': 18, 'roi': 12.4},
    'bilan d\'hier': <dynamic>[
      {...pronoApi('h1', dans: const Duration(hours: -20)), 'result': 'WIN', 'status': 'finished'},
      {...pronoApi('h2', dans: const Duration(hours: -18)), 'result': 'LOSS', 'status': 'finished'},
    ],
    'actualités': const <Map<String, dynamic>>[],
    'matchs suivis': const <Map<String, dynamic>>[],
    'abonnement': <String, dynamic>{'plan': 'free', 'days_left': 0},
    'bankroll': BankrollData(id: 'b', totalBudget: 100000, currentBalance: 104500, currency: 'XOF', bets: const []),
    'code promo': const PromoPartenaire(code: 'PRONOWIN2026', nom: '1xBet', lien: ''),
    'direct des compétitions': const <MatchEntity>[],
  };
}

Future<void> _monter(WidgetTester t, _Arrivees a, UserEntity compte) async {
  SharedPreferences.setMockInitialValues({'pseudo_nudge_dismissed': true});
  t.view.physicalSize = const Size(390 * 2, 844 * 2);
  t.view.devicePixelRatio = 2;
  t.view.padding = const FakeViewPadding(top: 59 * 2, bottom: 34 * 2);
  addTearDown(t.view.reset);

  await t.pumpWidget(ProviderScope(
    overrides: [
      ...donneesCommunes(utilisateur: compte),
      lastPronosSyncProvider.overrideWithValue(null),
      isServingFromCacheProvider.overrideWithValue(false),
      pronosticsJourProvider.overrideWith((ref) => a.de<List<dynamic>>('pronostics du jour')),
      nextPronosticProvider.overrideWith((ref) => a.de<Map<String, dynamic>?>('prochain pronostic')),
      statsJourProvider.overrideWith((ref) => a.de<Map<String, dynamic>>('chiffres du jour')),
      performance30Provider.overrideWith((ref) => a.de<Map<String, dynamic>?>('bilan sur 30 jours')),
      hierProvider.overrideWith((ref) => a.de<List<dynamic>>('bilan d\'hier')),
      actualitesProvider.overrideWith((ref) => a.de<List<Map<String, dynamic>>>('actualités')),
      favoritesListProvider.overrideWith((ref) => a.de<List<Map<String, dynamic>>>('matchs suivis')),
      currentSubscriptionProvider.overrideWith((ref) => a.de<Map<String, dynamic>>('abonnement')),
      bankrollProvider.overrideWith((ref) => a.de<BankrollData?>('bankroll')),
      promoPartenaireProvider.overrideWith((ref) => a.de<PromoPartenaire?>('code promo')),
      directGrandesCompetitionsProvider.overrideWith((ref) => a.de<List<MatchEntity>>('direct des compétitions')),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const AccueilPage())],
        errorBuilder: (_, _) => const Scaffold(),
      ),
      theme: AppTheme.light,
      locale: const Locale('fr'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ),
  ));
  await t.pump();
}

/// Les animations d'entrée et les tailles animées vont à leur terme.
Future<void> _laisserSePoser(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// La position verticale de chaque texte visible à l'écran. Un même texte
/// présent plusieurs fois est numéroté dans l'ordre de l'arbre ; le compte à
/// rebours, qui change chaque seconde, est écarté.
Map<String, double> _positions(WidgetTester t) {
  final taille = t.view.physicalSize / t.view.devicePixelRatio;
  final res = <String, double>{};
  for (final e in find.byType(RichText).evaluate()) {
    final texte = (e.widget as RichText).text.toPlainText().trim();
    if (texte.isEmpty || RegExp(r'^\d{1,2}$').hasMatch(texte)) continue;
    final boite = e.renderObject;
    if (boite is! RenderBox || !boite.hasSize || !boite.attached) continue;
    final p = boite.localToGlobal(Offset.zero);
    if (p.dy < 0 || p.dy > taille.height || p.dx < 0 || p.dx > taille.width) continue;
    var cle = texte;
    var n = 1;
    while (res.containsKey(cle)) {
      cle = '$texte #${++n}';
    }
    res[cle] = p.dy;
  }
  return res;
}
