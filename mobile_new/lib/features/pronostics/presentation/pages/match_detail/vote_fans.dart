part of '../match_detail_page.dart';

/// « Qui va gagner ? » — le vote des fans avant le match (26 octobre 2026),
/// comme sur Sofascore.
///
/// Avant de voter : trois boutons, l'équipe à domicile, le nul, l'équipe à
/// l'extérieur. Ensuite, la répartition, son propre vote en évidence ; on
/// peut changer d'avis jusqu'au coup d'envoi. Une fois le match commencé,
/// les votes sont clos et la répartition reste visible. Ce n'est pas un pari :
/// rien n'est misé, aucune cote — la carte s'affiche aussi sur iPhone.
class _VoteFans extends ConsumerStatefulWidget {
  final MatchEntity match;
  const _VoteFans({required this.match});

  @override
  ConsumerState<_VoteFans> createState() => _VoteFansState();
}

class _VoteFansState extends ConsumerState<_VoteFans> {
  /// La répartition rendue par le serveur après un vote : affichée tout de
  /// suite, sans attendre une nouvelle lecture.
  VotesMatch? _apresVote;
  String? _envoi;
  String? _erreur;

  Future<void> _voter(String choix) async {
    if (_envoi != null) return;
    HapticFeedback.selectionClick();
    final match = widget.match;
    // Ouvert aux invités en lecture ; voter exige un compte.
    if (!ref.read(effectiveLoggedInProvider)) {
      context.push('/auth/email?from=${Uri.encodeComponent('/pronostics/${match.id}')}');
      return;
    }
    final clos = tr(context, "Les votes sont clos : le match a commencé.");
    final impossible = tr(context, "Vote impossible pour l'instant.");
    setState(() { _envoi = choix; _erreur = null; });
    try {
      final r = await ref.read(voterMatchProvider)(match.id, choix);
      if (!mounted) return;
      setState(() { _apresVote = r; _envoi = null; });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() { _envoi = null; _erreur = e.response?.statusCode == 409 ? clos : impossible; });
      if (e.response?.statusCode == 409) ref.invalidate(votesMatchProvider(match.id));
    } catch (_) {
      if (!mounted) return;
      setState(() { _envoi = null; _erreur = impossible; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final v = _apresVote ?? ref.watch(votesMatchProvider(match.id)).valueOrNull;
    // Serveur muet, ou votes clos sans un seul vote : rien à montrer.
    if (v == null || (!v.ouvert && v.total == 0)) return const SizedBox.shrink();
    final resultats = v.monVote != null || !v.ouvert;
    final compte = AppStrings.of(context);

    final options = [
      ('1', match.homeTeam, match.homeTeamLogo, v.pDom),
      ('N', tr(context, "Nul"), null, v.pNul),
      ('2', match.awayTeam, match.awayTeamLogo, v.pExt),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        key: const Key('vote-fans'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cl.border, width: 0.8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.how_to_vote_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(context, "Qui va gagner ?"), style: TextStyle(
              color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w800))),
            if (resultats)
              Text(compte.count(v.total, one: '{arg0} vote', other: '{arg0} votes'),
                style: TextStyle(color: context.cl.textM, fontSize: 12)),
          ]),
          const SizedBox(height: 12),
          if (!resultats)
            // Avant de voter : les trois choix, sans la répartition.
            Row(children: [
              for (final (i, (choix, libelle, logo, _)) in options.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _BoutonVote(
                  cle: Key('vote-$choix'), libelle: libelle, logo: logo, nul: choix == 'N',
                  enCours: _envoi == choix, onTap: () => _voter(choix))),
              ],
            ])
          else
            for (final (choix, libelle, logo, pct) in options)
              _BarreVote(
                cle: Key('vote-part-$choix'),
                libelle: libelle, logo: logo, pourcentage: pct,
                choisi: v.monVote == choix,
                // Ouvert : un autre choix change le vote.
                onTap: v.ouvert && v.monVote != choix ? () => _voter(choix) : null),
          if (_erreur != null) ...[
            const SizedBox(height: 8),
            Text(_erreur!, key: const Key('vote-erreur'),
              style: TextStyle(color: context.cl.error, fontSize: 12.5)),
          ] else if (resultats) ...[
            const SizedBox(height: 6),
            Text(v.ouvert ? tr(context, "Tu peux changer d'avis jusqu'au coup d'envoi.") : tr(context, "Votes clos."),
              style: TextStyle(color: context.cl.textM, fontSize: 12)),
          ],
        ]),
      ),
    );
  }
}

class _BoutonVote extends StatelessWidget {
  final Key cle;
  final String libelle;
  final String? logo;
  final bool nul, enCours;
  final VoidCallback onTap;
  const _BoutonVote({required this.cle, required this.libelle, required this.logo,
    required this.nul, required this.enCours, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: libelle,
    child: Material(
      color: context.cl.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: cle,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: enCours ? AppColors.primary : context.cl.border, width: enCours ? 1.4 : 0.8)),
          child: ExcludeSemantics(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (enCours)
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
            else if (nul)
              Icon(Icons.drag_handle_rounded, size: 22, color: context.cl.textS)
            else
              TeamLogoWidget(url: logo, size: 22),
            const SizedBox(height: 6),
            Text(libelle, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: TextStyle(color: context.cl.textP, fontSize: 12, fontWeight: FontWeight.w700, height: 1.2)),
          ])),
        ),
      ),
    ),
  );
}

class _BarreVote extends StatelessWidget {
  final Key cle;
  final String libelle;
  final String? logo;
  final int pourcentage;
  final bool choisi;
  final VoidCallback? onTap;
  const _BarreVote({required this.cle, required this.libelle, required this.logo,
    required this.pourcentage, required this.choisi, this.onTap});

  @override
  Widget build(BuildContext context) {
    final couleur = choisi ? AppColors.primary : context.cl.textM;
    return Semantics(
      button: onTap != null,
      selected: choisi,
      label: tr(context, "{arg0} : {arg1} %", [libelle, pourcentage]),
      hint: choisi ? tr(context, "Ton vote") : null,
      child: InkWell(
        key: cle,
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ExcludeSemantics(child: Stack(children: [
            // La piste, pleine largeur : une barre courte se lit comme une
            // part, pas comme un bouton.
            Positioned.fill(child: Container(decoration: BoxDecoration(
              color: context.cl.bg, borderRadius: BorderRadius.circular(10)))),
            // La barre, à la proportion des votes.
            Positioned.fill(child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (pourcentage / 100).clamp(0.0, 1.0),
                child: Container(decoration: BoxDecoration(
                  color: couleur.withValues(alpha: choisi ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(10))),
              ),
            )),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(children: [
                if (logo != null) ...[TeamLogoWidget(url: logo, size: 18), const SizedBox(width: 8)],
                Expanded(child: Text(libelle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
                  color: context.cl.textP, fontSize: 13, fontWeight: choisi ? FontWeight.w800 : FontWeight.w600))),
                if (choisi) ...[
                  const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                ],
                Text('$pourcentage %', style: TextStyle(
                  color: choisi ? context.cl.accent : context.cl.textS, fontSize: 13, fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
          ])),
        ),
      ),
    );
  }
}
