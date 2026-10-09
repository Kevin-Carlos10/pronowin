import 'package:pronowin/l10n/football_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pronowin/l10n/app_strings.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/image_distante.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../../../shared/utils/montant.dart';
import '../../../../shared/widgets/erreur_chargement.dart';
import '../../../joueurs/presentation/pages/fiche_joueur_page.dart';
import '../providers/fiche_equipe_provider.dart';

/// Ouvre la fiche d'une équipe, d'après son identifiant ou, à défaut, son
/// logo. Sans l'un ni l'autre, il n'y a rien à ouvrir.
void ouvrirFicheEquipe(BuildContext context,
    {required String nom, String? logo, String? competition, int? id}) {
  final equipe = id ?? idEquipeDepuisLogo(logo);
  if (equipe == null) return;
  context.push('/equipes/$equipe', extra: (nom: nom, logo: logo, competition: competition));
}

/// Rend un écusson ou un nom d'équipe touchable : il ouvre la fiche.
///
/// [id] quand l'écran le connaît — le classement le reçoit du serveur ;
/// sinon il se lit dans l'adresse du logo.
class LienEquipe extends StatelessWidget {
  final String nom;
  final String? logo, competition;
  final int? id;
  final BorderRadius rayon;
  final Widget child;
  const LienEquipe({super.key, required this.nom, required this.logo, this.competition,
    this.id, this.rayon = const BorderRadius.all(Radius.circular(14)), required this.child});

  @override
  Widget build(BuildContext context) {
    if ((id ?? idEquipeDepuisLogo(logo)) == null) return child;
    return Semantics(
      button: true,
      onTapHint: tr(context, "ouvrir la fiche de l'équipe"),
      child: InkWell(
        borderRadius: rayon,
        onTap: () => ouvrirFicheEquipe(context, nom: nom, logo: logo, competition: competition, id: id),
        child: child,
      ),
    );
  }
}

/// La fiche d'une équipe : le club, son bilan de la saison, son stade, son
/// entraîneur et son effectif — chaque joueur ouvre sa propre fiche.
class FicheEquipePage extends ConsumerWidget {
  final int id;
  final ApercuEquipe? apercu;
  const FicheEquipePage({super.key, required this.id, this.apercu});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cl = context.cl;
    final cle = (id: id, competition: apercu?.competition);
    final fiche = ref.watch(ficheEquipeProvider(cle));

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
        title: Text(tr(context, "Fiche équipe"),
          style: TextStyle(color: cl.textP, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: fiche.when(
        loading: () => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          _EnTete(nom: apercu?.nom ?? '', logo: apercu?.logo),
          const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator())),
        ]),
        error: (e, _) => e is EquipeIntrouvable
          ? Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(tr(context, "Cette équipe n'a pas de fiche disponible."),
                textAlign: TextAlign.center, style: TextStyle(color: cl.textS, fontSize: 14))))
          : ErreurChargement(
              erreur: e, quoi: tr(context, "la fiche de l'équipe"),
              onRetry: () => ref.invalidate(ficheEquipeProvider(cle))),
        data: (f) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          _EnTete(nom: f.name, logo: f.logo ?? apercu?.logo, fiche: f),
          if (f.partial) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, "Certaines informations sont momentanément indisponibles."),
                style: TextStyle(color: cl.textS)),
              TextButton(onPressed: () => ref.invalidate(ficheEquipeProvider(cle)),
                child: Text(tr(context, "Réessayer"))),
            ])),
          if (f.bilan != null) ...[const SizedBox(height: 14), _Saison(fiche: f)],
          if (f.venue != null || f.coach != null) ...[const SizedBox(height: 14), _StadeEtEntraineur(fiche: f)],
          if (f.squad.isNotEmpty) ...[const SizedBox(height: 14), _Effectif(joueurs: f.squad)],
        ]),
      ),
    );
  }
}

BoxDecoration _carte(BuildContext context) => BoxDecoration(
  color: context.cl.surface,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: context.cl.borderSoft, width: 0.8));

Widget _titre(BuildContext context, String texte) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Text(texte, style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w700)));

class _EnTete extends StatelessWidget {
  final String nom;
  final String? logo;
  final FicheEquipe? fiche;
  const _EnTete({required this.nom, this.logo, this.fiche});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final details = [
      if (fiche?.country != null) FootballLabels.country(fiche!.country!),
      if (fiche?.founded != null) tr(context, "fondé en {arg0}", [fiche!.founded]),
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _carte(context),
      child: Row(children: [
        TeamLogoWidget(url: logo, size: 64),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nom, style: TextStyle(color: cl.textP, fontSize: 19, fontWeight: FontWeight.w700)),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(details, style: TextStyle(color: cl.textS, fontSize: 13)),
          ],
        ])),
      ]),
    );
  }
}

class _Saison extends StatelessWidget {
  final FicheEquipe fiche;
  const _Saison({required this.fiche});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final b = fiche.bilan!;
    final titre = fiche.season == null
        ? tr(context, "Cette saison")
        : tr(context, "Saison {arg0}-{arg1}", [fiche.season, (fiche.season! + 1) % 100]);
    // Les cinq derniers résultats, du plus ancien au plus récent.
    final forme = (b.forme ?? '').split('').where((c) => 'WDL'.contains(c)).toList();
    final derniers = forme.length > 5 ? forme.sublist(forme.length - 5) : forme;

    Widget tuile(String valeur, String libelle, [Color? couleur]) => Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(color: cl.surfaceDeep, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(valeur, style: TextStyle(color: couleur ?? cl.textP, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(libelle, textAlign: TextAlign.center, style: TextStyle(color: cl.textM, fontSize: 11)),
      ]),
    ));

    final lignes = <(String, String)>[
      (tr(context, "Buts marqués par match"), b.butsPour),
      (tr(context, "Buts encaissés par match"), b.butsContre),
      (tr(context, "Matchs sans encaisser"), '${b.cleanSheets}'),
      (tr(context, "Matchs sans marquer"), '${b.sansMarquer}'),
      if (b.systeme != null) (tr(context, "Système le plus utilisé"), b.systeme!),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _carte(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _titre(context, titre),
        Row(children: [
          tuile('${b.joues}', tr(context, "Joués")),
          const SizedBox(width: 6),
          tuile('${b.victoires}', tr(context, "Victoires"), cl.success),
          const SizedBox(width: 6),
          tuile('${b.nuls}', tr(context, "Nuls"), cl.warning),
          const SizedBox(width: 6),
          tuile('${b.defaites}', tr(context, "Défaites"), cl.error),
        ]),
        if (derniers.isNotEmpty) ...[
          const SizedBox(height: 14),
          Semantics(
            label: tr(context, "Forme récente : {arg0}", [derniers.map((c) => switch (c) {
              'W' => tr(context, "victoire"), 'D' => tr(context, "nul"), _ => tr(context, "défaite"),
            }).join(', ')]),
            excludeSemantics: true,
            child: Row(children: [
              Text(tr(context, "Forme"), style: TextStyle(color: cl.textM, fontSize: 12.5)),
              const SizedBox(width: 10),
              for (final c in derniers)
                Container(
                  width: 24, height: 24,
                  margin: const EdgeInsets.only(right: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (c == 'W' ? cl.success : c == 'D' ? cl.warning : cl.error).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6)),
                  child: Text(c == 'W' ? tr(context, "V") : c == 'D' ? tr(context, "N") : tr(context, "D"),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: c == 'W' ? cl.success : c == 'D' ? cl.warning : cl.error)),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        for (final (libelle, valeur) in lignes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(child: Text(libelle, style: TextStyle(color: cl.textS, fontSize: 12.5))),
              const SizedBox(width: 10),
              Text(valeur, style: TextStyle(color: cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }
}

class _StadeEtEntraineur extends StatelessWidget {
  final FicheEquipe fiche;
  const _StadeEtEntraineur({required this.fiche});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final v = fiche.venue;
    final c = fiche.coach;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _carte(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (v != null) ...[
          _titre(context, tr(context, "Stade")),
          if (v.image != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(aspectRatio: 16 / 9,
                child: ImageDistante(url: v.image, largeur: double.infinity, hauteur: double.infinity,
                  repli: Container(color: cl.surfaceDeep)))),
            const SizedBox(height: 10),
          ],
          Text(v.name ?? '', style: TextStyle(color: cl.textP, fontSize: 14, fontWeight: FontWeight.w700)),
          Text([
            if (v.city != null) v.city!,
            if (v.capacity != null) tr(context, "{arg0} places", [montantExact(v.capacity!)]),
          ].join(' · '), style: TextStyle(color: cl.textS, fontSize: 12.5)),
        ],
        if (v != null && c != null) const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider(height: 1)),
        if (c != null) ...[
          _titre(context, tr(context, "Entraîneur")),
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: cl.surfaceDeep, shape: BoxShape.circle),
              child: ClipOval(child: c.photo == null
                ? Icon(Icons.person_rounded, color: cl.textM)
                : ImageDistante(url: c.photo, largeur: 44, hauteur: 44,
                    repli: Icon(Icons.person_rounded, color: cl.textM)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: TextStyle(color: cl.textP, fontSize: 14, fontWeight: FontWeight.w700)),
              Text([
                if (c.nationality != null) FootballLabels.country(c.nationality!),
                if (c.age != null) tr(context, "{arg0} ans", [c.age]),
              ].join(' · '), style: TextStyle(color: cl.textS, fontSize: 12.5)),
            ])),
          ]),
        ],
      ]),
    );
  }
}

class _Effectif extends StatelessWidget {
  final List<JoueurEffectif> joueurs;
  const _Effectif({required this.joueurs});

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final groupes = <(String, String)>[
      ('Goalkeeper', tr(context, "Gardiens")),
      ('Defender', tr(context, "Défenseurs")),
      ('Midfielder', tr(context, "Milieux")),
      ('Attacker', tr(context, "Attaquants")),
    ];
    final connus = groupes.map((g) => g.$1).toSet();
    final autres = joueurs.where((j) => !connus.contains(j.position)).toList();

    Widget ligne(JoueurEffectif j) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: LienJoueur(id: j.id, nom: j.name, photo: j.photo,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 26, child: Text(j.number == null ? '' : '${j.number}',
              style: TextStyle(color: cl.textM, fontSize: 12, fontWeight: FontWeight.w700))),
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: cl.surfaceDeep, shape: BoxShape.circle),
              child: ClipOval(child: j.photo == null
                ? Icon(Icons.person_rounded, color: cl.textM, size: 17)
                : ImageDistante(url: j.photo, largeur: 30, hauteur: 30,
                    repli: Icon(Icons.person_rounded, color: cl.textM, size: 17)))),
            const SizedBox(width: 10),
            Expanded(child: Text(j.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cl.textP, fontSize: 13, fontWeight: FontWeight.w600))),
            if (j.age != null)
              Text(tr(context, "{arg0} ans", [j.age]), style: TextStyle(color: cl.textM, fontSize: 11.5)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: cl.textM),
          ]),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _carte(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _titre(context, tr(context, "Effectif")),
        for (final (poste, libelle) in groupes)
          if (joueurs.any((j) => j.position == poste)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Text(libelle.toUpperCase(),
                style: TextStyle(color: cl.textM, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8))),
            for (final j in joueurs.where((j) => j.position == poste)) ligne(j),
          ],
        if (autres.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text(tr(context, "Autres").toUpperCase(),
              style: TextStyle(color: cl.textM, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8))),
          for (final j in autres) ligne(j),
        ],
      ]),
    );
  }
}
