import 'package:flutter/material.dart';
import 'package:pronowin/l10n/app_strings.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/pronostics_provider.dart' show MatchEvent;

/// Fil des événements d'un match, au style Sofascore (demande de
/// l'utilisateur du 17 octobre 2026, vidéo de comparaison).
///
/// - Les plus récents en haut, séparés par période : « Fin du match »,
///   « Mi-temps » avec le score, « Prolongations »…
/// - Domicile à gauche, extérieur à droite, la minute sur le bord extérieur.
/// - Sur chaque but, le score du moment (« 1 - 0 »).
/// - Remplacement : l'entrant en premier. API-Football met le **sortant**
///   dans `player` et l'**entrant** dans `assist` (vérifié le 17 octobre 2026
///   sur un match réel : les sept `player` étaient des titulaires).
/// - Carton : son motif (`comments` : « Argument » → « Contestation »…).

// ─── Logique ──────────────────────────────────────────────────────────────────

/// Période d'un événement : 1, 2, 3 (prolongations) ou 4 (tirs au but).
int periodeEvenement(MatchEvent e) {
  if (e.comments == 'Penalty Shootout') return 4;
  if (e.minute <= 45) return 1;
  if (e.minute <= 90) return 2;
  if (e.minute <= 120) return 3;
  return 4;
}

/// Ce que marque un séparateur de période.
enum Separateur {
  /// En haut, match terminé : score final.
  finDuMatch,
  /// En haut, match en cours : la période jouée.
  premiereMiTemps, deuxiemeMiTemps, prolongations, tirsAuBut,
  /// Entre deux périodes : le score à ce moment.
  miTemps, finTempsReglementaire, finProlongations,
}

class LigneFil {
  final Separateur? separateur;
  final MatchEvent? evenement;
  /// Événement de l'équipe à domicile.
  final bool domicile;
  /// « 1 - 0 » : score après ce but, ou au séparateur. Null si on ne peut pas
  /// le garantir.
  final String? score;

  const LigneFil.separateur(Separateur this.separateur, {this.score})
      : evenement = null, domicile = false;
  const LigneFil.evenement(MatchEvent this.evenement, {required this.domicile, this.score})
      : separateur = null;
}

/// Construit le fil, dans l'ordre d'affichage (le plus récent en haut).
///
/// [periodeAtteinte] : 1 à 4, la période la plus avancée du match (d'après sa
/// phase), pour placer les séparateurs même sans événement. [scoreFinal] :
/// le score actuel ou final du match, hors tirs au but. Les scores au fil des
/// buts ne sont affichés que s'ils y aboutissent : un but contre son camp ou
/// une annulation par la VAR mal interprétés ne doivent pas afficher un score
/// faux.
List<LigneFil> construireFil(
  List<MatchEvent> evenements, {
  required String domicile,
  required bool termine,
  required int periodeAtteinte,
  ({int dom, int ext})? scoreFinal,
}) {
  final notables = [
    for (final e in evenements)
      if (const {'Goal', 'Card', 'subst', 'Var'}.contains(e.type)) e,
  ];
  // Ordre chronologique stable : période, minute, temps additionnel.
  final chrono = [...notables.asMap().entries]..sort((a, b) {
    final pa = periodeEvenement(a.value), pb = periodeEvenement(b.value);
    if (pa != pb) return pa - pb;
    if (a.value.minute != b.value.minute) return a.value.minute - b.value.minute;
    final ea = a.value.extra ?? 0, eb = b.value.extra ?? 0;
    if (ea != eb) return ea - eb;
    return a.key - b.key;
  });
  final ordre = [for (final e in chrono) e.value];

  final scores = _scoresAuFil(ordre, domicile: domicile, scoreFinal: scoreFinal);
  String? scoreApres(int i) => scores == null ? null : '${scores[i].dom} - ${scores[i].ext}';
  // Score à la fin d'une période : celui du dernier événement de cette
  // période ou d'avant.
  String? scoreFinDePeriode(int p) {
    if (scores == null) return null;
    var s = (dom: 0, ext: 0);
    for (var i = 0; i < ordre.length; i++) {
      if (periodeEvenement(ordre[i]) <= p) s = scores[i];
    }
    return '${s.dom} - ${s.ext}';
  }

  final atteinte = [
    periodeAtteinte,
    for (final e in ordre) periodeEvenement(e),
  ].reduce((a, b) => a > b ? a : b).clamp(1, 4);

  final lignes = <LigneFil>[];
  lignes.add(termine
      ? LigneFil.separateur(Separateur.finDuMatch,
          score: scoreFinal == null ? null : '${scoreFinal.dom} - ${scoreFinal.ext}')
      : LigneFil.separateur(switch (atteinte) {
          1 => Separateur.premiereMiTemps,
          2 => Separateur.deuxiemeMiTemps,
          3 => Separateur.prolongations,
          _ => Separateur.tirsAuBut,
        }));
  for (var p = atteinte; p >= 1; p--) {
    for (var i = ordre.length - 1; i >= 0; i--) {
      final e = ordre[i];
      if (periodeEvenement(e) != p) continue;
      lignes.add(LigneFil.evenement(e,
          domicile: e.team == domicile,
          score: e.type == 'Goal' && _compte(e) ? scoreApres(i) : null));
    }
    if (p > 1) {
      lignes.add(LigneFil.separateur(switch (p - 1) {
        1 => Separateur.miTemps,
        2 => Separateur.finTempsReglementaire,
        _ => Separateur.finProlongations,
      }, score: scoreFinDePeriode(p - 1)));
    }
  }
  return lignes;
}

/// Un but qui compte au score du match (pas un penalty manqué, pas un tir au
/// but de la séance).
bool _compte(MatchEvent e) =>
    e.type == 'Goal' && e.detail != 'Missed Penalty' && e.comments != 'Penalty Shootout';

/// Score après chaque événement de [ordre], ou null s'il n'aboutit pas au
/// score final quelle que soit l'interprétation des buts contre son camp.
List<({int dom, int ext})>? _scoresAuFil(
  List<MatchEvent> ordre, {
  required String domicile,
  required ({int dom, int ext})? scoreFinal,
}) {
  if (scoreFinal == null) return null;
  // API-Football n'est pas constant sur l'équipe d'un but contre son camp :
  // on essaie les deux lectures, et on garde celle qui retombe sur le score.
  for (final cscPourAdversaire in [false, true]) {
    var dom = 0, ext = 0;
    final apres = <({int dom, int ext})>[];
    for (final e in ordre) {
      final pourDomicile = e.team == domicile;
      if (_compte(e)) {
        final beneficiaireDomicile =
            e.detail == 'Own Goal' && cscPourAdversaire ? !pourDomicile : pourDomicile;
        beneficiaireDomicile ? dom++ : ext++;
      } else if (e.type == 'Var' && e.detail.toLowerCase().contains('goal cancelled')) {
        if (pourDomicile && dom > 0) dom--;
        if (!pourDomicile && ext > 0) ext--;
      }
      apres.add((dom: dom, ext: ext));
    }
    if (dom == scoreFinal.dom && ext == scoreFinal.ext) return apres;
  }
  return null;
}

/// Motif d'un carton, en français ; null si inconnu (on n'affiche pas
/// d'anglais au milieu du fil).
String? motifCarton(String? comments) => switch (comments?.toLowerCase().trim()) {
  'foul' => 'Faute',
  'argument' => 'Contestation',
  'time wasting' => 'Perte de temps',
  'unsportsmanlike conduct' => 'Comportement antisportif',
  'simulation' || 'diving' => 'Simulation',
  'handball' => 'Main',
  'roughing' => 'Brutalité',
  'professional foul' || 'professional foul last man' => 'Faute tactique',
  'holding' => 'Tirage de maillot',
  'violent conduct' => 'Comportement violent',
  'off the ball foul' => 'Faute sans ballon',
  'tripping' => 'Croc-en-jambe',
  'elbowing' => 'Coup de coude',
  'dangerous play' => 'Jeu dangereux',
  'serious foul' || 'serious foul play' => 'Faute grave',
  'excessive celebration' => 'Célébration excessive',
  'entering field' || 'leaving field' => 'Entrée ou sortie non autorisée',
  'bench' => 'Banc de touche',
  _ => null,
};

/// Décision de la VAR, en français.
String decisionVar(String detail) => switch (detail.toLowerCase().trim()) {
  'goal cancelled' || 'goal disallowed' => 'But annulé',
  'goal disallowed - offside' => 'But annulé (hors-jeu)',
  'goal disallowed - handball' => 'But annulé (main)',
  'goal disallowed - foul' => 'But annulé (faute)',
  'goal confirmed' => 'But validé',
  'penalty confirmed' => 'Penalty confirmé',
  'penalty cancelled' => 'Penalty annulé',
  'card upgrade' => 'Carton aggravé',
  'red card cancelled' => 'Carton rouge annulé',
  _ => 'Décision VAR',
};

// ─── Affichage ────────────────────────────────────────────────────────────────

class FilEvenements extends StatelessWidget {
  final List<LigneFil> lignes;
  const FilEvenements({super.key, required this.lignes});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final l in lignes)
      l.separateur != null ? _LigneSeparateur(ligne: l) : _LigneEvenement(ligne: l)],
  );
}

class _LigneSeparateur extends StatelessWidget {
  final LigneFil ligne;
  const _LigneSeparateur({required this.ligne});

  @override
  Widget build(BuildContext context) {
    final libelle = tr(context, switch (ligne.separateur!) {
      Separateur.finDuMatch => 'Fin du match',
      Separateur.premiereMiTemps => '1re mi-temps',
      Separateur.deuxiemeMiTemps => '2e mi-temps',
      Separateur.prolongations => 'Prolongations',
      Separateur.tirsAuBut => 'Tirs au but',
      // « Mi-temps » seul est déjà traduit « Halves » (familles de cotes).
      Separateur.miTemps => 'À la mi-temps',
      Separateur.finTempsReglementaire => 'Fin du temps réglementaire',
      Separateur.finProlongations => 'Fin des prolongations',
    });
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(child: Divider(color: context.cl.borderSoft, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: libelle),
              if (ligne.score != null) TextSpan(
                text: '   ${ligne.score}',
                style: TextStyle(color: context.cl.textP, fontWeight: FontWeight.w700)),
            ]), style: TextStyle(color: context.cl.textS, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Divider(color: context.cl.borderSoft, height: 1)),
        ]),
      ),
    );
  }
}

class _LigneEvenement extends StatelessWidget {
  final LigneFil ligne;
  const _LigneEvenement({required this.ligne});

  static const _jaune = Color(0xFFF5C518);
  static const _rouge = Color(0xFFE53935);

  /// Largeur de la colonne des minutes : « 90' +11 » tient.
  static const double largeurMinute = 40;

  @override
  Widget build(BuildContext context) {
    final e = ligne.evenement!;
    final dom = ligne.domicile;
    final (principal, secondaire) = _textes(context, e);

    final minute = SizedBox(
      width: largeurMinute,
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: "${e.minute}'"),
          if (e.extra != null) TextSpan(text: ' +${e.extra}',
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600)),
        ]),
        textAlign: dom ? TextAlign.left : TextAlign.right,
        style: TextStyle(color: context.cl.textS, fontSize: 11.5, fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
    final icone = SizedBox(width: 24, child: Center(child: _icone(context, e)));
    final score = ligne.score == null ? null : Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(ligne.score!, style: TextStyle(
        color: context.cl.textP, fontSize: 12.5, fontWeight: FontWeight.w800)),
    );
    final textes = Expanded(child: Column(
      crossAxisAlignment: dom ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(principal, maxLines: 1, overflow: TextOverflow.ellipsis,
          textAlign: dom ? TextAlign.left : TextAlign.right,
          style: TextStyle(color: context.cl.textP, fontSize: 12.5, fontWeight: FontWeight.w600)),
        if (secondaire != null)
          Text(secondaire, maxLines: 1, overflow: TextOverflow.ellipsis,
            textAlign: dom ? TextAlign.left : TextAlign.right,
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
      ],
    ));

    // Moitié du fil réservée au camp : les événements d'une équipe restent
    // de son côté, comme sur Sofascore.
    final moitie = Row(children: dom
        ? [minute, icone, ?score, const SizedBox(width: 6), textes]
        : [textes, const SizedBox(width: 6), ?score, icone, minute]);
    return Semantics(
      label: tr(context, "{arg0}e minute : {arg1}", [
        e.extra != null ? '${e.minute}+${e.extra}' : '${e.minute}',
        [principal, ?secondaire, ?ligne.score].join(', '),
      ]),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: dom
            ? [Expanded(flex: 3, child: moitie), const Spacer(flex: 1)]
            : [const Spacer(flex: 1), Expanded(flex: 3, child: moitie)]),
      ),
    );
  }

  /// Texte principal et secondaire de la ligne.
  static (String, String?) _textes(BuildContext context, MatchEvent e) {
    final joueur = e.player.isEmpty ? tr(context, "Joueur") : e.player;
    switch (e.type) {
      case 'Goal':
        if (e.detail == 'Missed Penalty') return (joueur, tr(context, "Penalty manqué"));
        final passe = e.assist != null && e.assist!.isNotEmpty
            ? tr(context, "Passe déc. : {arg0}", [e.assist]) : null;
        return (joueur, switch (e.detail) {
          'Own Goal' => tr(context, "But contre son camp"),
          'Penalty' => tr(context, "Penalty"),
          _ => passe,
        });
      case 'subst':
        // Entrant en premier : il est dans `assist` (voir l'en-tête du fichier).
        final entrant = e.assist != null && e.assist!.isNotEmpty ? e.assist! : joueur;
        final sortant = e.assist != null && e.assist!.isNotEmpty ? e.player : null;
        return (entrant, sortant == null || sortant.isEmpty
            ? tr(context, "Remplacement") : tr(context, "Sort : {arg0}", [sortant]));
      case 'Card':
        final motif = motifCarton(e.comments);
        return (joueur, motif != null ? tr(context, motif) : tr(context, switch (e.detail) {
          'Red Card' => 'Carton rouge',
          'Second Yellow card' || 'Second Yellow Card' => 'Deuxième carton jaune',
          _ => 'Carton jaune',
        }));
      case 'Var':
        return (tr(context, decisionVar(e.detail)), e.player.isEmpty ? null : e.player);
    }
    return (joueur, null);
  }

  static Widget _icone(BuildContext context, MatchEvent e) {
    switch (e.type) {
      case 'Goal':
        if (e.detail == 'Missed Penalty') {
          return Stack(clipBehavior: Clip.none, children: [
            Icon(Icons.sports_soccer_rounded, color: context.cl.textM, size: 16),
            Positioned(right: -4, bottom: -3,
              child: Icon(Icons.close_rounded, color: context.cl.error, size: 10)),
          ]);
        }
        return Icon(Icons.sports_soccer_rounded,
          color: e.detail == 'Own Goal' ? context.cl.error : context.cl.success, size: 16);
      case 'Card':
        final rouge = e.detail == 'Red Card';
        final deuxJaunes = e.detail.toLowerCase() == 'second yellow card';
        // Couleurs fixes : un carton est jaune ou rouge, quel que soit le
        // thème (la couleur « avertissement » du thème clair tire sur le
        // marron).
        Widget carton(Color c) => Container(width: 10, height: 14,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)));
        if (deuxJaunes) {
          return SizedBox(width: 16, height: 16, child: Stack(children: [
            Positioned(left: 0, top: 0, child: carton(_jaune)),
            Positioned(left: 5, top: 2, child: carton(_rouge)),
          ]));
        }
        return carton(rouge ? _rouge : _jaune);
      case 'subst':
        return Icon(Icons.swap_vert_rounded, color: context.cl.success, size: 18);
      case 'Var':
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: context.cl.info, width: 1),
              borderRadius: BorderRadius.circular(3)),
            child: Text('VAR', softWrap: false, style: TextStyle(color: context.cl.info,
              fontSize: 8, fontWeight: FontWeight.w800, height: 1.1)),
          ),
        );
    }
    return Icon(Icons.circle, color: context.cl.textM, size: 8);
  }
}
