import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/pronostics/presentation/providers/pronostics_provider.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/infos_joueurs.dart';

/// Compositions au style Sofascore (17 octobre 2026) : note, buts, cartons,
/// entrée et sortie de chaque joueur, reliés par identifiant.
void main() {
  PlayerRating note(int id, double n, {String equipe = 'home', bool capitaine = false, int jaunes = 0}) =>
      PlayerRating(id: id, name: 'J$id', team: equipe, rating: n, minutes: 90, goals: 0, assists: 0,
          shots: 0, passes: 0, captain: capitaine, yellow: jaunes);
  MatchEvent ev(String type, String detail, int min, {int? joueur, int? assist, String nom = 'Sortant'}) =>
      MatchEvent(minute: min, team: 'V', player: nom, type: type, detail: detail, playerId: joueur, assistId: assist);

  test('événements reliés par identifiant : buts, CSC, cartons, remplacement', () {
    final infos = infosJoueurs(
      notes: [note(1, 8.4, capitaine: true), note(2, 6.1), note(3, 7.0)],
      evenements: [
        ev('Goal', 'Normal Goal', 12, joueur: 1, assist: 3),
        ev('Goal', 'Penalty', 70, joueur: 1),
        ev('Goal', 'Missed Penalty', 80, joueur: 2),
        ev('Goal', 'Own Goal', 55, joueur: 4),
        ev('Card', 'Yellow Card', 30, joueur: 2),
        ev('Card', 'Second Yellow card', 60, joueur: 5),
        // API-Football : `player` sort, `assist` entre.
        ev('subst', 'Substitution 1', 66, joueur: 2, assist: 3, nom: 'C. Macià'),
        ev('Goal', 'Normal Goal', 10, nom: 'sans identifiant'),
      ]);
    expect((infos[1]!.note, infos[1]!.buts, infos[1]!.capitaine), (8.4, 2, true));
    expect(infos[2]!.buts, 0, reason: 'penalty manqué : pas de but');
    expect((infos[2]!.jaunes, infos[2]!.sortie), (1, 66));
    expect((infos[3]!.entree, infos[3]!.remplace), (66, 'C. Macià'));
    expect(infos[4]!.butsContreSonCamp, 1);
    expect((infos[5]!.jaunes, infos[5]!.rouges), (1, 1));
    expect(infos[3]!.aDesEvenements, isFalse, reason: 'une entrée en jeu n\'est pas un badge sur le terrain');
  });

  test('sans événement de carton : cartons tirés des statistiques des notes', () {
    final infos = infosJoueurs(notes: [note(9, 6.8, jaunes: 1)]);
    expect(infos[9]!.jaunes, 1);
  });

  test('note d\'équipe : moyenne des joueurs notés de ce côté', () {
    final notes = [note(1, 8.0), note(2, 7.0), note(3, 6.0, equipe: 'away')];
    expect(noteEquipe(notes, 'home'), 7.5);
    expect(noteEquipe(notes, 'away'), 6.0);
    expect(noteEquipe(const [], 'home'), isNull);
  });

  test('couleurs de l\'échelle Sofascore, chiffre lisible sur chacune (≥ 4,5:1)', () {
    double contraste(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      final (h, l) = la > lb ? (la, lb) : (lb, la);
      return (h + 0.05) / (l + 0.05);
    }
    final paliers = {9.1: 0xFF2563EB, 7.4: 0xFF15803D, 6.7: 0xFFEAB308, 6.2: 0xFFC2410C, 5.4: 0xFFB91C1C};
    paliers.forEach((note, couleur) {
      expect(couleurNote(note), Color(couleur), reason: '$note');
      expect(contraste(couleurNote(note), texteSurNote(note)), greaterThanOrEqualTo(4.5), reason: '$note');
    });
  });
}
