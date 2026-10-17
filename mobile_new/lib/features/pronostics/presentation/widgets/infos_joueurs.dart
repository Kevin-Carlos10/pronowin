import 'package:flutter/material.dart';

import '../providers/pronostics_provider.dart' show MatchEvent, PlayerRating;

/// Ce que les compositions affichent sur chaque joueur, au style Sofascore
/// (demande de l'utilisateur du 17 octobre 2026) : sa note, ses buts, ses
/// cartons, son entrée ou sa sortie.
///
/// Les événements et les notes sont reliés au joueur par son **identifiant**
/// API-Football, jamais par son nom : les deux réponses n'écrivent pas les
/// noms de la même façon (« A. Pérez » ici, « Ayoze Pérez » là).
class InfosJoueur {
  double? note;
  int buts = 0;
  int butsContreSonCamp = 0;
  int jaunes = 0;
  int rouges = 0;
  bool capitaine = false;
  /// Minute de sa sortie, s'il a été remplacé.
  int? sortie;
  /// Minute de son entrée, s'il est entré en jeu.
  int? entree;
  /// Nom du joueur qu'il a remplacé.
  String? remplace;

  bool get aDesEvenements => buts > 0 || butsContreSonCamp > 0 || jaunes > 0 || rouges > 0 || sortie != null;
}

/// Regroupe notes et événements par identifiant de joueur.
Map<int, InfosJoueur> infosJoueurs({
  List<PlayerRating> notes = const [],
  List<MatchEvent> evenements = const [],
}) {
  final infos = <int, InfosJoueur>{};
  InfosJoueur de(int id) => infos.putIfAbsent(id, InfosJoueur.new);

  for (final n in notes) {
    final id = n.id;
    if (id == null) continue;
    de(id)
      ..note = n.rating
      ..capitaine = n.captain;
  }

  // Les cartons viennent des événements ; à défaut (événements non couverts),
  // des statistiques individuelles qui accompagnent les notes.
  final cartonsParEvenements = evenements.any((e) => e.type == 'Card');
  if (!cartonsParEvenements) {
    for (final n in notes) {
      if (n.id == null) continue;
      de(n.id!)
        ..jaunes = n.yellow
        ..rouges = n.red;
    }
  }

  for (final e in evenements) {
    final joueur = e.playerId;
    switch (e.type) {
      case 'Goal':
        if (joueur == null || e.detail == 'Missed Penalty' || e.comments == 'Penalty Shootout') break;
        if (e.detail == 'Own Goal') {
          de(joueur).butsContreSonCamp++;
        } else {
          de(joueur).buts++;
        }
      case 'Card':
        if (joueur == null) break;
        final d = e.detail.toLowerCase();
        if (d == 'red card') {
          de(joueur).rouges++;
        } else if (d == 'second yellow card') {
          final j = de(joueur);
          j.jaunes = 1;
          j.rouges++;
        } else {
          de(joueur).jaunes++;
        }
      case 'subst':
        // API-Football : `player` sort, `assist` entre.
        if (joueur != null) de(joueur).sortie = e.minute;
        final entrant = e.assistId;
        if (entrant != null) {
          de(entrant)
            ..entree = e.minute
            ..remplace = e.player.isEmpty ? null : e.player;
        }
    }
  }
  return infos;
}

/// Note moyenne d'une équipe (« home » ou « away »), sur les joueurs notés.
double? noteEquipe(List<PlayerRating> notes, String cote) {
  final n = [for (final p in notes) if (p.team == cote && p.rating > 0) p.rating];
  if (n.isEmpty) return null;
  return n.reduce((a, b) => a + b) / n.length;
}

/// Couleur d'une note, sur l'échelle de Sofascore : bleu au-delà de 8, vert
/// de 7 à 8, jaune de 6,5 à 7, orange de 6 à 6,5, rouge en dessous.
///
/// Teintes foncées : le chiffre blanc y garde au moins 4,5:1 de contraste.
/// Le jaune, lui, porte un chiffre sombre ([texteSurNote]).
Color couleurNote(double note) {
  if (note >= 8.0) return const Color(0xFF2563EB);
  if (note >= 7.0) return const Color(0xFF15803D);
  if (note >= 6.5) return const Color(0xFFEAB308);
  if (note >= 6.0) return const Color(0xFFC2410C);
  return const Color(0xFFB91C1C);
}

/// Couleur du chiffre posé sur [couleurNote].
Color texteSurNote(double note) =>
    note >= 6.5 && note < 7.0 ? const Color(0xFF111827) : Colors.white;

/// « 7.2 » sur fond de couleur, comme les notes de Sofascore.
class PastilleNote extends StatelessWidget {
  final double note;
  final double taille;
  const PastilleNote(this.note, {super.key, this.taille = 9});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: taille * 0.4, vertical: taille * 0.12),
    decoration: BoxDecoration(
      color: couleurNote(note),
      borderRadius: BorderRadius.circular(taille * 0.35)),
    child: Text(note.toStringAsFixed(1),
      style: TextStyle(color: texteSurNote(note), fontSize: taille, fontWeight: FontWeight.w800,
        height: 1.15, fontFeatures: const [FontFeature.tabularFigures()])),
  );
}
