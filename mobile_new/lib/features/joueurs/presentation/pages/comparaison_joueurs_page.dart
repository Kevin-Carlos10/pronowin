import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pronowin/l10n/app_strings.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/image_distante.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../../../shared/widgets/erreur_chargement.dart';
import '../../../pronostics/presentation/providers/recherche_provider.dart';
import '../../../pronostics/presentation/widgets/infos_joueurs.dart' show PastilleNote;
import '../providers/fiche_joueur_provider.dart';

/// Comparer deux joueurs (7 novembre 2026, comme Sofascore et FotMob) :
/// leur saison côte à côte, la meilleure valeur de chaque ligne mise en avant.
///
/// Chaque joueur est lu dans sa compétition principale (la plus jouée), celle
/// de l'en-tête de sa fiche.

/// Demande l'autre joueur, puis ouvre la comparaison.
Future<void> comparerAvecUnAutre(BuildContext context, FicheJoueur premier) async {
  final autre = await showModalBottomSheet<JoueurTrouve>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ChoixJoueur(exclu: premier.id),
  );
  if (autre == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ComparaisonJoueursPage(idA: premier.id, idB: autre.id)));
}

class _ChoixJoueur extends ConsumerStatefulWidget {
  final int exclu;
  const _ChoixJoueur({required this.exclu});

  @override
  ConsumerState<_ChoixJoueur> createState() => _ChoixJoueurState();
}

class _ChoixJoueurState extends ConsumerState<_ChoixJoueur> {
  String _terme = '';

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final t = _terme.trim();
    final resultats = t.length < 3 ? null : ref.watch(rechercheEquipesJoueursProvider(t));
    final joueurs = [
      for (final j in resultats?.valueOrNull?.joueurs ?? const <JoueurTrouve>[])
        if (j.id != widget.exclu) j,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(tr(context, "Comparer avec…"),
              style: TextStyle(color: cl.textP, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const Key('recherche-comparaison'),
              autofocus: true,
              onChanged: (v) => setState(() => _terme = v),
              decoration: InputDecoration(
                hintText: tr(context, "Nom du joueur (3 lettres au moins)"),
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: cl.surfaceDeep,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: resultats == null
            ? const SizedBox.shrink()
            : resultats.isLoading && joueurs.isEmpty
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
              : joueurs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(tr(context, "Aucun joueur trouvé."),
                      textAlign: TextAlign.center, style: TextStyle(color: cl.textM)))
                : ListView(children: [
                    for (final j in joueurs)
                      ListTile(
                        key: Key('choix-joueur-${j.id}'),
                        leading: ClipOval(child: SizedBox(width: 34, height: 34, child: ImageDistante(
                          url: j.photo, largeur: 34, hauteur: 34,
                          repli: ColoredBox(color: cl.surfaceDeep,
                            child: Icon(Icons.person_rounded, size: 20, color: cl.textM))))),
                        title: Text(j.nom, style: TextStyle(color: cl.textP, fontWeight: FontWeight.w600)),
                        subtitle: j.nationalite == null ? null
                            : Text(j.nationalite!, style: TextStyle(color: cl.textM, fontSize: 12)),
                        onTap: () => Navigator.of(context).pop(j),
                      ),
                  ])),
        ]),
      ),
    );
  }
}

class ComparaisonJoueursPage extends ConsumerWidget {
  final int idA, idB;
  const ComparaisonJoueursPage({super.key, required this.idA, required this.idB});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cl = context.cl;
    final a = ref.watch(ficheJoueurProvider(idA));
    final b = ref.watch(ficheJoueurProvider(idB));
    return Scaffold(
      backgroundColor: cl.bg,
      appBar: AppBar(
        backgroundColor: cl.bg,
        elevation: 0,
        title: Text(tr(context, "Comparaison"),
          style: TextStyle(color: cl.textP, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: switch ((a, b)) {
        (AsyncData(value: final fa), AsyncData(value: final fb)) => _Comparaison(a: fa, b: fb),
        (AsyncError(:final error), _) || (_, AsyncError(:final error)) => ErreurChargement(
            erreur: error, quoi: tr(context, "la comparaison"),
            onRetry: () { ref.invalidate(ficheJoueurProvider(idA)); ref.invalidate(ficheJoueurProvider(idB)); }),
        _ => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      },
    );
  }
}

/// Une ligne de comparaison : sa valeur pour chacun, et le sens du « mieux »
/// (plus de buts, moins de cartons).
typedef _Ligne = ({String libelle, num? a, num? b, String Function(num) format, bool plusEstMieux});

class _Comparaison extends StatelessWidget {
  final FicheJoueur a, b;
  const _Comparaison({required this.a, required this.b});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final sa = a.principale, sb = b.principale;
    String entier(num v) => '${v.toInt()}';
    String note(num v) => v.toStringAsFixed(2);
    String pourcent(num v) => '${v.toInt()} %';
    final gardiens = (sa?.estGardien ?? false) && (sb?.estGardien ?? false);
    final lignes = <_Ligne>[
      (libelle: tr(context, "Note moyenne"), a: sa?.rating, b: sb?.rating, format: note, plusEstMieux: true),
      (libelle: tr(context, "Matchs"), a: sa?.appearances, b: sb?.appearances, format: entier, plusEstMieux: true),
      (libelle: tr(context, "Minutes"), a: sa?.minutes, b: sb?.minutes, format: entier, plusEstMieux: true),
      if (gardiens) ...[
        (libelle: tr(context, "Arrêts"), a: sa?.saves, b: sb?.saves, format: entier, plusEstMieux: true),
        (libelle: tr(context, "Buts encaissés"), a: sa?.conceded, b: sb?.conceded, format: entier, plusEstMieux: false),
      ] else ...[
        (libelle: tr(context, "Buts"), a: sa?.goals, b: sb?.goals, format: entier, plusEstMieux: true),
        (libelle: tr(context, "Passes décisives"), a: sa?.assists, b: sb?.assists, format: entier, plusEstMieux: true),
        (libelle: tr(context, "Tirs cadrés"), a: sa?.shotsOn, b: sb?.shotsOn, format: entier, plusEstMieux: true),
        (libelle: tr(context, "Passes clés"), a: sa?.keyPasses, b: sb?.keyPasses, format: entier, plusEstMieux: true),
        (libelle: tr(context, "Dribbles réussis"), a: sa?.dribblesSuccess, b: sb?.dribblesSuccess, format: entier, plusEstMieux: true),
      ],
      (libelle: tr(context, "Précision des passes"), a: sa?.passAccuracy, b: sb?.passAccuracy, format: pourcent, plusEstMieux: true),
      (libelle: tr(context, "Duels gagnés"), a: sa?.duelsWon, b: sb?.duelsWon, format: entier, plusEstMieux: true),
      (libelle: tr(context, "Cartons jaunes"), a: sa?.yellowCards, b: sb?.yellowCards, format: entier, plusEstMieux: false),
    ];

    Widget joueur(FicheJoueur f) => Expanded(child: Column(children: [
      ClipOval(child: SizedBox(width: 64, height: 64, child: ImageDistante(
        url: f.photo, largeur: 64, hauteur: 64,
        repli: ColoredBox(color: cl.surfaceDeep, child: Icon(Icons.person_rounded, color: cl.textM, size: 36))))),
      const SizedBox(height: 8),
      Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
        style: TextStyle(color: cl.textP, fontSize: 15, fontWeight: FontWeight.w800)),
      if (f.principale != null) ...[
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TeamLogoWidget(url: f.principale!.teamLogo, size: 16),
          const SizedBox(width: 5),
          Flexible(child: Text(f.principale!.team, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cl.textS, fontSize: 12))),
        ]),
        const SizedBox(height: 2),
        Text(f.principale!.league, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: cl.textM, fontSize: 11)),
      ],
    ]));

    Widget valeur(num? v, num? autre, _Ligne l, {required bool droite}) {
      final mieux = v != null && autre != null && v != autre && (l.plusEstMieux ? v > autre : v < autre);
      final texte = v == null ? '–' : l.format(v);
      final style = TextStyle(
        color: mieux ? cl.textP : cl.textS, fontSize: 15,
        fontWeight: mieux ? FontWeight.w800 : FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()]);
      final contenu = l.libelle == tr(context, "Note moyenne") && v != null
          ? PastilleNote(v.toDouble(), taille: 13)
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: mieux ? BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)) : null,
              child: Text(texte, style: style));
      return SizedBox(width: 72, child: Align(
        alignment: droite ? Alignment.centerRight : Alignment.centerLeft, child: contenu));
    }

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        joueur(a),
        Padding(padding: const EdgeInsets.only(top: 22, left: 6, right: 6),
          child: Text('VS', style: TextStyle(color: cl.textM, fontWeight: FontWeight.w800))),
        joueur(b),
      ]),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: cl.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cl.borderSoft, width: 0.8)),
        child: Column(children: [
          for (final (i, l) in lignes.indexed) ...[
            if (i > 0) Divider(height: 1, color: cl.borderSoft),
            Semantics(
              label: '${l.libelle} : ${a.name} ${l.a == null ? '–' : l.format(l.a!)}, ${b.name} ${l.b == null ? '–' : l.format(l.b!)}',
              child: ExcludeSemantics(child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  valeur(l.a, l.b, l, droite: false),
                  Expanded(child: Text(l.libelle, textAlign: TextAlign.center,
                    style: TextStyle(color: cl.textS, fontSize: 13))),
                  valeur(l.b, l.a, l, droite: true),
                ]),
              )),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      Text(tr(context, "Saison {arg0}-{arg1}, compétition principale de chaque joueur.", [a.season, (a.season + 1) % 100]),
        textAlign: TextAlign.center, style: TextStyle(color: cl.textM, fontSize: 12)),
    ]);
  }
}
