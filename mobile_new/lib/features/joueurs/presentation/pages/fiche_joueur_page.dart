import 'package:pronowin/l10n/football_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pronowin/l10n/app_strings.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/image_distante.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../../../shared/widgets/erreur_chargement.dart';
import '../providers/fiche_joueur_provider.dart';
import '../../../pronostics/presentation/widgets/infos_joueurs.dart' show PastilleNote;
import 'comparaison_joueurs_page.dart';

/// Ouvre la fiche d'un joueur. Sans identifiant (joueur que le fournisseur ne
/// numérote pas), il n'y a rien à ouvrir : la ligne reste inerte.
void ouvrirFicheJoueur(BuildContext context, {required int? id, required String nom, String? photo}) {
  if (id == null || id <= 0) return;
  context.push('/joueurs/$id', extra: (nom: nom, photo: photo));
}

/// La fiche d'un joueur : qui il est, sa saison compétition par compétition,
/// ses absences récentes et ses transferts.
///
/// Un nom de joueur s'affichait dans les compositions, les notes, les absences
/// et les palmarès sans rien derrière ; les données existaient chez le
/// fournisseur, sur le même abonnement.
class FicheJoueurPage extends ConsumerStatefulWidget {
  final int id;
  final ApercuJoueur? apercu;
  const FicheJoueurPage({super.key, required this.id, this.apercu});

  @override
  ConsumerState<FicheJoueurPage> createState() => _FicheJoueurPageState();
}

class _FicheJoueurPageState extends ConsumerState<FicheJoueurPage> {
  int _competition = 0;

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final fiche = ref.watch(ficheJoueurProvider(widget.id));

    return Scaffold(
      backgroundColor: cl.bg,
      appBar: AppBar(
        backgroundColor: cl.bg,
        elevation: 0,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(tr(context, "Fiche joueur"),
          style: TextStyle(color: cl.textP, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: fiche.when(
        loading: () => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          _EnTete(nom: widget.apercu?.nom ?? '', photo: widget.apercu?.photo),
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator())),
        ]),
        error: (e, _) => e is JoueurIntrouvable
          ? Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(tr(context, "Ce joueur n'a pas de fiche disponible."),
                textAlign: TextAlign.center,
                style: TextStyle(color: cl.textS, fontSize: 14))))
          : ErreurChargement(
              erreur: e,
              quoi: tr(context, "la fiche du joueur"),
              onRetry: () => ref.invalidate(ficheJoueurProvider(widget.id))),
        data: (f) {
          final indice = _competition.clamp(0, f.stats.isEmpty ? 0 : f.stats.length - 1);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            _EnTete(nom: f.name, photo: f.photo, fiche: f,
              onComparer: () => comparerAvecUnAutre(context, f)),
          if (f.partial) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, "Certaines informations sont momentanément indisponibles."),
                style: TextStyle(color: cl.textS)),
              TextButton(onPressed: () => ref.invalidate(ficheJoueurProvider(widget.id)),
                child: Text(tr(context, "Réessayer"))),
            ])),
            const SizedBox(height: 14),
            _Identite(fiche: f),
            const SizedBox(height: 14),
            _Saison(
              fiche: f,
              indice: indice,
              onChoisir: (i) => setState(() => _competition = i)),
            if (f.absences.isNotEmpty) ...[
              const SizedBox(height: 14),
              _Absences(absences: f.absences),
            ],
            if (f.transferts.isNotEmpty) ...[
              const SizedBox(height: 14),
              _Transferts(transferts: f.transferts),
            ],
          ]);
        },
      ),
    );
  }
}

/// Libellé du poste, depuis la valeur du fournisseur.
String libellePoste(BuildContext context, String? poste) => switch (poste) {
  'Goalkeeper' => tr(context, "Gardien"),
  'Defender'   => tr(context, "Défenseur"),
  'Midfielder' => tr(context, "Milieu"),
  'Attacker'   => tr(context, "Attaquant"),
  _            => '',
};

BoxDecoration _carte(BuildContext context) => BoxDecoration(
  color: context.cl.surface,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: context.cl.borderSoft, width: 0.8));

Widget _titreSection(BuildContext context, String texte) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Text(texte, style: TextStyle(
    color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w700)));

/// L'en-tête (7 novembre 2026, comme Sofascore et FotMob) : la photo et
/// l'écusson du club, le nom, le club et le poste, la note de la saison en
/// pastille de couleur, et la comparaison avec un autre joueur.
class _EnTete extends StatelessWidget {
  final String nom;
  final String? photo;
  final FicheJoueur? fiche;
  final VoidCallback? onComparer;
  const _EnTete({required this.nom, this.photo, this.fiche, this.onComparer});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final principale = fiche?.principale;
    final poste = libellePoste(context, principale?.position);
    final note = principale?.rating;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _carte(context),
      child: Column(children: [
        Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 76, height: 76,
              decoration: BoxDecoration(
                color: cl.surfaceDeep, shape: BoxShape.circle,
                border: Border.all(color: cl.borderSoft)),
              child: ClipOval(child: photo == null
                ? Icon(Icons.person_rounded, color: cl.textM, size: 42)
                : ImageDistante(url: photo, largeur: 76, hauteur: 76,
                    repli: Icon(Icons.person_rounded, color: cl.textM, size: 42))),
            ),
            if (principale?.teamLogo != null)
              Positioned(right: -4, bottom: -2, child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: cl.surface, shape: BoxShape.circle),
                child: TeamLogoWidget(url: principale!.teamLogo, size: 22))),
          ]),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nom, style: TextStyle(color: cl.textP, fontSize: 20, fontWeight: FontWeight.w800)),
            if (principale != null) ...[
              const SizedBox(height: 5),
              Text(
                [principale.team, if (poste.isNotEmpty) poste].join(' · '),
                style: TextStyle(color: cl.textS, fontSize: 13)),
            ],
            if (fiche?.injured == true) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cl.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7)),
                child: Text(tr(context, "Blessé actuellement"),
                  style: TextStyle(color: cl.error, fontSize: 12, fontWeight: FontWeight.w700))),
            ],
          ])),
          if (note != null) ...[
            const SizedBox(width: 8),
            Semantics(
              label: tr(context, "Note moyenne de la saison : {arg0}", [note.toStringAsFixed(2)]),
              child: ExcludeSemantics(child: Column(children: [
                PastilleNote(note, taille: 16),
                const SizedBox(height: 4),
                Text(tr(context, "Note"), style: TextStyle(color: cl.textM, fontSize: 11)),
              ])),
            ),
          ],
        ]),
        if (onComparer != null) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('comparer-joueur'),
              onPressed: onComparer,
              icon: const Icon(Icons.compare_arrows_rounded, size: 18),
              label: Text(tr(context, "Comparer avec un autre joueur")),
              style: OutlinedButton.styleFrom(
                foregroundColor: cl.textP,
                side: BorderSide(color: cl.borderSoft),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Qui il est, en cases (7 novembre 2026) : âge, taille, poids, pays ; la
/// naissance, plus longue, sur toute la largeur.
class _Identite extends StatelessWidget {
  final FicheJoueur fiche;
  const _Identite({required this.fiche});

  /// « 194 » → « 194 cm » ; « 194 cm » reste tel quel.
  static String _unite(String valeur, String unite) =>
      RegExp(r'^\d+$').hasMatch(valeur.trim()) ? '${valeur.trim()} $unite' : valeur;

  @override
  Widget build(BuildContext context) {
    final f = fiche;
    final cl = context.cl;
    final cases = <(String, String)>[
      if (f.age != null) (tr(context, "Âge"), tr(context, "{arg0} ans", [f.age])),
      if (f.height != null) (tr(context, "Taille"), _unite(f.height!, 'cm')),
      if (f.weight != null) (tr(context, "Poids"), _unite(f.weight!, 'kg')),
      if (f.nationality != null) (tr(context, "Nationalité"),
          FootballLabels.country(f.nationality!, language: AppStrings.of(context).locale.languageCode)),
    ];
    final naissance = f.birthDate == null ? null
        : [DateFormat('d MMMM y').format(f.birthDate!), if (f.birthPlace != null) f.birthPlace!].join(' · ');
    if (cases.isEmpty && naissance == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _carte(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (cases.isNotEmpty) LayoutBuilder(builder: (context, c) {
          final parLigne = cases.length >= 4 ? 2 : cases.length;
          final largeur = (c.maxWidth - 8 * (parLigne - 1)) / parLigne;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (libelle, valeur) in cases)
              Container(
                width: largeur,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: cl.surfaceDeep, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(valeur, style: TextStyle(color: cl.textP, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(libelle, style: TextStyle(color: cl.textM, fontSize: 12)),
                ]),
              ),
          ]);
        }),
        if (naissance != null) Padding(
          padding: EdgeInsets.fromLTRB(4, cases.isEmpty ? 4 : 12, 4, 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, "Naissance"), style: TextStyle(color: cl.textM, fontSize: 13)),
            const SizedBox(width: 12),
            Expanded(child: Text(naissance, textAlign: TextAlign.end,
              style: TextStyle(color: cl.textP, fontSize: 13, fontWeight: FontWeight.w600))),
          ]),
        ),
      ]),
    );
  }
}

class _Saison extends StatelessWidget {
  final FicheJoueur fiche;
  final int indice;
  final ValueChanged<int> onChoisir;
  const _Saison({required this.fiche, required this.indice, required this.onChoisir});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final titre = tr(context, "Saison {arg0}-{arg1}", [fiche.season, (fiche.season + 1) % 100]);
    if (fiche.stats.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _carte(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _titreSection(context, titre),
          Text(tr(context, "Pas encore de match joué cette saison."),
            style: TextStyle(color: cl.textM, fontSize: 13)),
        ]),
      );
    }
    final s = fiche.stats[indice];
    final valeurs = <(String, String)>[
      (tr(context, "Matchs"), '${s.appearances}'),
      (tr(context, "Titularisations"), '${s.lineups}'),
      (tr(context, "Minutes"), '${s.minutes}'),
      (tr(context, "Note moyenne"), s.rating?.toStringAsFixed(2) ?? '–'),
      if (s.estGardien) ...[
        (tr(context, "Buts encaissés"), '${s.conceded}'),
        (tr(context, "Arrêts"), '${s.saves}'),
      ] else ...[
        (tr(context, "Buts"), '${s.goals}'),
        (tr(context, "Passes décisives"), '${s.assists}'),
        (tr(context, "Tirs (cadrés)"), '${s.shots} (${s.shotsOn})'),
        (tr(context, "Passes clés"), '${s.keyPasses}'),
        (tr(context, "Dribbles réussis"), '${s.dribblesSuccess}'),
        (tr(context, "Penalties marqués"), '${s.penaltiesScored}'),
      ],
      (tr(context, "Précision des passes"), s.passAccuracy == null ? '–' : '${s.passAccuracy} %'),
      (tr(context, "Duels gagnés"), '${s.duelsWon}'),
      (tr(context, "Cartons jaunes"), '${s.yellowCards}'),
      (tr(context, "Cartons rouges"), '${s.redCards}'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _carte(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _titreSection(context, titre),
        if (fiche.stats.length > 1) ...[
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < fiche.stats.length; i++)
              ChoiceChip(
                key: Key('competition-$i'),
                label: Text(fiche.stats[i].league),
                selected: i == indice,
                onSelected: (_) => onChoisir(i),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                labelStyle: TextStyle(fontSize: 12,
                  fontWeight: i == indice ? FontWeight.w700 : FontWeight.w500,
                  color: i == indice ? cl.textP : cl.textS),
                selectedColor: cl.accent.withValues(alpha: 0.16),
                side: BorderSide(color: i == indice ? cl.accent.withValues(alpha: 0.5) : cl.borderSoft),
              ),
          ]),
          const SizedBox(height: 12),
        ] else ...[
          Row(children: [
            TeamLogoWidget(url: s.leagueLogo, size: 16),
            const SizedBox(width: 6),
            Flexible(child: Text(s.league, style: TextStyle(color: cl.textS, fontSize: 13))),
          ]),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(builder: (context, c) {
          // Deux colonnes : chaque case garde la moitié de la largeur, et
          // le texte agrandi passe à la ligne au lieu de déborder.
          final largeur = (c.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (libelle, valeur) in valeurs)
              Container(
                width: largeur,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cl.surfaceDeep,
                  borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(valeur, style: TextStyle(color: cl.textP, fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(libelle, style: TextStyle(color: cl.textM, fontSize: 12)),
                ]),
              ),
          ]);
        }),
      ]),
    );
  }
}

class _Absences extends StatelessWidget {
  final List<AbsenceJoueur> absences;
  const _Absences({required this.absences});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final format = DateFormat('d MMM y');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _carte(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _titreSection(context, tr(context, "Absences récentes")),
        for (final a in absences)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(a.suspension ? Icons.style_rounded : Icons.healing_rounded,
                size: 17, color: a.suspension ? cl.warning : cl.error),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(FootballLabels.absence(a.motif).text, style: TextStyle(color: cl.textP, fontSize: 13, fontWeight: FontWeight.w600)),
                if (a.debut != null)
                  Text(
                    a.fin != null
                      ? tr(context, "Du {arg0} au {arg1}", [format.format(a.debut!), format.format(a.fin!)])
                      : tr(context, "Depuis le {arg0}", [format.format(a.debut!)]),
                    style: TextStyle(color: cl.textM, fontSize: 12)),
              ])),
            ]),
          ),
      ]),
    );
  }
}

class _Transferts extends StatelessWidget {
  final List<TransfertJoueur> transferts;
  const _Transferts({required this.transferts});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final format = DateFormat('MMM y');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _carte(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _titreSection(context, tr(context, "Transferts")),
        for (final t in transferts)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              label: tr(context, "{arg0} : de {arg1} à {arg2}, {arg3}",
                [t.date == null ? '' : format.format(t.date!), t.depuis, t.vers, FootballLabels.transfer(t.type).text]),
              excludeSemantics: true,
              child: Row(children: [
                SizedBox(width: 62, child: Text(t.date == null ? '' : format.format(t.date!),
                  style: TextStyle(color: cl.textM, fontSize: 12))),
                TeamLogoWidget(url: t.depuisLogo, size: 18),
                const SizedBox(width: 6),
                Flexible(child: Text(t.depuis, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cl.textS, fontSize: 12))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward_rounded, size: 14, color: cl.textM)),
                TeamLogoWidget(url: t.versLogo, size: 18),
                const SizedBox(width: 6),
                Flexible(child: Text(t.vers, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cl.textP, fontSize: 12, fontWeight: FontWeight.w600))),
                const SizedBox(width: 6),
                Text(FootballLabels.transfer(t.type).text, style: TextStyle(color: cl.textM, fontSize: 11)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Rend une ligne de joueur touchable : elle ouvre sa fiche. Sans identifiant,
/// la ligne reste telle quelle — rien à ouvrir.
class LienJoueur extends StatelessWidget {
  final int? id;
  final String nom;
  final String? photo;
  final Widget child;
  final BorderRadius rayon;
  const LienJoueur({
    super.key, required this.id, required this.nom, this.photo, required this.child,
    this.rayon = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  Widget build(BuildContext context) {
    if (id == null || id! <= 0) return child;
    return Semantics(
      button: true,
      onTapHint: tr(context, "ouvrir la fiche du joueur"),
      child: InkWell(
        borderRadius: rayon,
        onTap: () => ouvrirFicheJoueur(context, id: id, nom: nom, photo: photo),
        child: child,
      ),
    );
  }
}
