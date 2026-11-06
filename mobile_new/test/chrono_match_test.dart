import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/pronostics/domain/chrono_match.dart';

/// Chrono du direct à la seconde, comme Sofascore (demande de l'utilisateur
/// du 17 octobre 2026) : calculé sur le téléphone à partir du début de chaque
/// mi-temps que publie API-Football.
void main() {
  final debut1 = DateTime.utc(2026, 10, 17, 14, 0, 30);
  final debut2 = DateTime.utc(2026, 10, 17, 15, 3, 10);

  ChronoMatch c({String? phase, int? elapsed, int? extra, DateTime? d1, DateTime? d2, required DateTime t}) =>
      chronoMatch(phase: phase, elapsed: elapsed, extra: extra, debut1: d1, debut2: d2, maintenant: t);

  group('à la seconde', () {
    test('première mi-temps : 23:45, 24e minute', () {
      final r = c(phase: '1H', elapsed: 23, d1: debut1, t: debut1.add(const Duration(minutes: 23, seconds: 45)));
      expect(r.etat, EtatChrono.aLaSeconde);
      expect(r.texteSecondes, '23:45');
      expect(r.minute, 24);
      expect(r.additionnel, isNull);
    });

    test('seconde mi-temps : repart de 45:00', () {
      final r = c(phase: '2H', elapsed: 67, d1: debut1, d2: debut2,
          t: debut2.add(const Duration(minutes: 22, seconds: 23)));
      expect(r.texteSecondes, '67:23');
    });

    test('temps additionnel : 92:09 et « +7 » une fois la 90e passée', () {
      final r = c(phase: '2H', elapsed: 90, extra: 7, d2: debut2,
          t: debut2.add(const Duration(minutes: 47, seconds: 9)));
      expect(r.texteSecondes, '92:09');
      expect(r.additionnel, 7);
      // Annoncé avant la 90e : pas encore affiché.
      expect(c(phase: '2H', elapsed: 88, extra: 7, d2: debut2,
          t: debut2.add(const Duration(minutes: 43))).additionnel, isNull);
    });

    test('première mi-temps prolongée : 46:30 et « +3 »', () {
      final r = c(phase: '1H', elapsed: 45, extra: 3, d1: debut1,
          t: debut1.add(const Duration(minutes: 46, seconds: 30)));
      expect((r.texteSecondes, r.additionnel), ('46:30', 3));
    });

    test('horloge du téléphone en retard sur le coup d\'envoi : 00:00, pas de temps négatif', () {
      expect(c(phase: '1H', elapsed: 1, d1: debut1, t: debut1.subtract(const Duration(seconds: 20))).texteSecondes, '00:00');
      expect(c(phase: '2H', elapsed: 46, d2: debut2, t: debut2.subtract(const Duration(seconds: 5))).texteSecondes, '45:00');
    });
  });

  group('repli sur la minute', () {
    test('sans début de mi-temps', () {
      final r = c(phase: '2H', elapsed: 67, t: debut2);
      expect((r.etat, r.minute), (EtatChrono.aLaMinute, 67));
    });

    test('chrono incohérent avec la minute publiée (horodatage faux, horloge déréglée)', () {
      final r = c(phase: '2H', elapsed: 60, d2: debut2, t: debut2.add(const Duration(minutes: 40)));
      expect((r.etat, r.minute), (EtatChrono.aLaMinute, 60));
    });

    test('prolongations : la minute, faute de début daté', () {
      expect(c(phase: 'ET', elapsed: 105, t: debut2).etat, EtatChrono.aLaMinute);
      expect(c(phase: 'ET', elapsed: 121, extra: 2, t: debut2).additionnel, 2);
    });

    test('phase inconnue : la minute du relevé de score, sinon « en direct »', () {
      expect(c(elapsed: 39, t: debut1).minute, 39);
      expect(c(t: debut1).etat, EtatChrono.inconnu);
    });
  });

  test('pauses et interruptions : un libellé, pas de chiffre qui tourne', () {
    expect(c(phase: 'HT', elapsed: 45, d1: debut1, t: debut2).etat, EtatChrono.miTemps);
    expect(c(phase: 'BT', elapsed: 90, t: debut2).etat, EtatChrono.pause);
    expect(c(phase: 'P', elapsed: 120, t: debut2).etat, EtatChrono.tirsAuBut);
    expect(c(phase: 'SUSP', elapsed: 70, t: debut2).etat, EtatChrono.interrompu);
    expect(c(phase: 'INT', elapsed: 70, t: debut2).etat, EtatChrono.interrompu);
  });

  test('horodatage Unix en secondes', () {
    final d = DateTime.utc(2026, 10, 17, 14, 0, 30);
    expect(depuisSecondesUnix(d.millisecondsSinceEpoch ~/ 1000), d);
    expect(depuisSecondesUnix(null), isNull);
    expect(depuisSecondesUnix('1791896430'), isNull);
  });
}
