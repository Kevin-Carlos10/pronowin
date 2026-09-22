import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/domain/entities/match_entity.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/match_card_widget.dart';

/// Ce que l'application supporte réellement quand on agrandit le texte.
///
/// La borne de `main.dart` (1,3) a d'abord été choisie par estimation. Elle
/// mérite mieux : une estimation se démode au premier changement de mise en
/// page, et personne ne s'en aperçoit — un débordement ne casse rien, il
/// affiche une bande rayée jaune et noire à qui a agrandi son texte.
///
/// Ces contrôles rendent les widgets les plus répétés de l'application aux
/// échelles réelles, sur les largeurs d'écran réelles, et échouent au premier
/// dépassement. C'est une mesure, pas un avis.
void main() {
  // Sans cette initialisation, `DateFormat('dd/MM', 'fr_FR')` lève une
  // `LocaleDataException` — que le harnais comptait comme un débordement.
  // J'ai cru pendant trois mesures que la disposition « match terminé » était
  // fautive : c'était le banc d'essai. `main.dart` fait cet appel, pas les
  // tests de widget.
  setUpAll(() async => initializeDateFormatting('fr_FR'));

  MatchEntity fabriquer({
    String home = 'Real Sociedad de Fútbol',
    String away = 'Borussia Mönchengladbach',
    String league = 'UEFA Champions League',
    MatchStatus status = MatchStatus.upcoming,
    bool avecPronostic = true,
    int confiance = 4,
  }) =>
      MatchEntity(
        id: 'm1',
        league: league,
        leagueCountry: 'EU',
        homeTeam: home,
        awayTeam: away,
        matchDate: DateTime(2026, 8, 26, 19),
        status: status,
        predictionType: PredictionType.win1,
        predictionLabel: 'Real Sociedad de Fútbol gagne',
        oddsRecommended: 1.34,
        oddsHome: 1.34,
        oddsDraw: 4.5,
        oddsAway: 8.0,
        // 4, et non 80 : la confiance est une note de 1 a 5. La valeur 80
        // venait de l'epoque ou l'ecran affichait un pourcentage, et la table
        // de conversion la ramenait silencieusement a 5 par `clamp`. Le jour
        // ou la note est devenue « n/5 », elle est sortie de l'echelle et la
        // carte a debordé — le gabarit testait un etat que la production ne
        // produit pas.
        confidenceScore: confiance,
        isPremium: false,
        homeFormPoints: 9,
        awayFormPoints: 4,
        hasPronostic: avecPronostic,
      );

  /// Rend [enfant] à l'échelle de texte et à la largeur demandées.
  Future<void> rendre(
    WidgetTester tester,
    Widget enfant, {
    required double echelle,
    required double largeur,
  }) async {
    tester.view.physicalSize = Size(largeur, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(echelle)),
            child: Scaffold(
              body: SingleChildScrollView(child: enfant),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  /// Les échelles à tenir, et les largeurs du parc.
  ///
  /// 320 px, c'est un Android d'entrée de gamme — exactement le matériel visé.
  /// Vérifier à 400 px seulement reviendrait à ne rien vérifier.
  ///
  /// 1,5 est la borne mesurée : au-delà, la carte tient encore à 360 et 411 px
  /// mais cède à 320. C'est ce qui fixe `maxScaleFactor` dans `main.dart` —
  /// une valeur mesurée, plus une estimation.
  const echelles = [1.0, 1.15, 1.3, 1.5];
  const largeurs = [320.0, 360.0, 411.0];

  group('la carte de match ne déborde pas', () {
    for (final echelle in echelles) {
      for (final largeur in largeurs) {
        testWidgets('échelle $echelle · largeur ${largeur.toInt()} px',
            (tester) async {
          await rendre(tester, MatchCardWidget(match: fabriquer()),
              echelle: echelle, largeur: largeur);

          // Un débordement de mise en page remonte comme exception : c'est la
          // bande rayée jaune et noire, en version testable.
          expect(tester.takeException(), isNull);
        });
      }
    }

    // Toutes les notes, pas une seule.
    //
    // C'est le trou par lequel le defaut est passe : le banc balayait quatre
    // echelles et trois largeurs, mais toujours avec la meme note. Or c'est la
    // note qui decide du libelle, et le libelle va de « Bon » (trois lettres)
    // a « Tres elevee » (onze). Mesure : les notes 1 et 5 faisaient deborder
    // la carte de 6,8 px a 320 px / echelle 1,5 — les notes 2, 3 et 4 non.
    //
    // En production seules les notes 3, 4 et 5 sont publiees. Tout pronostic
    // a cinq etoiles cassait donc la mise en page sur un Android d'entree de
    // gamme dont l'utilisateur a grossi les caracteres.
    for (final note in [1, 2, 3, 4, 5]) {
      testWidgets('note $note · 320 px · échelle 1.5', (tester) async {
        await rendre(
          tester,
          MatchCardWidget(match: fabriquer(confiance: note)),
          echelle: 1.5,
          largeur: 320,
        );
        expect(tester.takeException(), isNull,
            reason: 'le libellé « ${MatchEntity.labelForConfidence(note)} » '
                'ne doit pas imposer une largeur que la rangée n a pas');
      });
    }

    // Une note hors echelle existe dans le code : `confidenceDisplay` rend
    // alors « Non évaluée ». C'est en corrigeant le gabarit ci-dessus qu'on
    // s'en est apercu — ces onze caracteres en corps 15 gras faisaient deborder
    // la carte de 15 px a 320 px / echelle 1,15, et de 47 px a l'echelle 1,3.
    //
    // Le gabarit se trompait, mais il exercait un cas reel : la colonne
    // `confidence_score` est un entier sans contrainte, et rien n'empeche une
    // valeur hors bornes d'arriver. Une protection qui, en se declenchant,
    // casse l'ecran qu'elle protege n'en est pas une.
    //
    // On garde donc le cas, cette fois volontairement.
    for (final echelle in echelles) {
      for (final largeur in largeurs) {
        testWidgets('note hors échelle · $echelle · ${largeur.toInt()} px',
            (tester) async {
          await rendre(
            tester,
            MatchCardWidget(match: fabriquer(confiance: 80)),
            echelle: echelle,
            largeur: largeur,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('match terminé, avec la date affichée', (tester) async {
      await rendre(
        tester,
        MatchCardWidget(
          match: fabriquer(status: MatchStatus.finished),
          showDate: true,
        ),
        echelle: 1.0,
        largeur: 411,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('sans pronostic, l\'autre disposition tient aussi',
        (tester) async {
      await rendre(
        tester,
        MatchCardWidget(match: fabriquer(avecPronostic: false)),
        echelle: 1.0,
        largeur: 411,
      );

      expect(tester.takeException(), isNull);
    });

    // ── Ce qui n'est pas encore tenu ────────────────────────────────────────
    //
    // Ces deux dispositions débordent encore à 320 px combiné à 1,3×. Mesuré,
    // pas supposé : 77 px pour celle sans pronostic. Elles restent ici, en
    // attente, plutôt que d'être retirées — un test supprimé ne rappelle rien,
    // et le trou disparaîtrait de la mémoire du projet avec lui.
    //
    // Le cas de base (match à venir, avec pronostic) tient, lui, aux trois
    // largeurs et aux trois échelles : c'est ce que voit la quasi-totalité des
    // cartes affichées.
    testWidgets('320 px × 1,3 — terminé', (tester) async {
      await rendre(
        tester,
        MatchCardWidget(
          match: fabriquer(status: MatchStatus.finished), showDate: true),
        echelle: 1.3, largeur: 320,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('320 px × 1,3 — sans pronostic', (tester) async {
      await rendre(
        tester,
        MatchCardWidget(match: fabriquer(avecPronostic: false)),
        echelle: 1.3, largeur: 320,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
