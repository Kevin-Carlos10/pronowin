import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/fil_evenements.dart';

/// Les buteurs sous le nom de chaque équipe, dans l'en-tête du match
/// (7 novembre 2026, comme Sofascore : « N. Okafor 79' »).
void main() {
  MatchEvent but(int minute, String equipe, String joueur, {String detail = 'Normal Goal', int? extra, String type = 'Goal'}) =>
      MatchEvent(minute: minute, extra: extra, team: equipe, player: joueur, type: type, detail: detail);

  test('un but, une minute', () {
    final b = buteursDuMatch([but(79, 'Leeds', 'N. Okafor')], domicile: 'Leeds', scoreFinal: (dom: 1, ext: 0));
    expect(b.dom, ["N. Okafor 79'"]);
    expect(b.ext, isEmpty);
  });

  test('un doublé se regroupe ; le penalty et le temps additionnel se lisent', () {
    final b = buteursDuMatch([
      but(85, 'Bayern', 'H. Kane', detail: 'Penalty'),
      but(12, 'Bayern', 'H. Kane'),
      but(90, 'Bayern', 'M. Olise', extra: 3),
    ], domicile: 'Mainz', scoreFinal: (dom: 0, ext: 3));
    expect(b.ext, ["H. Kane 12', 85' (pen.)", "M. Olise 90+3'"]);
  });

  test('penalty manqué et tir au but de la séance ne comptent pas', () {
    final b = buteursDuMatch([
      but(30, 'PSG', 'O. Dembélé', detail: 'Missed Penalty'),
      MatchEvent(minute: 120, team: 'PSG', player: 'Vitinha', type: 'Goal', detail: 'Penalty', comments: 'Penalty Shootout'),
    ], domicile: 'PSG', scoreFinal: (dom: 0, ext: 0));
    expect(b.dom, isEmpty);
  });

  test('but contre son camp : du côté de l\'équipe qui en profite, quelle que soit la lecture du fournisseur', () {
    // Le fournisseur range le csc tantôt chez l'équipe du joueur…
    final a = buteursDuMatch([but(40, 'Bayern', 'J. Tah', detail: 'Own Goal')],
        domicile: 'Mainz', scoreFinal: (dom: 1, ext: 0));
    expect(a.dom, ["J. Tah 40' (csc)"]);
    // … tantôt chez celle qui en profite.
    final b = buteursDuMatch([but(40, 'Mainz', 'J. Tah', detail: 'Own Goal')],
        domicile: 'Mainz', scoreFinal: (dom: 1, ext: 0));
    expect(b.dom, ["J. Tah 40' (csc)"]);
  });

  test('un but annulé par la VAR disparaît', () {
    final b = buteursDuMatch([
      but(20, 'Arsenal', 'B. Saka'),
      but(22, 'Arsenal', '', type: 'Var', detail: 'Goal cancelled'),
      but(60, 'Arsenal', 'M. Ødegaard'),
    ], domicile: 'Arsenal', scoreFinal: (dom: 1, ext: 0));
    expect(b.dom, ["M. Ødegaard 60'"]);
  });
}
