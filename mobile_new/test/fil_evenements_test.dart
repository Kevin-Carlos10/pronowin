import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/fil_evenements.dart';

import 'aides/banc_ecran.dart';

/// Fil des événements au style Sofascore (demande de l'utilisateur du
/// 17 octobre 2026).
void main() {
  MatchEvent but(int min, String equipe, String joueur, {String detail = 'Normal Goal', String? passe, int? extra, String? comments}) =>
      MatchEvent(minute: min, extra: extra, team: equipe, player: joueur, assist: passe, type: 'Goal', detail: detail, comments: comments);
  MatchEvent carton(int min, String equipe, String joueur, {String detail = 'Yellow Card', String? motif, int? extra}) =>
      MatchEvent(minute: min, extra: extra, team: equipe, player: joueur, type: 'Card', detail: detail, comments: motif);
  // API-Football : `player` = sortant, `assist` = entrant.
  MatchEvent changement(int min, String equipe, String sortant, String entrant) =>
      MatchEvent(minute: min, team: equipe, player: sortant, assist: entrant, type: 'subst', detail: 'Substitution 1');

  String decrire(LigneFil l) => l.separateur != null
      ? '[${l.separateur!.name}${l.score != null ? ' ${l.score}' : ''}]'
      : '${l.evenement!.minute}${l.evenement!.extra != null ? '+${l.evenement!.extra}' : ''} '
        '${l.domicile ? 'D' : 'E'} ${l.evenement!.type}${l.score != null ? ' ${l.score}' : ''}';

  group('construction', () {
    final evenements = [
      but(12, 'Villarreal', 'G. Moreno', passe: 'A. Pépé'),
      carton(38, 'Elche', 'G. Villar', motif: 'Foul'),
      changement(46, 'Elche', 'J. Fernández', 'A. Mendoza'),
      but(58, 'Elche', 'M. Aguado'),
      but(90, 'Villarreal', 'A. Pépé', extra: 3, detail: 'Penalty'),
      MatchEvent(minute: 70, team: 'Villarreal', player: 'Corner', type: 'Normal', detail: 'x'),
    ];

    test('match terminé : les plus récents en haut, séparés par période, score au fil des buts', () {
      final fil = construireFil(evenements, domicile: 'Villarreal', termine: true,
          periodeAtteinte: 2, scoreFinal: (dom: 2, ext: 1));
      expect(fil.map(decrire), [
        '[finDuMatch 2 - 1]',
        '90+3 D Goal 2 - 1',
        '58 E Goal 1 - 1',
        '46 E subst',
        '[miTemps 1 - 0]',
        '38 E Card',
        '12 D Goal 1 - 0',
      ]);
    });

    test('score qui n\'aboutit pas au score final : aucun score au fil des buts', () {
      final fil = construireFil(evenements, domicile: 'Villarreal', termine: true,
          periodeAtteinte: 2, scoreFinal: (dom: 3, ext: 1));
      expect(fil.where((l) => l.evenement?.type == 'Goal').every((l) => l.score == null), isTrue);
      expect(fil.first.score, '3 - 1', reason: 'le score final reste celui du match');
    });

    test('but contre son camp : la lecture qui retombe sur le score final', () {
      final csc = [but(30, 'Elche', 'D. Ndiaye', detail: 'Own Goal')];
      // Une lecture crédite Elche, l'autre Villarreal : seule la seconde
      // donne le 1 - 0 final.
      final fil = construireFil(csc, domicile: 'Villarreal', termine: true, periodeAtteinte: 2, scoreFinal: (dom: 1, ext: 0));
      expect(fil.firstWhere((l) => l.evenement != null).score, '1 - 0');
    });

    test('but annulé par la VAR et penalty manqué ne comptent pas', () {
      final fil = construireFil([
        but(20, 'Villarreal', 'G. Moreno'),
        MatchEvent(minute: 21, team: 'Villarreal', player: 'G. Moreno', type: 'Var', detail: 'Goal cancelled'),
        but(60, 'Elche', 'M. Aguado', detail: 'Missed Penalty'),
        but(75, 'Elche', 'M. Aguado'),
      ], domicile: 'Villarreal', termine: true, periodeAtteinte: 2, scoreFinal: (dom: 0, ext: 1));
      expect(fil.firstWhere((l) => l.evenement?.minute == 75).score, '0 - 1');
      expect(fil.firstWhere((l) => l.evenement?.minute == 60).score, isNull);
    });

    test('en direct, seconde mi-temps sans événement encore : séparateurs quand même', () {
      final fil = construireFil([carton(38, 'Elche', 'G. Villar')], domicile: 'Villarreal',
          termine: false, periodeAtteinte: 2, scoreFinal: (dom: 0, ext: 0));
      expect(fil.map(decrire), ['[deuxiemeMiTemps]', '[miTemps 0 - 0]', '38 E Card']);
    });

    test('prolongations et tirs au but', () {
      final fil = construireFil([
        but(80, 'Villarreal', 'G. Moreno'),
        but(88, 'Elche', 'M. Aguado'),
        but(105, 'Villarreal', 'A. Pépé'),
        but(120, 'Elche', 'R. Mir', comments: 'Penalty Shootout'),
      ], domicile: 'Villarreal', termine: true, periodeAtteinte: 4, scoreFinal: (dom: 2, ext: 1));
      expect(fil.map(decrire), [
        '[finDuMatch 2 - 1]',
        '120 E Goal',
        '[finProlongations 2 - 1]',
        '105 D Goal 2 - 1',
        '[finTempsReglementaire 1 - 1]',
        '88 E Goal 1 - 1',
        '80 D Goal 1 - 0',
        '[miTemps 0 - 0]',
      ]);
    });
  });

  test('motifs de carton et décisions VAR en français, rien d\'anglais en repli', () {
    expect(motifCarton('Argument'), 'Contestation');
    expect(motifCarton('Foul'), 'Faute');
    expect(motifCarton('Time wasting'), 'Perte de temps');
    expect(motifCarton('Something new'), isNull);
    expect(motifCarton(null), isNull);
    expect(decisionVar('Goal Disallowed - offside'), 'But annulé (hors-jeu)');
    expect(decisionVar('Penalty cancelled'), 'Penalty annulé');
    expect(decisionVar('Unknown'), 'Décision VAR');
  });

  group('affichage', () {
    setUpAll(preparerBanc);

    Future<void> afficher(WidgetTester t, List<LigneFil> lignes, {double echelle = 1, double largeur = 360}) async {
      t.view.physicalSize = Size(largeur * 2, 1600 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: AppTheme.dark, home: MediaQuery(
        data: MediaQueryData(size: Size(largeur, 1600), textScaler: TextScaler.linear(echelle)),
        child: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16),
          child: FilEvenements(lignes: lignes))))));
    }

    final lignes = construireFil([
      but(12, 'Villarreal', 'Gerard Moreno', passe: 'Nicolas Pépé'),
      carton(38, 'Elche', 'Gonzalo Villar', motif: 'Argument'),
      changement(65, 'Elche', 'Tete Morente', 'Lucas Cepeda'),
      carton(90, 'Villarreal', 'Juan Foyth', motif: 'Argument', extra: 1),
      MatchEvent(minute: 63, team: 'Villarreal', player: 'Rafa Revivo', type: 'Var', detail: 'Penalty cancelled'),
    ], domicile: 'Villarreal', termine: false, periodeAtteinte: 2, scoreFinal: (dom: 1, ext: 0));

    testWidgets('textes à la Sofascore : entrant d\'abord, motif du carton, temps additionnel', (t) async {
      await afficher(t, lignes);
      expect(find.text('2e mi-temps'), findsOneWidget);
      expect(find.textContaining('À la mi-temps'), findsOneWidget);
      expect(find.text('Lucas Cepeda'), findsOneWidget, reason: 'l\'entrant en premier');
      expect(find.text('Sort : Tete Morente'), findsOneWidget);
      expect(find.text('Contestation'), findsNWidgets(2));
      expect(find.text('Passe déc. : Nicolas Pépé'), findsOneWidget);
      expect(find.text('Penalty annulé'), findsOneWidget);
      expect(find.text('1 - 0'), findsOneWidget, reason: 'score au but de la 12e');
      expect(find.text('VAR'), findsOneWidget);
    });

    for (final echelle in [1.0, 1.8]) {
      testWidgets('aucun débordement à ${(echelle * 100).round()} % sur 320 px', (t) async {
        await afficher(t, lignes, echelle: echelle, largeur: 320);
        expect(t.takeException(), isNull);
      });
    }
  });
}
